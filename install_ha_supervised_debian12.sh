#!/usr/bin/env bash
set -euo pipefail

# Home Assistant Supervised - Install tout-en-un pour Debian 12
# - Configure NetworkManager + systemd-resolved
# - Propose DHCP ou IP fixe (IP/MASK/GW/DNS)
# - Installe Docker
# - Installe OS Agent 1.7.2 adapté à l'architecture
# - Installe supervised-installer et passe MACHINE automatiquement (surcharge possible)
#
# Variables d'env (optionnelles, sinon prompts):
#   IFACE=enp1s0
#   MODE=dhcp|static
#   IP=192.168.10.50
#   MASK=24|255.255.255.0
#   GW=192.168.10.1
#   DNS="192.168.10.1,1.1.1.1"   # si fourni → on force exactement ces DNS
#   MACHINE=generic-x86-64|generic-aarch64|...
#   DATA_SHARE=/var/lib/homeassistant
#   SKIP_NET=1 (pour sauter toute config réseau)
#
# Testé pour Debian 12 (bookworm)

red()   { printf "\033[31m%s\033[0m\n" "$*" >&2; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
yellow(){ printf "\033[33m%s\033[0m\n" "$*"; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    red "Ce script doit être exécuté en root."
    exit 1
  fi
}

check_debian12() {
  if ! grep -qi 'debian' /etc/os-release; then
    red "OS non supporté. Utilise Debian 12 (bookworm)."
    exit 1
  fi
  . /etc/os-release
  if [[ "${VERSION_CODENAME:-}" != "bookworm" ]]; then
    red "Cette procédure est prévue pour Debian 12 (bookworm). Détecté: ${VERSION_CODENAME:-inconnu}"
    exit 1
  fi
}

mask_to_prefix() {
  local mask="$1"
  if [[ "$mask" =~ ^[0-9]+$ ]]; then
    echo "$mask"; return
  fi
  IFS=. read -r o1 o2 o3 o4 <<<"$mask"
  local bin=$(printf "%08d%08d%08d%08d" \
      "$(bc <<<"obase=2;$o1")" \
      "$(bc <<<"obase=2;$o2")" \
      "$(bc <<<"obase=2;$o3")" \
      "$(bc <<<"obase=2;$o4")" | tr -d '\n')
  echo "$bin" | tr -cd '1' | wc -c
}

pick_iface() {
  local def_if=""
  def_if=$(ip -o link show | awk -F': ' '$2!="lo"{print $2}' | head -n1)
  if [[ -n "${IFACE:-}" ]]; then
    echo "$IFACE"; return
  fi
  yellow "Interfaces détectées:"
  ip -o link show | awk -F': ' '$2!="lo"{print "- " $2}'
  read -rp "Interface à configurer (ex: enp1s0) [${def_if}]: " ans
  IFACE="${ans:-$def_if}"
  echo "$IFACE"
}

prompt_network() {
  if [[ "${SKIP_NET:-0}" == "1" ]]; then
    yellow "⚠️  Configuration réseau sautée (SKIP_NET=1)."
    return
  fi

  IFACE="$(pick_iface)"

  if [[ -z "${MODE:-}" ]]; then
    read -rp "Mode réseau pour ${IFACE} ? (dhcp/static) [dhcp]: " MODE
    MODE="${MODE:-dhcp}"
  fi
  MODE=$(echo "$MODE" | tr '[:upper:]' '[:lower:]')

  if [[ "$MODE" == "static" ]]; then
    if [[ -z "${IP:-}"   ]]; then read -rp "Adresse IP (ex 192.168.10.50): " IP; fi
    if [[ -z "${MASK:-}" ]]; then read -rp "Masque (CIDR 24 ou 255.255.255.0): " MASK; fi
    if [[ -z "${GW:-}"   ]]; then read -rp "Passerelle (ex 192.168.10.1): " GW; fi
    # DNS OBLIGATOIRE en static (pas de défaut/passerelle)
    if [[ -z "${DNS:-}"  ]]; then read -rp "DNS (liste séparée par des virgules, ex 192.168.10.1,1.1.1.1): " DNS; fi
  else
    MODE="dhcp"
    # En DHCP, si DNS précisé par l'utilisateur, on forcera ces DNS (ignore-auto-dns yes).
    # Sinon, on laisse le DNS fourni par le DHCP.
  fi
}

ensure_resolved_symlink() {
  if [[ ! -L /etc/resolv.conf ]]; then
    yellow "Mise en place de /etc/resolv.conf pour systemd-resolved…"
    if [[ -f /etc/resolv.conf ]]; then mv -f /etc/resolv.conf /etc/resolv.conf.backup.$(date +%s) || true; fi
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
  fi
}

revive_resolved() {
  systemctl unmask systemd-resolved || true
  systemctl enable systemd-resolved || true
  systemctl restart systemd-resolved || true
}

ensure_nm_and_resolved() {
  yellow "Installation NetworkManager + systemd-resolved…"
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y network-manager systemd-resolved

  ensure_resolved_symlink
  revive_resolved

  if systemctl is-enabled networking.service &>/dev/null; then
    yellow "Désactivation de ifupdown (networking.service)…"
    systemctl disable --now networking.service || true
  fi

  if [[ -f /etc/network/interfaces ]]; then
    mv /etc/network/interfaces /etc/network/interfaces.disabled.$(date +%s)
  fi

  systemctl restart NetworkManager
}

nm_find_or_create_con() {
  local con=""
  con=$(nmcli -t -f NAME,DEVICE con show | awk -F: -v d="$IFACE" '$2==d{print $1;exit}')
  if [[ -z "$con" ]]; then
    con="hass-${IFACE}"
    nmcli con add type ethernet ifname "$IFACE" con-name "$con" || true
  fi
  echo "$con"
}

apply_network_nmcli() {
  if [[ "${SKIP_NET:-0}" == "1" ]]; then return; fi

  yellow "Application de la configuration réseau via nmcli…"
  local con; con="$(nm_find_or_create_con)"

  if [[ "$MODE" == "dhcp" ]]; then
    if [[ -n "${DNS:-}" ]]; then
      nmcli con mod "$con" ipv4.method auto ipv4.dns "$(echo "$DNS" | tr ',' ' ')" ipv4.ignore-auto-dns yes
    else
      nmcli con mod "$con" ipv4.method auto ipv4.dns "" ipv4.ignore-auto-dns no
    fi
  else
    local prefix; prefix="$(mask_to_prefix "$MASK")"
    nmcli con mod "$con" ipv4.method manual \
      ipv4.addresses "${IP}/${prefix}" \
      ipv4.gateway "${GW}" \
      ipv4.dns "$(echo "$DNS" | tr ',' ' ')" \
      ipv4.ignore-auto-dns yes
  fi

  nmcli con mod "$con" ipv6.method auto || true

  nmcli con down "$con" || true
  nmcli con up "$con"

  green "Réseau appliqué sur ${IFACE}. Adresse(s) actuelle(s) :"
  ip -4 addr show dev "$IFACE" | awk '/inet /{print " - "$2}'
}

validate_dns_strict() {
  yellow "Validation stricte du DNS…"
  # resolvectl doit répondre
  if ! resolvectl status >/dev/null 2>&1; then
    red "systemd-resolved ne répond pas. Pas de fallback : corrige la config DNS/NetworkManager."
    exit 1
  fi

  # Si l'utilisateur a fourni un DNS, on vérifie qu'il est bien pris par resolved
  if [[ -n "${DNS:-}" ]]; then
    # Normalise les DNS utilisateur (espaces)
    local dns_expected; dns_expected="$(echo "$DNS" | tr ',' ' ' | xargs)"
    local dns_seen; dns_seen="$(resolvectl status | awk '/DNS Servers:/{print $3,$4,$5,$6,$7,$8,$9,$10}' | xargs)"

    # Test très simple : chaque DNS attendu doit apparaître dans la liste vue par resolved
    for d in $dns_expected; do
      if ! grep -qw "$d" <<<"$dns_seen"; then
        red "Le DNS '$d' n'est pas utilisé par systemd-resolved (vu: $dns_seen)."
        red "Aucun fallback appliqué. Corrige manuellement (nmcli) et relance."
        exit 1
      fi
    done
    green "DNS validé : $dns_expected"
  else
    green "DNS non forcé par l'utilisateur → on utilise ceux du DHCP/auto."
  fi
}

install_deps() {
  yellow "Installation dépendances (udisks2, curl, lsb-release, jq, dbus, apparmor, avahi-daemon, ca-certificates, bc)…"
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    udisks2 curl lsb-release jq dbus apparmor apparmor-utils avahi-daemon ca-certificates bc
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    green "Docker déjà installé."
    return
  fi
  yellow "Installation Docker (get.docker.com)…"
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
}

arch_map_osagent() {
  local a; a=$(dpkg --print-architecture)
  case "$a" in
    amd64) echo "linux_x86_64" ;;
    arm64) echo "linux_aarch64" ;;
    i386)  echo "linux_i386" ;;
    armhf) echo "linux_armv7" ;;
    armel) echo "linux_armv6" ;;
    *) red "Architecture non supportée automatiquement: $a"; exit 1 ;;
  esac
}

