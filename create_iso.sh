#!/bin/bash
percorso_input=$1
percorso_output=$2
ubuntu_custom_dir=~/ubuntu-custom
ubuntu_iso_name_output="ubuntu-autoinstall.iso"
iso_originale="${percorso_input}/ubuntu-24.04.1-live-server-amd64.iso"

rm -rf "${ubuntu_custom_dir}"
rm -rf "${percorso_output}/${ubuntu_iso_name_output}"

# Estrai l'ISO originale
xorriso -osirrox on \
  -indev "${iso_originale}" \
  -extract / "${ubuntu_custom_dir}"

chmod -R u+w "${ubuntu_custom_dir}"

# Crea la directory nocloud e copia i file
mkdir -p "${ubuntu_custom_dir}/nocloud"
cp ./user-data "${ubuntu_custom_dir}/nocloud/"
touch "${ubuntu_custom_dir}/nocloud/meta-data"
cp ./autoOpenNebula.sh "${ubuntu_custom_dir}/nocloud/"

# Modifica grub.cfg
sed -i 's/ ---/ autoinstall ds=nocloud;s=\/cdrom\/nocloud\/ ---/' \
  "${ubuntu_custom_dir}/boot/grub/grub.cfg"

# Estrai il MBR ibrido dall'ISO originale (fondamentale per USB!)
dd if="${iso_originale}" bs=1 count=432 \
  of="${ubuntu_custom_dir}/boot/grub/i386-pc/mbr.img" 2>/dev/null
# (oppure usa il file se già presente nella ISO estratta)

# Ricostruisci l'ISO con supporto BIOS + UEFI ibrido
xorriso -as mkisofs \
  -r -V "Chiavetta_Ubuntu2404Auto" \
  -o "${percorso_output}/${ubuntu_iso_name_output}" \
  -J -joliet-long \
  --grub2-mbr "${ubuntu_custom_dir}/boot/grub/i386-pc/boot_hybrid.img" \
  -partition_offset 16 \
  --mbr-force-bootable \
  -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b \
    "${ubuntu_custom_dir}/boot/grub/efi.img" \
  -appended_part_as_gpt \
  -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
  -b boot/grub/i386-pc/eltorito.img \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  --grub2-boot-info \
  -eltorito-alt-boot \
  -e '--interval:appended_partition_2:::' \
  -no-emul-boot \
  -isohybrid-gpt-basdat \
  "${ubuntu_custom_dir}"