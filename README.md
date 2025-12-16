# With ansible create K8S cluster. Keepalive, crio, traefik, CNI flanell, metallb, ansible awx + websites (Ubuntu 24.04)
###
#### First steps install 3 master and 2 worke nodes with Ubuntu 24.04.
###
#### sudo apt update && sudo apt install software-properties-common -y
#### sudo add-apt-repository --yes --update ppa:ansible/ansible && sudo apt install ansible -y
###
### 0.1 Generate ssh key and copy to main directory.
#### sudo ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519_vm
###
### 0.2 Edit hosts.ini ansible_host, ansible_user, ansible_password.
### 0.3 Edit hosts_wolf.ini ansible_host, ansible_user, ansible_ssh_private_key_file (Windows and linux is different ssh location).
###
### 0.4 Generate CA your privacy or use my.
###
#### openssl genrsa -out latloto-ca.key 4096
#### openssl req -x509 -new -nodes -key latloto-ca.key -sha256 -days 3650 -out latloto-ca.crt -subj "/C=LV/ST=Riga/L=Riga/O=Latloto CA/OU=IT/CN=latloto-ca"
#### openssl genrsa -out latloto-intermediate-server-v1.key 4096
#### openssl req -new -key latloto-intermediate-server-v1.key -out latloto-intermediate-server-v1.csr -subj "/C=LV/ST=Riga/L=Riga/O=Latloto Intermediate V1/OU=IT/CN=latloto-intermediate-server-v1"
#### openssl x509 -req -in latloto-intermediate-server-v1.csr -CA latloto-ca.crt -CAkey latloto-ca.key -CAcreateserial -out latloto-intermediate-server-v1.crt -days 1825 -sha256
#### openssl genrsa -out latloto-intermediate-server-v2.key 4096
#### openssl req -new -key latloto-intermediate-server-v2.key -out latloto-intermediate-server-v2.csr -subj "/C=LV/ST=Riga/L=Riga/O=Latloto Intermediate V2/OU=IT/CN=latloto-intermediate-server-v2"
#### openssl x509 -req -in latloto-intermediate-server-v2.csr -CA latloto-ca.crt -CAkey latloto-ca.key -CAcreateserial -out latloto-intermediate-server-v2.crt -days 1825 -sha256
#### openssl genrsa -out wildcard.iloto.lldev.key 2048
#### openssl req -new -key wildcard.iloto.lldev.key -out wildcard.iloto.lldev.csr -subj "/C=LV/ST=Riga/L=Riga/O=Latloto/OU=IT/CN=*.iloto.lldev"
#### openssl x509 -req -in wildcard.iloto.lldev.csr -CA latloto-intermediate-server-v2.crt -CAkey latloto-intermediate-server-v2.key -CAcreateserial -out wildcard.iloto.lldev.crt -days 825 -sha256
#### cat wildcard.iloto.lldev.crt latloto-intermediate-server-v2.crt latloto-ca.crt > combined-chain.crt

### Import to web browser:
### cat latloto-intermediate-server-v2.crt latloto-intermediate-server-v1.crt > intermediate-chain.crt (Edit file because space need).
###
### openssl x509 -in intermediate-chain.crt -text -noout
### openssl pkcs12 -export -out wildcard.iloto.lldev.pfx -inkey wildcard.iloto.lldev.key -in wildcard.iloto.lldev.crt -certfile intermediate-chain.crt
###
### 0.5 Edit /etc/hosts 0_setup.yml, master1, master2...
### 0.6 Edit 2_keepalived.yml vip: "10.10.1.30/32", interface: "enp7s0" (ip a) Ubuntu.
### 0.7 Edit to your IP in file 6.1_metalb.yml vip: 10.10.1.30 metallb_ip_range: "10.10.1.30-10.10.1.30", my demo_host: demo.latloto.lv
#### 0.8 Copy manual key or use ansible (0_setup.yml)
#### Edit file k8s-init-master main.yml and k8s-join-controlplane main.yml my user wolf to Yours.
###
## 1. ansible-playbook -i hosts.ini 0_setup.yml
#### If you need add second disc to volume use:
## 1.1. ansible-playbook -i hosts_wolf.ini 0_setup_disc.yml
###
## 2 - 10.yml master playbook.
## ansible-playbook -i hosts_wolf.ini 1_master_playbook.yml
###
#### or manual use step by step:
## 2. ansible-playbook -i hosts_wolf.ini 2_keepalived.yml
## 3. ansible-playbook -i hosts_wolf.ini 3_ca_import_latloto.yml
### Edit file 3_ca_import_latloto.yml - vars if use another certificates.
## 4. ansible-playbook -i hosts_wolf.ini 4_k8s_ha.yml etc... 5,6,7,8,9,10...
###
#### ansible-playbook -i hosts_wolf.ini restart.yml or poweroff.yml.
#### 12_install_rancher_full.yaml doesn't work because need high CPU and RAM.
###
### nano /etc/hosts in your computer (MAC). Windows is different.
#### 192.168.4.190.  hello.iloto.lldev
#### 192.168.4.190   data.iloto.lldev
#### 192.168.4.190   manual.iloto.lldev
#### 192.168.4.190   awx.iloto.lldev
#### Add certificate to web browser: latloto-ca.crt
#### http://hello.iloto.lldev
#### https://awx.iloto.lldev
#### kubectl get secret ansible-awx-admin-password -o jsonpath="{.data.password}" -n awx | base64 --decode ; echo