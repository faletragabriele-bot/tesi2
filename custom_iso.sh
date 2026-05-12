#!/usr/bin/env bash
# =============================================================================
# custom_iso.sh — crea da 0 una iso con autoinstall
# =============================================================================
# Uso: sudo ./custom_iso.sh
# Dipendenze: xorriso, isolinux (syslinux-utils), mtools
# =============================================================================

set -euo pipefail

#https://cdimage.ubuntu.com/ubuntu/releases/24.04.4/release/ubuntu-24.04.4-live-server-arm64.iso

# ─── Configurazione ───────────────────────────────────────────────────────────
#ORIGINAL_ISO="${ORIGINAL_ISO:-/home/gabriele/VirtualBox VMs/ubuntu-24.04.1-live-server-amd64.iso}"
#OUTPUT_ISO="${OUTPUT_ISO:-/home/gabriele/Documents/OS/ubuntu-custom.iso}"
#WORK_DIR="${WORK_DIR:-/home/gabriele/ubuntu-custom}"
#NOCLOUD_SRC="${NOCLOUD_SRC:-/home/gabriele/Documents/Tesi2/nocloud}"      # directory con user-data e meta-data
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

#[[ -f "$ORIGINAL_ISO" ]] || error "ISO originale non trovata: $ORIGINAL_ISO"
#[[ -d "$NOCLOUD_SRC" ]]  || error "Directory nocloud non trovata: $NOCLOUD_SRC"
#[[ -f "$NOCLOUD_SRC/user-data" ]] || error "File mancante: $NOCLOUD_SRC/user-data"
#[[ -f "$NOCLOUD_SRC/meta-data" ]] || error "File mancante: $NOCLOUD_SRC/meta-data"

# ─── Pulizia e preparazione directory ────────────────────────────────────────
info "Preparazione directory di lavoro:"
temp_dir=$(mktemp -d)
cd "$temp_dir"
rm -rf "$temp_dir"
mkdir -p "$temp_dir/iso"
mkdir -p "$temp_dir/nocloud"

# ─── Generazione file per autoinstall ────────────────────────────────────────
touch "$temp_dir/nocloud/meta-data"

cat > "$temp_dir/nocloud/autoOpenNebula.sh" << "EOF"
wget -4 -O- https://downloads.opennebula.io/repo/repo2.key | sudo gpg --dearmor --yes --output /etc/apt/trusted.gpg.d/opennebula.gpg
echo "deb https://downloads.opennebula.io/repo/7.0/Ubuntu/24.04 stable opennebula" | sudo tee /etc/apt/sources.list.d/opennebula.list
apt update
apt install opennebula opennebula-fireedge opennebula-guacd -y
apt install opennebula-node-kvm -y
sudo -u oneadmin ssh-keygen -t rsa -N "" -f /var/lib/one/.ssh/id_rsa
sudo -u oneadmin cp /var/lib/one/.ssh/id_rsa.pub /var/lib/one/.ssh/authorized_keys
systemctl enable --now opennebula opennebula-fireedge
apt update && apt upgrade -y && apt autoremove -y
EOF

info "Configurazione interattiva user-data per autoinstall..."
read -p "Lingua del sistema installato (default: it_IT.UTF-8): " lingua
lingua=${lingua:-it_IT.UTF-8}
read -p "Fuso orario (default: Europe/Rome): " orazone
orazone=${orazone:-Europe/Rome}
read -p "Layout tastiera (default: it): " keyboard_layout
keyboard_layout=${keyboard_layout:-it}

INTERFACES_LIST=()
while true; do
  read -p "Aggiungi Interfaccia (enter per finire): " interface_next
  [[ -z "$interface_next" ]] && break
  INTERFACES_LIST+=("$interface_next")
done
read -p "Indirizzo IP: " ip_address
ip_address=${ip_address}
read -p "Gateway: " gateway
gateway=${gateway}
DNS_LIST=()
while true; do
  read -p "Aggiungi DNS (enter per finire): " dns_next
  [[ -z "$dns_next" ]] && break
  DNS_LIST+=("$dns_next")
done

read -p "Hostname (default: rootserver): " hostname
hostname=${hostname:-rootserver}
read -p "Username (default: server): " username
username=${username:-server}
read -p "Password (default: root@server1234): " password
echo  # nuova riga dopo input nascosto
password_hash=$(mkpasswd -m sha-512 "$password")

