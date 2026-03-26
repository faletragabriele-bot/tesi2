wget -4 -O- https://downloads.opennebula.io/repo/repo2.key | sudo gpg --dearmor --yes --output /etc/apt/trusted.gpg.d/opennebula.gpg
echo "deb https://downloads.opennebula.io/repo/7.0/Ubuntu/24.04 stable opennebula" | sudo tee /etc/apt/sources.list.d/opennebula.list
sudo apt update
sudo apt install opennebula opennebula-fireedge opennebula-guacd -y
sudo apt install opennebula-node-kvm -y
sudo -u oneadmin ssh-keygen -t rsa -N "" -f /var/lib/one/.ssh/id_rsa
sudo -u oneadmin cp /var/lib/one/.ssh/id_rsa.pub /var/lib/one/.ssh/authorized_keys
sudo systemctl enable --now opennebula opennebula-fireedge
sudo apt update && sudo apt upgrade -y && sudo autoremove -y
