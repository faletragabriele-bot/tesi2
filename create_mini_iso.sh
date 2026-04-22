#!/bin/bash
percorso_input=$1 # Percorso dell'ISO di origine
percorso_output=$2 # Percorso di destinazione per l'ISO personalizzato
grub_text=$3 # Testo da sostituire in grub.cfg
ubuntu_custom_dir=~/ubuntu-mini
rm -rf "${ubuntu_custom_dir}"
ubuntu_iso_name_output="ubuntu-manual-mini.iso"

rm -rf "${percorso_output}/${ubuntu_iso_name_output}"


xorriso -osirrox on \
  -indev "${percorso_input}" \
  -extract / "${ubuntu_custom_dir}"
chmod -R u+w "${ubuntu_custom_dir}"
mkdir "${ubuntu_custom_dir}/nocloud"
cp ./user-data "${ubuntu_custom_dir}/nocloud/"
touch "${ubuntu_custom_dir}/nocloud/meta-data"
cp ./autoOpenNebula.sh "${ubuntu_custom_dir}/nocloud/"
sed -i "s/ip=dhcp ---/${grub_text}/" "${ubuntu_custom_dir}/boot/grub/grub.cfg"
xorriso -as mkisofs \
  -r -V "Chiavetta_Ubuntu2404Auto" \
  -o "${percorso_output}/${ubuntu_iso_name_output}" \
  -J -joliet-long \
  -b boot/grub/i386-pc/eltorito.img \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  "${ubuntu_custom_dir}"