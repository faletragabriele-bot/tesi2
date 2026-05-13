#!/usr/bin/env bash
# =============================================================================
# custom_iso.sh — crea da 0 una iso con autoinstall
# =============================================================================
# Uso: sudo ./custom_iso.sh
# Dipendenze: xorriso, mtools, whois (mkpasswd), python3
# =============================================================================

set -euo pipefail

# ─── Configurazione ───────────────────────────────────────────────────────────
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colori per output
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ─── Controlli preliminari ────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || error "Esegui lo script come root: sudo $0"

for cmd in xorriso mksquashfs unsquashfs 7z; do
  command -v "$cmd" &>/dev/null || warn "Comando '$cmd' non trovato — potrebbe servire."
done
command -v xorriso &>/dev/null || error "xorriso non trovato. Installa con: apt install xorriso"

# ─── Funzione hash password ───────────────────────────────────────────────────
hash_password() {
  local pwd="$1"
  if command -v mkpasswd &>/dev/null; then
    mkpasswd -m sha-512 "$pwd"
  else
    python3 -c "
import crypt, sys
pwd = sys.argv[1]
print(crypt.crypt(pwd, crypt.mksalt(crypt.METHOD_SHA512)))
" "$pwd"
  fi
}

# ─── Pulizia e preparazione directory ────────────────────────────────────────
info "Preparazione directory di lavoro..."
temp_dir=$(mktemp -d)
mkdir -p "$temp_dir/iso"
mkdir -p "$temp_dir/nocloud"

# Pulizia automatica in caso di errore
trap 'warn "Errore — pulizia $temp_dir..."; rm -rf "$temp_dir"' ERR

# ─── Generazione autoOpenNebula.sh ────────────────────────────────────────────
cat > "$temp_dir/nocloud/autoOpenNebula.sh" << "EOF"
#!/usr/bin/env bash
set -euo pipefail
wget -4 -O- https://downloads.opennebula.io/repo/repo2.key | gpg --dearmor --yes --output /etc/apt/trusted.gpg.d/opennebula.gpg
echo "deb https://downloads.opennebula.io/repo/7.0/Ubuntu/24.04 stable opennebula" | tee /etc/apt/sources.list.d/opennebula.list
apt update
apt install -y opennebula opennebula-fireedge opennebula-guacd
apt install -y opennebula-node-kvm
sudo -u oneadmin ssh-keygen -t rsa -N "" -f /var/lib/one/.ssh/id_rsa
sudo -u oneadmin cp /var/lib/one/.ssh/id_rsa.pub /var/lib/one/.ssh/authorized_keys
systemctl enable --now opennebula opennebula-fireedge
apt update && apt upgrade -y && apt autoremove -y
EOF

touch "$temp_dir/nocloud/meta-data"

# ─── Configurazione interattiva ───────────────────────────────────────────────
info "Configurazione interattiva user-data per autoinstall..."

read -p "Lingua del sistema installato (default: it_IT.UTF-8): " lingua
lingua=${lingua:-it_IT.UTF-8}

read -p "Fuso orario (default: Europe/Rome): " orazone
orazone=${orazone:-Europe/Rome}

read -p "Layout tastiera (default: it): " keyboard_layout
keyboard_layout=${keyboard_layout:-it}

INTERFACES_LIST=()
while true; do
  read -p "Aggiungi interfaccia di rete (invio per terminare): " iface
  [[ -z "$iface" ]] && break
  INTERFACES_LIST+=("$iface")
