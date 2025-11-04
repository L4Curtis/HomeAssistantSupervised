# ✅ Installation automatique de Home Assistant Supervised sur Debian 12

Ce dépôt fournit un script d'installation pour déployer **Home Assistant Supervised** sur une machine **Debian 12 (Bookworm)** en une seule commande. Le script prend en charge :

- Configuration réseau (DHCP ou IP statique)
- Activation de NetworkManager et systemd-resolved
- Installation de Docker (Docker CE)
- Installation de OS-Agent (requis par le Supervisor)
- Installation de Home Assistant Supervised (paquet officiel .deb)
- Support des architectures : amd64, arm64, armhf, i386

---

## ⚠️ Prérequis

- Debian 12 fraîchement installée et à jour :
  - sudo apt update && sudo apt upgrade
- Exécuter le script en tant que root
- Connexion Internet fonctionnelle
- Architectures supportées : `amd64`, `arm64`, `armhf`, `i386`
- Si vous utilisez un conteneur LXC (Proxmox) : le conteneur doit être privileged, avec `nesting=1` et les cgroups activés

Note : l'installation "Supervised" est une méthode avancée et peut être considérée comme non officielle si le système n'est pas strictement conforme (Debian pur, pas Ubuntu ni certains environnements virtualisés restreints).

---

## 🚀 Installation rapide

Remarque : adaptez les variables selon votre réseau et interface.

1) IP statique (sans interaction) :

```bash
IFACE=enp1s0 MODE=static IP=192.168.10.50 MASK=24 GW=192.168.10.1 DNS="192.168.10.1" \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/L4Curtis/HomeAssistantSupervised/main/install_ha_supervised_debian12.sh)"
```

2) DHCP (sans interaction, DNS forcé) :

```bash
IFACE=enp1s0 MODE=dhcp DNS="192.168.10.1" \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/L4Curtis/HomeAssistantSupervised/main/install_ha_supervised_debian12.sh)"
```

3) Mode interactif (le script vous pose des questions) :

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/L4Curtis/HomeAssistantSupervised/main/install_ha_supervised_debian12.sh)"
```

---

## ⚙️ Variables disponibles

- IFACE — ex. `enp1s0` : interface réseau à configurer  
- MODE — `dhcp` ou `static` : mode réseau  
- IP — ex. `192.168.10.50` : adresse IP (si static)  
- MASK — ex. `24` ou `255.255.255.0` : masque réseau  
- GW — ex. `192.168.10.1` : passerelle (si static)  
- DNS — ex. `192.168.10.1,1.1.1.1` : serveurs DNS (obligatoire si static)  
- MACHINE — ex. `generic-x86-64` (détecté automatiquement par défaut) : type de machine pour Home Assistant  
- DATA_SHARE — ex. `/var/lib/homeassistant` : chemin personnalisé pour les données Home Assistant  
- SKIP_NET — si `SKIP_NET=1`, la configuration réseau est ignorée (utile si vous configurez le réseau manuellement)

---

## Que fait le script (résumé)

1. Configuration réseau
   - Active NetworkManager et systemd-resolved
   - Désactive la configuration legacy (/etc/network/interfaces) si présente
   - Crée/mettre à jour la connexion réseau via nmcli (DHCP ou IP statique)
   - Applique exactement les DNS fournis et vérifie que systemd-resolved les utilise

2. Installation des dépendances système
   - Installe les paquets requis : udisks2, curl, lsb-release, jq, dbus, apparmor, apparmor-utils, avahi-daemon, ca-certificates, bc, systemd-journal-remote, etc.

3. Installation de Docker CE
   - Installation via le script officiel get.docker.com

4. Installation de OS-Agent
   - Téléchargement et installation de la version adaptée à l'architecture (ex : os-agent_1.7.2...)

5. Installation de Home Assistant Supervised
   - Téléchargement du paquet homeassistant-supervised.deb
   - Installation avec la variable MACHINE appropriée
   - Ajout/configuration de services système nécessaires (ex. systemd-journal-remote)

---

## 🔑 Accès à Home Assistant

Après l'installation, rendez-vous sur :

http://<IP_DU_SERVEUR>:8123

Exemple : http://192.168.10.50:8123

Temps d'initialisation : prévoir 5 à 10 minutes pour que les conteneurs démarrent et que l'interface soit disponible.

---

## 🔎 Commandes utiles (diagnostic)

- resolvectl status
  - Vérifier l'état DNS et systemd-resolved
- journalctl -fu hassio-supervisor
  - Suivre les logs du Supervisor
- docker ps
  - Voir les conteneurs Docker actifs
- busctl introspect --system io.hass.os /io/hass/os
  - Tester OS-Agent

---

## ⚠️ Avertissement officiel Home Assistant

L'installation Supervised sur Debian est une méthode avancée et n'est pas officiellement recommandée pour tous les environnements. Si le système n'est pas strictement conforme (modifications importantes, composants manquants, environnement virtualisé restrictif), vous pouvez rencontrer des problèmes de compatibilité ou d'update du Supervisor.

---

## ✨ Auteur

- Curtis — L4Curtis  
- Répertoire : https://github.com/L4Curtis/HomeAssistantSupervised
