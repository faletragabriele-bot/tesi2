#!/usr/bin/env bash
# =============================================================================
# build-iso.sh — Smonta e rimonta Ubuntu Server 24.04.1 LTS con autoinstall
# =============================================================================
# Uso: sudo ./build-iso.sh
# Dipendenze: xorriso, isolinux (syslinux-utils), mtools
# =============================================================================

set -euo pipefail

# ─── Configurazione ───────────────────────────────────────────────────────────
ORIGINAL_ISO="${ORIGINAL_ISO:-/home/gabriele/VirtualBox VMs/ubuntu-24.04.1-live-server-amd64.iso}"
OUTPUT_ISO="${OUTPUT_ISO:-/home/gabriele/Documents/OS/ubuntu-custom.iso}"
WORK_DIR="${WORK_DIR:-/home/gabriele/ubuntu-custom}"
NOCLOUD_SRC="${NOCLOUD_SRC:-/home/gabriele/Documents/Tesi2/nocloud}"      # directory con user-data e meta-data

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

[[ -f "$ORIGINAL_ISO" ]] || error "ISO originale non trovata: $ORIGINAL_ISO"
[[ -d "$NOCLOUD_SRC" ]]  || error "Directory nocloud non trovata: $NOCLOUD_SRC"
[[ -f "$NOCLOUD_SRC/user-data" ]] || error "File mancante: $NOCLOUD_SRC/user-data"
[[ -f "$NOCLOUD_SRC/meta-data" ]] || error "File mancante: $NOCLOUD_SRC/meta-data"

# ─── Pulizia e preparazione directory ────────────────────────────────────────
info "Preparazione directory di lavoro: $WORK_DIR"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/iso"

# ─── Estrazione ISO ───────────────────────────────────────────────────────────
info "Estrazione ISO originale con xorriso..."
xorriso -osirrox on \
  -indev "$ORIGINAL_ISO" \
  -extract / "$WORK_DIR/iso" \
  2>/dev/null
info "Estrazione completata."

# Rendi modificabile il contenuto (xorriso estrae in sola lettura)
chmod -R u+w "$WORK_DIR/iso"

# ─── Copia nocloud/ ───────────────────────────────────────────────────────────
info "Copia dei file nocloud (user-data, meta-data)..."
cp -r "$NOCLOUD_SRC" "$WORK_DIR/iso/nocloud"
chmod 644 "$WORK_DIR/iso/nocloud/user-data" \
           "$WORK_DIR/iso/nocloud/meta-data" \
           "$WORK_DIR/iso/nocloud/autoOpenNebula.sh"

# ─── Patch GRUB ──────────────────────────────────────────────────────────────
GRUB_CFG="$WORK_DIR/iso/boot/grub/grub.cfg"
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
ISOLINUX_CFG="$WORK_DIR/iso/isolinux/txt.cfg"
if [[ -f "$ISOLINUX_CFG" ]]; then
  info "Patch isolinux/txt.cfg per boot BIOS legacy..."
  cp "$ISOLINUX_CFG" "${ISOLINUX_CFG}.bak"
  sed -i 's|append  *|append autoinstall ds=nocloud\\;s=/cdrom/nocloud/ |' "$ISOLINUX_CFG" || true
fi

# ─── Raccolta metadati ISO originale (MBR + partizioni) ─────────────────────
info "Lettura MBR e parametri EFI dall'ISO originale..."

MBR_IMG="$WORK_DIR/mbr.img"
EFI_IMG="$WORK_DIR/efi.img"

# Estrai MBR (primi 432 byte — area sicura, non tocca la partition table)
dd if="$ORIGINAL_ISO" bs=1 count=432 of="$MBR_IMG" status=none

# Trova offset e dimensione della partizione EFI (partizione 2 tipicamente)
# Usa xorriso per leggere il layout
EFI_OFFSET=$(xorriso -indev "$ORIGINAL_ISO" -report_el_torito as_mkisofs 2>/dev/null \
  | grep -oP '(?<=--efi-boot-part --efi-boot-image --protective-msdos-label).*' || true)

# Usa sfdisk -d: output strutturato (start=N, size=N, type=EF)
# non dipende dal path del file → sicuro con spazi nel nome ISO
SECTOR_SIZE=512
EFI_START_SECTOR=$(sfdisk -d "$ORIGINAL_ISO" 2>/dev/null \
  | awk -F'[=,]' '/type=EF/{gsub(/ /,"",$2); print $2}' | head -1 || echo "")
EFI_SIZE_SECTOR=$(sfdisk -d "$ORIGINAL_ISO" 2>/dev/null \
  | awk -F'[=,]' '/type=EF/{gsub(/ /,"",$4); print $4}' | head -1 || echo "")

if [[ -n "$EFI_START_SECTOR" && -n "$EFI_SIZE_SECTOR" ]]; then
  dd if="$ORIGINAL_ISO" \
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
info "Ricostruzione ISO: $OUTPUT_ISO"
rm -f "$OUTPUT_ISO"

XORRISO_ARGS=(
  xorriso -as mkisofs
  -r
  -V "Ubuntu-Server-24.04.1-auto"
  --modification-date="$(date -u +%Y%m%d%H%M%S)00"
  -o "$OUTPUT_ISO"

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
  "$WORK_DIR/iso"
)

"${XORRISO_ARGS[@]}"

# ─── Verifica output ──────────────────────────────────────────────────────────
if [[ -f "$OUTPUT_ISO" ]]; then
  SIZE=$(du -sh "$OUTPUT_ISO" | cut -f1)
  info "✅ ISO creata con successo: $OUTPUT_ISO ($SIZE)"
  info ""
  info "Verifica rapida contenuto:"
  xorriso -indev "$OUTPUT_ISO" -find nocloud -exec lsdl -- 2>/dev/null | sed 's/^/  /' || true
else
  error "Qualcosa è andato storto — $OUTPUT_ISO non trovata."
fi

# ─── Pulizia ──────────────────────────────────────────────────────────────────
info "Pulizia directory temporanea..."
rm -rf "$WORK_DIR"

info ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info " ISO pronta: $OUTPUT_ISO"
info " Scrivi su USB con:"
info "   sudo dd if=$OUTPUT_ISO of=/dev/sdX bs=4M status=progress oflag=sync"
info " oppure:"
info "   sudo cp $OUTPUT_ISO /dev/sdX && sync"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"