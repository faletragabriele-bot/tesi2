#!/bin/bash
percorso_input=$1 # Percorso dell'ISO di origine
percorso_output=$2 # Percorso di destinazione per l'ISO personalizzato
ubuntu_custom_dir=~/ubuntu-custom
rm -rf "${ubuntu_custom_dir}" 
ubuntu_iso_name_output="ubuntu-autoinstall.iso"

rm -rf "${percorso_output}/${ubuntu_iso_name_output}" 


xorriso -osirrox on \
  -indev "${percorso_input}/ubuntu-24.04.1-live-server-amd64.iso" \
  -extract / "${ubuntu_custom_dir}"
chmod -R u+w "${ubuntu_custom_dir}" 
mkdir "${ubuntu_custom_dir}/nocloud"
cp ./user-data "${ubuntu_custom_dir}/nocloud/"
touch "${ubuntu_custom_dir}/nocloud/meta-data"
cp ./autoOpenNebula.sh "${ubuntu_custom_dir}/nocloud/"
sed -i 's/ ---/autoinstall ds=nocloud\\;s=\/cdrom\/nocloud\/ ---/' "${ubuntu_custom_dir}/boot/grub/grub.cfg"


#xorriso -as mkisofs \
#  -r -V "Chiavetta_Ubuntu2404Auto" \
#  -o "${percorso_output}/${ubuntu_iso_name_output}" \
#  -J -joliet-long \
#  -b boot/grub/i386-pc/eltorito.img \
#  -no-emul-boot -boot-load-size 4 -boot-info-table \
#  "${ubuntu_custom_dir}"



xorriso -as mkisofs \
  -r -V "Chiavetta_Ubuntu2404Auto" \
  -o "${percorso_output}/${ubuntu_iso_name_output}" \
  -J -l \
  -b boot/grub/i386-pc/eltorito.img \
  -c boot.catalog \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  "${ubuntu_custom_dir}"