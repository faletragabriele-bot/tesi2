- CHIAVETTA AUTOINSTALLANTE
    
    Per rendere bootabile una chiavetta usb
    
    ```bash
    sudo dd if=<path del file.iso> of=/dev/<path del USB key> bs=4M conv=fsync status=progress
    ```
    
    sudo: superuser do
    
    dd: data duplicator (Copy, and optionally convert, a file system resource)
    
    - if: input file (the file used for input)
    - of: output file (the file used for output)
    - per of ha senso prima mandare il comando:
    
    ```bash
    lsblk --scsi
    ```
    
    - per avere il path della USB inserita
    - bs: bytes (read and write up to BYTES bytes at a time) (impostati 4 MB, diviso il file.iso in blocchetti da 4MB copiati uno alla volta)
    - conv=fsync mi assicura che il processo di copia e riscrittura, di una parte del file, su chiavetta sia completato prima di passare alla parte dopo (quindi prima di avanzare nella progress bar, fsync assicura che un pezzo di file sia arrivato e copiato in modo corretto sulla chiavetta prima di passare al pezzo successivo)
    - status=progress mi dà la barra di progresso che avanza man mano che la copia va a buon fine
    
    Per collegarsi:
    
    ```bash
    sudo apt install net-tools # sul server per potersi collegare tramite ssh, perché contiene la possibilità di renderlo server su ssh
    ```
    
    ```bash
    whoami # per darci il nome dell’utente sul server, che viene impostato sul file.yaml
    ```
    
    ```bash
    ifconfig # per ricavarsi l’indirizzo IP del server
    ```
    
    Queste informazioni servono per collegarsi da un PC remoto (client) al PC server.
    
    File.yaml:
    
- Creazione/modifica dell’iso
    
    **1. Strumenti necessari**
    
    `sudo apt install xorriso`
    
    **2. Estrai la ISO server**
    
    `xorriso -osirrox on \
      -indev "percorso/ubuntu-24.04.1-live-server-amd64.iso" \
      -extract / ~/ubuntu-custom
    chmod -R u+w ~/ubuntu-custom`
    
    **3. Aggiungi i file autoinstall**
    
    `mkdir ~/ubuntu-custom/nocloud
    cp user-data ~/ubuntu-custom/nocloud/
    touch ~/ubuntu-custom/nocloud/meta-data`
    
    **4. Modifica il grub.cfg a mano**
    
    `nano ~/ubuntu-custom/boot/grub/grub.cfg
    ```
    La riga `linux` deve diventare:
    ```
    linux	/casper/vmlinuz autoinstall ds=nocloud\;s=/cdrom/nocloud/  ---`
    
    ⚠️ Il `\;` è fondamentale — senza il backslash il punto e virgola viene troncato da GRUB.
    
    **5. Ricostruisci la ISO**
    
    `xorriso -as mkisofs \
      -r -V "Ubuntu2404Auto" \
      -o "percorso/ubuntu-autoinstall.iso" \
      -J -joliet-long \
      -b boot/grub/i386-pc/eltorito.img \
      -no-emul-boot -boot-load-size 4 -boot-info-table \
      ~/ubuntu-custom`
    
    **6. Verifica che grub.cfg e nocloud siano nella ISO**
    
    `xorriso -osirrox on -indev "ubuntu-autoinstall.iso" \
      -extract /boot/grub/grub.cfg /tmp/check.cfg && cat /tmp/check.cfg`
    
- OPENNEBULA
    
    OpenNebula è configurato per funzionare bene su Ubuntu 24.04 LTS (il mio è Ubuntu 25.10) per cui l'idea migliore è stata di scaricare VirtualBox per generare una VM con l'OS desiderato (proprietà: RAM 6 GB, 2 core, 60 GB disco, 128 MB di memoria video).
    
    ## primo metodo
    
    Ho scaricato il file “.iso” del OS di Ubuntu 24.04.4 LTS (6.7 GB) da mettere nella VM.
    Ho provato a seguire le indicazioni di installazione di OpenNebula dal sito ufficiale ma non andava, per cui ho usato ChatGPT che mi ha indicato i seguenti comandi che ho riportato nel terminale della VM:
    
    ```bash
    sudo apt update
    sudo apt upgrade -y
    sudo apt install curl gnupg2 -y
    echo "deb https://downloads.opennebula.io/repo/6.10/Ubuntu/24.04 stable opennebula" | sudo tee /etc/apt/sources.list.d/opennebula.list
    curl -fsSL https://downloads.opennebula.io/repo/repo2.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/opennebula.gpg
    sudo apt update
    sudo apt install opennebula opennebula-sunstone -y
    sudo systemctl start opennebula
    sudo systemctl start opennebula-sunstone
    sudo cat /var/lib/one/.one/one_auth
    ```
    
    L’ultima riga è utile per ricavarsi la password per accedere a OpenNebula dal browser attraverso: [http://localhost:9869](http://localhost:9869/)
    
    Credenziali: 
    
    user: oneadmin
    password: output dell’ultimo comando
    
    Riavviando il computer, dal browser non è stato più possibile accedere a OpenNebula. Cause? C’è bisogno di riavviare il terminale e immettere i penultimi due comandi
    
    Fonte informazioni per istallazione ufficile tramite repository: https://docs.opennebula.io/6.10/overview/opennebula_concepts/opennebula_overview.html
    
    ## secondo metodo:
    
    sudo apt update && sudo apt upgrade -y
    sudo apt install gnupg wget apt-transport-https -y
    
    wget -4 -O- https://downloads.opennebula.io/repo/repo2.key | sudo gpg --dearmor --yes --output /etc/apt/trusted.gpg.d/opennebula.gpg
    echo "deb https://downloads.opennebula.io/repo/7.0/Ubuntu/24.04 stable opennebula" | sudo tee /etc/apt/sources.list.d/opennebula.list
    sudo apt update
    
    sudo apt install opennebula opennebula-fireedge opennebula-guacd -y
    
    sudo apt install opennebula-node-kvm -y
    sudo reboot
    
    sudo passwd oneadmin
    
    Cambia password
    
    sudo -u oneadmin ssh-keygen -t rsa -N "" -f /var/lib/one/.ssh/id_rsa
    sudo -u oneadmin cp /var/lib/one/.ssh/id_rsa.pub /var/lib/one/.ssh/authorized_keys
    
    Configura SSH (da eseguire come utente oneadmin se possibile, o gestito daONE)
    
    sudo systemctl enable --now opennebula opennebula-fireedge
    
    sudo ufw allow 2616
    sudo ufw reload
    

# Alla fine

ho dovuto comunque mandare

```bash
sudo systemctl enable ssh
sudo systemctl start ssh
sudo systemctl status ssh
```

per attivare ssh e poi

```bash
sudo systemctl enable --now opennebula opennebula-fireedge
```

per attivare OpenNebula e questo per ottenere la pw

```bash
sudo cat /var/lib/one/.one/one_auth
```