install_os_agent() {
  local ver="1.7.2"
  local suffix; suffix="$(arch_map_osagent)"
  local url="https://github.com/home-assistant/os-agent/releases/download/${ver}/os-agent_${ver}_${suffix}.deb"
  local deb="/tmp/os-agent_${ver}_${suffix}.deb"

  if busctl introspect --system io.hass.os /io/hass/os >/div/null 2>&1; then
    green "OS Agent déjà en place (io.hass.os)."
    return
  fi

  yellow "Téléchargement OS Agent ${ver} (${suffix})…"
  curl -fL -o "$deb" "$url"
  yellow "Installation OS Agent…"
  dpkg -i "$deb" || (apt-get -f install -y && dpkg -i "$deb")

  if busctl introspect --system io.hass.os /io/hass/os >/dev/null 2>&1; then
    green "OS Agent OK."
  else
    red "OS Agent ne répond pas (io.hass.os). Vérifie journaux: journalctl -u dbus -u systemd-*."
  fi
}

pick_machine() {
  if [[ -n "${MACHINE:-}" ]]; then echo "$MACHINE"; return; fi
  local a; a=$(dpkg --print-architecture)
  case "$a" in
    amd64) MACHINE="generic-x86-64" ;;
    arm64) MACHINE="generic-aarch64" ;;
    i386)  MACHINE="qemux86" ;;
    armhf) MACHINE="raspberrypi3" ;;
    *) MACHINE="generic-x86-64" ;;
  esac
  echo "$MACHINE"
}