done
[[ ${#INTERFACES_LIST[@]} -eq 0 ]] && error "Devi specificare almeno un'interfaccia di rete."

read -p "Indirizzo IP (es. 192.168.1.10): " ip_address
[[ -z "$ip_address" ]] && error "Indirizzo IP obbligatorio."

read -p "Gateway (es. 192.168.1.1): " gateway
[[ -z "$gateway" ]] && error "Gateway obbligatorio."

DNS_LIST=()
while true; do
  read -p "Aggiungi DNS (invio per terminare): " dns
  [[ -z "$dns" ]] && break
  DNS_LIST+=("$dns")
done
[[ ${#DNS_LIST[@]} -eq 0 ]] && DNS_LIST=("8.8.8.8" "8.8.4.4" "1.1.1.1")

read -p "Hostname (default: rootserver): " hostname
hostname=${hostname:-rootserver}

read -p "Username (default: server): " username
username=${username:-server}

read -s -p "Password (default: root@server1234): " password
echo
password=${password:-root@server1234}

info "Calcolo hash password..."
password_hash=$(hash_password "$password")

# ─── Costruzione blocchi YAML per array ───────────────────────────────────────
# Interfacce per la sezione ethernets (es: "      eth0: {}")
YAML_ETHERNETS=""
for iface in "${INTERFACES_LIST[@]}"; do
  YAML_ETHERNETS+="      ${iface}: {}"$'\n'
done

# Interfacce per la sezione bond (es: "          - eth0")
YAML_BOND_IFACES=""
for iface in "${INTERFACES_LIST[@]}"; do
  YAML_BOND_IFACES+="          - ${iface}"$'\n'
done

PRIMARY_IFACE="${INTERFACES_LIST[0]}"

# DNS come lista YAML inline (es: [8.8.8.8, 8.8.4.4])
DNS_INLINE=$(printf '%s, ' "${DNS_LIST[@]}")
DNS_INLINE="[${DNS_INLINE%, }]"

# ─── Generazione user-data ────────────────────────────────────────────────────
info "Generazione user-data..."

# NOTA: heredoc senza virgolette → le variabili bash vengono espanse
cat > "$temp_dir/nocloud/user-data" << EOF
#cloud-config
autoinstall:
  version: 1

  # ─── CONFERME ────────────────────────────────────────────
  interactive-sections: []

  # ─── LOCALE ──────────────────────────────────────────────
  locale: ${lingua}
  timezone: ${orazone}

  # ─── TASTIERA ────────────────────────────────────────────
  keyboard:
    layout: ${keyboard_layout}
    variant: ""

  # ─── RETE ────────────────────────────────────────────────
  network:
    version: 2
    ethernets:
${YAML_ETHERNETS}
    bonds:
      bond0:
        interfaces:
${YAML_BOND_IFACES}
        parameters:
          mode: active-backup
          primary: ${PRIMARY_IFACE}
        dhcp4: false
        addresses:
          - ${ip_address}/24
        routes:
          - to: default
            via: ${gateway}
        nameservers:
          addresses: ${DNS_INLINE}

  # ─── IDENTITÀ ────────────────────────────────────────────
  identity:
    hostname: ${hostname}
    username: ${username}
    password: "${password_hash}"

  # ─── SSH ─────────────────────────────────────────────────
  ssh:
    install-server: true
    allow-pw: true

  # ─── STORAGE ─────────────────────────────────────────────
  storage:
    layout:
      name: lvm
      match:
        size: largest

  # ─── PACCHETTI ───────────────────────────────────────────
  packages:
    - snapd
    - vim
    - curl
    - git
    - htop
    - net-tools
    - iproute2
    - sed
    - openssh-sftp-server
    - gnupg
    - wget
    - apt-transport-https
    #- emacs
    #- ufw

  package_update: true
  package_upgrade: true

  # ─── COMANDI ─────────────────────────────────────────────
  early-commands:
    - echo "Inizio installazione" > /tmp/install.log

  late-commands:
    - curtin in-target --target=/target -- sed -i 's|autoinstall ds=nocloud\\;s=/cdrom/nocloud/||g' /boot/grub/grub.cfg
    - curtin in-target --target=/target -- sed -i 's|autoinstall||g' /boot/grub/grub.cfg
    - cp /cdrom/nocloud/autoOpenNebula.sh /target/tmp/
    - curtin in-target --target=/target -- bash /tmp/autoOpenNebula.sh
    - curtin in-target --target=/target -- snap install firefox
    - curtin in-target --target=/target -- apt-get install -y ubuntu-desktop
    - curtin in-target --target=/target -- bash -c 'export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get install -y emacs'
    #- curtin in-target --target=/target -- bash -c 'export DEBIAN_FRONTEND=noninteractive && apt-get -o Dpkg::Options::="--force-confnew" install -y emacs'
  # ─── USER-DATA (cloud-init primo avvio) ──────────────────
  user-data:
    runcmd:
      - echo "Sistema pronto!" >> /var/log/firstboot.log
EOF

info "Verifica user-data generato:"
grep -E "locale:|timezone:|hostname:|username:|primary:" "$temp_dir/nocloud/user-data" | sed 's/^/  /'

# ─── Download ISO ─────────────────────────────────────────────────────────────
info "Download ISO originale (amd64)..."
wget -q --show-progress \
  -O "$temp_dir/ubuntu.iso" \
  "https://releases.ubuntu.com/24.04.4/ubuntu-24.04.4-live-server-amd64.iso"
info "Dimensione ISO: $(du -h "$temp_dir/ubuntu.iso" | cut -f1)"

# ─── Estrazione ISO ───────────────────────────────────────────────────────────
info "Estrazione ISO originale..."
xorriso -osirrox on \
  -indev "$temp_dir/ubuntu.iso" \
  -extract / "$temp_dir/iso" \
  2>/dev/null
info "Estrazione completata."
chmod -R u+w "$temp_dir/iso"

# ─── Copia nocloud/ ───────────────────────────────────────────────────────────
info "Copia dei file nocloud..."
cp -r "$temp_dir/nocloud" "$temp_dir/iso/nocloud"
chmod 644 "$temp_dir/iso/nocloud/user-data" \
           "$temp_dir/iso/nocloud/meta-data" \
           "$temp_dir/iso/nocloud/autoOpenNebula.sh"

# ─── Patch GRUB ──────────────────────────────────────────────────────────────
GRUB_CFG="$temp_dir/iso/boot/grub/grub.cfg"
[[ -f "$GRUB_CFG" ]] || error "grub.cfg non trovato: $GRUB_CFG"
info "Patch di grub.cfg..."
cp "$GRUB_CFG" "${GRUB_CFG}.bak"

python3 - "$GRUB_CFG" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

def patch_linux_line(m):
    line = m.group(0)
    if 'autoinstall' in line:
        return line
    if '---' in line:
        line = line.replace('---', 'autoinstall ds=nocloud\\;s=/cdrom/nocloud/ ---')
    else:
        line = line.rstrip() + ' autoinstall ds=nocloud\\;s=/cdrom/nocloud/'
    return line

patched = re.sub(
    r'^\s*(linux|linuxefi)\s+.*vmlinuz.*$',
    patch_linux_line,
    content,
    flags=re.MULTILINE
)

with open(path, 'w') as f:
    f.write(patched)

print(f"  Righe patched: {patched.count('autoinstall')}")
PYEOF

info "Verifica patch grub.cfg:"
grep -n "autoinstall" "$GRUB_CFG" | sed 's/^/  /' || warn "Nessuna riga autoinstall — controlla grub.cfg manualmente."

# ─── Patch ISOLINUX (BIOS legacy) ────────────────────────────────────────────
ISOLINUX_CFG="$temp_dir/iso/isolinux/txt.cfg"
if [[ -f "$ISOLINUX_CFG" ]]; then
  info "Patch isolinux/txt.cfg per boot BIOS legacy..."
  cp "$ISOLINUX_CFG" "${ISOLINUX_CFG}.bak"
  sed -i 's|append  *|append autoinstall ds=nocloud\\;s=/cdrom/nocloud/ |' "$ISOLINUX_CFG" || true
fi

# ─── Estrazione MBR e partizione EFI ─────────────────────────────────────────
info "Lettura MBR e parametri EFI dall'ISO originale..."

MBR_IMG="$temp_dir/mbr.img"
EFI_IMG="$temp_dir/efi.img"

dd if="$temp_dir/ubuntu.iso" bs=1 count=432 of="$MBR_IMG" status=none

SECTOR_SIZE=512
EFI_START_SECTOR=$(sfdisk -d "$temp_dir/ubuntu.iso" 2>/dev/null \
  | awk -F'[=,]' '/type=EF/{gsub(/ /,"",$2); print $2}' | head -1 || echo "")
EFI_SIZE_SECTOR=$(sfdisk -d "$temp_dir/ubuntu.iso" 2>/dev/null \
  | awk -F'[=,]' '/type=EF/{gsub(/ /,"",$4); print $4}' | head -1 || echo "")

if [[ -n "$EFI_START_SECTOR" && -n "$EFI_SIZE_SECTOR" ]]; then
  dd if="$temp_dir/ubuntu.iso" \
     bs=$SECTOR_SIZE \
     skip="$EFI_START_SECTOR" \
     count="$EFI_SIZE_SECTOR" \
     of="$EFI_IMG" \
     status=none
  info "Immagine EFI estratta: offset=$EFI_START_SECTOR settori, size=$EFI_SIZE_SECTOR settori"
  HAS_EFI=1
else
  warn "Partizione EFI non rilevata — boot UEFI potrebbe non funzionare."
  HAS_EFI=0
fi

# ─── Ricostruzione ISO ────────────────────────────────────────────────────────
info "Ricostruzione ISO: $script_dir/ubuntu-custom.iso"
rm -f "$script_dir/ubuntu-custom.iso"

XORRISO_ARGS=(
  xorriso -as mkisofs
  -r
  -V "Ubuntu-Server-24.04.4-auto"
  --modification-date="$(date -u +%Y%m%d%H%M%S)00"
  -o "$script_dir/ubuntu-custom.iso"

  # Boot BIOS (El Torito)
  -b boot/grub/i386-pc/eltorito.img
  -no-emul-boot
  -boot-load-size 4
  -boot-info-table
  --grub2-boot-info

  # MBR per boot da USB
  --grub2-mbr "$MBR_IMG"
  -partition_offset 16
)

if [[ $HAS_EFI -eq 1 ]]; then
  XORRISO_ARGS+=(
    --efi-boot-part
    --efi-boot-image
    --protective-msdos-label
    -append_partition 2 0xef "$EFI_IMG"
  )
fi

XORRISO_ARGS+=(
  -joliet
  -joliet-long
  -full-iso9660-filenames
  "$temp_dir/iso"
)

"${XORRISO_ARGS[@]}"

# ─── Verifica output ──────────────────────────────────────────────────────────
if [[ -f "$script_dir/ubuntu-custom.iso" ]]; then
  SIZE=$(du -sh "$script_dir/ubuntu-custom.iso" | cut -f1)
  info "✅ ISO creata con successo: $script_dir/ubuntu-custom.iso ($SIZE)"
  info ""
  info "Verifica rapida contenuto:"
  xorriso -indev "$script_dir/ubuntu-custom.iso" -find nocloud -exec lsdl -- 2>/dev/null | sed 's/^/  /' || true
else
  error "Qualcosa è andato storto — $script_dir/ubuntu-custom.iso non trovata."
fi

# ─── Pulizia ──────────────────────────────────────────────────────────────────
info "Pulizia directory temporanea..."
rm -rf "$temp_dir"
trap - ERR

info ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info " ISO pronta: $script_dir/ubuntu-custom.iso"
info " Scrivi su USB con:"
info "   sudo dd if=$script_dir/ubuntu-custom.iso of=/dev/sdX bs=4M status=progress oflag=sync"
info " oppure:"
info "   sudo cp $script_dir/ubuntu-custom.iso /dev/sdX && sync"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"