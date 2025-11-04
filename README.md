# ✅ Installation automatique de Home Assistant Supervised sur Debian 12

Ce script permet d’installer **Home Assistant Supervised** sur une machine **Debian 12 (Bookworm)** en **une seule commande**, avec :
- Configuration réseau (DHCP ou IP fixe)
- Activation de NetworkManager + systemd-resolved
- Installation de Docker
- Installation de OS-Agent (nécessaire au Supervisor)
- Installation de Home Assistant Supervised officiel
- Prise en charge de l’architecture (amd64 / arm64 / armhf / i386)

---

## ⚠️ Prérequis

- Debian 12 **fraîchement installée**, à jour (`apt update && apt upgrade`)
- Lancer en **root**
- Avoir **Internet** fonctionnel
- Architecture supportée :
  - `amd64` (PC/serveur classique)
  - `arm64` / `armhf` (Raspberry Pi, ARM SBC)
  - `i386` (32 bits)
- Machine non virtualisée en LXC non privilégié (ou avec `nesting=1` et cgroups activés)

---

## 🚀 Installation rapide (mode auto)

**Sans interaction + IP fixe** :

```bash
IFACE=enp1s0 MODE=static IP=192.168.10.50 MASK=24 GW=192.168.10.1 DNS="192.168.10.1" \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/L4Curtis/HomeAssistantSupervised/main/install_ha_supervised_debian12.sh)"