install_supervised() {
  local deb="/tmp/homeassistant-supervised.deb"
  yellow "Téléchargement du package supervised-installer (dernier) …"
  curl -fL -o "$deb" "https://github.com/home-assistant/supervised-installer/releases/latest/download/homeassistant-supervised.deb"
 
  # Dépendance obligatoire pour Home Assistant supervised
  apt-get install -y systemd-journal-remote || true
  
  local machine; machine="$(pick_machine)"

  yellow "Installation Home Assistant Supervised (MACHINE=${machine})…"
  if [[ -n "${DATA_SHARE:-}" ]]; then
    env MACHINE="$machine" DATA_SHARE="$DATA_SHARE" dpkg --force-confdef --force-confold -i "$deb" || (apt-get -f install -y && env MACHINE="$machine" DATA_SHARE="$DATA_SHARE" dpkg -i "$deb")
  else
    env MACHINE="$machine" dpkg --force-confdef --force-confold -i "$deb" || (apt-get -f install -y && env MACHINE="$machine" dpkg -i "$deb")
  fi
}

main() {
  require_root
  check_debian12

  yellow "=== Étape 1/6 : Réseau (NetworkManager + systemd-resolved) ==="
  prompt_network
  ensure_nm_and_resolved
  apply_network_nmcli
  validate_dns_strict

  yellow "=== Étape 2/6 : Dépendances ==="
  install_deps

  yellow "=== Étape 3/6 : Docker ==="
  install_docker

  yellow "=== Étape 4/6 : OS Agent ==="
  install_os_agent

  yellow "=== Étape 5/6 : Home Assistant Supervised ==="
  install_supervised

  green "=== Étape 6/6 : Vérifications rapides ==="
  local ip_now
  ip_now=$(ip -4 addr show "${IFACE:-$(ip -o -4 route show default | awk '{print $5;exit}')}" 2>/dev/null | awk '/inet /{print $2}' | head -n1)
  yellow "Accès à Home Assistant (peut prendre quelques minutes au premier démarrage) :"
  echo "  → http://$(echo "$ip_now" | cut -d/ -f1):8123"
  echo
  echo "Diagnostic :"
  echo "  - resolvectl status"
  echo "  - journalctl -fu hassio-supervisor"
  echo "  - docker ps"
  echo "  - busctl introspect --system io.hass.os /io/hass/os"
}

main "$@"