cat > "$temp_dir/nocloud/user-data" << "EOF"
#cloud-config
autoinstall:
  version: 1                        # OBBLIGATORIO — sempre 1

  # ─── CONFERME ────────────────────────────────────────────
  interactive-sections: [] # Salta tutte le domande interattive

  # ─── LOCALE ──────────────────────────────────────────────
  locale: $lingua               # lingua del sistema installato
  timezone: $orazoone           # fuso orario

  # ─── TASTIERA ────────────────────────────────────────────
  keyboard:
    layout: $keyboard_layout
    variant: ""                     # lascia vuoto per layout base

  # ─── RETE ────────────────────────────────────────────────
  network:
    version: 2
    ethernets:          # definizione interfacce fisiche — obbligatorio per il bond
      ${INTERFACES_LIST[@]/%/: {}}
    bonds:              # configurazione bonding (link aggregation)
      bond0:
        interfaces:
          ${INTERFACES_LIST[@]/%/}
        parameters:
          mode: active-backup
          primary: ${INTERFACES_LIST[0]}  # interfaccia primaria
        dhcp4: false
        addresses:
          - $ip_address/24
        routes:
          - to: default
            via: $gateway
        nameservers:
          addresses: [${DNS_LIST[*]}]

  # ─── IDENTITÀ ────────────────────────────────────────────
  identity:
    hostname: $hostname              # nome del computer (senza spazi)
    username: $username                  # nome utente senza spazi
    # password DEVE essere in formato hash bcrypt/SHA-512
    password: "$password_hash" #root@server1234
    # realname:   # nome completo (opzionale)

  # ─── SSH ─────────────────────────────────────────────────
  ssh:
    install-server: true              # installa openssh-server
    allow-pw: true                    # abilita login con password

  # ─── STORAGE ─────────────────────────────────────────────
  storage:
    layout:
      name: lvm                       # oppure: "direct" (no LVM) o "zfs"
      match:
        size: largest                 # usa il disco più grande


  # ─── PACCHETTI ───────────────────────────────────────────
  # Solo pacchetti già presenti nella ISO — nessuna connessione internet necessaria
  packages:
    - snapd                           # per installare pacchetti snap (es. Firefox)
    - vim                             # editor di testo
    - curl                            # per scaricare file da internet
    - git                             # controllo versione
    - htop                            # monitoraggio risorse
    - net-tools                       # strumenti di rete legacy (ifconfig, netstat)
    - iproute2                        # strumenti di rete
    - sed                             # per modificare file di testo da terminale
    - openssh-sftp-server             # per abilitare SFTP
    - gnupg                           # per gestire chiavi GPG
    - wget                            # per scaricare file da terminale
    - apt-transport-https             # per usare repository HTTPS
    - emacs                            # altro editor di testo
    - opennebula-node-kvm             # pacchetto necessario per OpenNebula
    #- ufw                            # firewall

  # Aggiorna tutti i pacchetti dopo l'installazione
  package_update: true
  package_upgrade: true

  # ─── COMANDI ─────────────────────────────────────────────
  # Eseguiti PRIMA che l'installer parta (in ambiente live)
  early-commands:
    - echo "Inizio installazione" > /tmp/install.log

  # Eseguiti DOPO l'installazione, nel sistema installato (tramite curtin)
  late-commands:
    #- curtin in-target --target=/target -- systemctl enable ufw
    #- curtin in-target --target=/target -- ufw allow ssh
    #- curtin in-target --target=/target -- ufw --force enable
    - curtin in-target --target=/target -- sed -i 's|autoinstall ds=nocloud\\;s=/cdrom/nocloud/||g' /boot/grub/grub.cfg
    - curtin in-target --target=/target -- sed -i 's|autoinstall||g' /boot/grub/grub.cfg 
    - cp /cdrom/nocloud/autoOpenNebula.sh /target/tmp/
    - curtin in-target --target=/target -- bash /tmp/autoOpenNebula.sh
    - curtin in-target --target=/target -- snap install firefox
    - curtin in-target --target=/target -- apt-get install -y ubuntu-desktop 

  # ─── USER-DATA (cloud-init aggiuntivo) ───────────────────
  # Eseguito al primo avvio del sistema installato
  user-data:
    runcmd:
      - echo "Sistema pronto!" >> /var/log/firstboot.log
EOF


# ─── Estrazione ISO ───────────────────────────────────────────────────────────
info "Download ISO originale..."
wget -O ubuntu.iso "https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso"
info "Estrazione ISO originale con xorriso..."
xorriso -osirrox on \
  -indev "ubuntu.iso" \
  -extract / "$temp_dir/iso" \
  2>/dev/null
info "Estrazione completata."

# Rendi modificabile il contenuto (xorriso estrae in sola lettura)
chmod -R u+w "$temp_dir/iso"

# ─── Copia nocloud/ ───────────────────────────────────────────────────────────
info "Copia dei file nocloud (user-data, meta-data)..."
cp -r "$temp_dir/nocloud" "$temp_dir/iso/nocloud"
chmod 644 "$temp_dir/iso/nocloud/user-data" \
           "$temp_dir/iso/nocloud/meta-data" \
           "$temp_dir/iso/nocloud/autoOpenNebula.sh"

# ─── Patch GRUB ──────────────────────────────────────────────────────────────
GRUB_CFG="$temp_dir/iso/boot/grub/grub.cfg"
[[ -f "$GRUB_CFG" ]] || error "grub.cfg non trovato: $GRUB_CFG"

info "Patch di grub.cfg..."

# Backup
cp "$GRUB_CFG" "${GRUB_CFG}.bak"

# Aggiunge autoinstall e nocloud alla prima voce di menu (linux/linuxefi)
# Supporta sia BIOS (linux) che UEFI (linuxefi)
python3 - "$GRUB_CFG" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Pattern per righe linux/linuxefi che contengono vmlinuz
def patch_linux_line(m):
    line = m.group(0)
    # Evita di duplicare se già patchato
    if 'autoinstall' in line:
        return line
    # Aggiunge i parametri prima di eventuali --- finali
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
grep -n "autoinstall" "$GRUB_CFG" | sed 's/^/  /' || warn "Nessuna riga autoinstall trovata — controlla grub.cfg manualmente."

# ─── (Opzionale) Patch ISOLINUX per boot BIOS legacy ─────────────────────────
ISOLINUX_CFG="$temp_dir/iso/isolinux/txt.cfg"
if [[ -f "$ISOLINUX_CFG" ]]; then
  info "Patch isolinux/txt.cfg per boot BIOS legacy..."
  cp "$ISOLINUX_CFG" "${ISOLINUX_CFG}.bak"
  sed -i 's|append  *|append autoinstall ds=nocloud\\;s=/cdrom/nocloud/ |' "$ISOLINUX_CFG" || true
fi

# ─── Raccolta metadati ISO originale (MBR + partizioni) ─────────────────────
info "Lettura MBR e parametri EFI dall'ISO originale..."

MBR_IMG="$temp_dir/mbr.img"
EFI_IMG="$temp_dir/efi.img"

# Estrai MBR (primi 432 byte — area sicura, non tocca la partition table)
dd if="ubuntu.iso" bs=1 count=432 of="$MBR_IMG" status=none

# Trova offset e dimensione della partizione EFI (partizione 2 tipicamente)
# Usa xorriso per leggere il layout
EFI_OFFSET=$(xorriso -indev "ubuntu.iso" -report_el_torito as_mkisofs 2>/dev/null \
  | grep -oP '(?<=--efi-boot-part --efi-boot-image --protective-msdos-label).*' || true)

# Usa sfdisk -d: output strutturato (start=N, size=N, type=EF)
# non dipende dal path del file → sicuro con spazi nel nome ISO
SECTOR_SIZE=512
EFI_START_SECTOR=$(sfdisk -d "ubuntu.iso" 2>/dev/null \
  | awk -F'[=,]' '/type=EF/{gsub(/ /,"",$2); print $2}' | head -1 || echo "")
EFI_SIZE_SECTOR=$(sfdisk -d "ubuntu.iso" 2>/dev/null \
  | awk -F'[=,]' '/type=EF/{gsub(/ /,"",$4); print $4}' | head -1 || echo "")

if [[ -n "$EFI_START_SECTOR" && -n "$EFI_SIZE_SECTOR" ]]; then
  dd if="ubuntu.iso" \
     bs=$SECTOR_SIZE \
     skip="$EFI_START_SECTOR" \
     count="$EFI_SIZE_SECTOR" \
     of="$EFI_IMG" \
     status=none
  info "Immagine EFI estratta: offset=$EFI_START_SECTOR settori, size=$EFI_SIZE_SECTOR settori"
  HAS_EFI=1
else
  warn "Partizione EFI non rilevata automaticamente — boot UEFI potrebbe non funzionare."
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
    # Boot UEFI
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

info ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info " ISO pronta: $script_dir/ubuntu-custom.iso"
info " Scrivi su USB con:"
info "   sudo dd if=$script_dir/ubuntu-custom.iso of=/dev/sdX bs=4M status=progress oflag=sync"
info " oppure:"
info "   sudo cp $script_dir/ubuntu-custom.iso /dev/sdX && sync"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"