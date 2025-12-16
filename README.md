# With ansible create K8S cluster. Keepalive, crio, traefik, CNI flanell, metallb, ansible awx + web sites (Ubuntu 24.04)
#### First steps install 3 master and 2 worke nodes with Ubuntu 24.04.
##
#### sudo apt update && sudo apt install software-properties-common -y
#### sudo add-apt-repository --yes --update ppa:ansible/ansible && sudo apt install ansible -y
##
## 0.1 Generate ssh key and copy to main directory.
#### sudo ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519_vm
##
#### 0.2 Edit hosts.ini ansible_host, ansible_user, ansible_password.
#### 0.3 Edit hosts_wolf.ini ansible_host, ansible_user, ansible_ssh_private_key_file (Windows and linux is different ssh location).
##
# 0.4 Generate CA your privacy or use my. 
#### openssl genrsa -aes256 -out ca.key 4096
#### openssl req -new -x509 -sha256 -key ca.key -out ca.crt -days 3650
## 0.5 Edit /etc/hosts 0_setup.yml, master1, master2...
## 0.6 Edit 2_keepalived.yml vip: "10.10.1.30/32", interface: "enp7s0" (ip a) Ubuntu.
## 0.7 Edit to your IP in file 6.1_metalb.yml vip: 10.10.1.30 metallb_ip_range: "10.10.1.30-10.10.1.30", my demo_host: demo.latloto.lv
# 0.8 Copy manual key or use ansible (0_setup.yml)
#### sudo scp -i ~/.ssh/id_ed25519_vm ~/.ssh/id_ed25519_vm User@master1:~/.ssh/
#### sudo chmod 600 ~/.ssh/id_ed25519_vm 
===
## 1. ansible-playbook -i hosts.ini 0_setup.yml
#### If you need add second disc to volume use:
## 1.1. ansible-playbook -i hosts_wolf.ini 0_setup_disc.yml
##
### 2 - 10.yml:
## ansible-playbook -i hosts_wolf.ini 1_master_playbook.yml
===
##
#### or manual use step by step:
### 2. ansible-playbook -i hosts_wolf.ini 2_keepalived.yml
### 3. ansible-playbook -i hosts_wolf.ini 3_ca_import_latloto.yml
### 4. ansible-playbook -i hosts_wolf.ini 4_k8s_ha.yml etc... 5,6,7,8,9,10...
##
### ansible-playbook -i hosts_wolf.ini restart.yml or poweroff.yml.
### 12_install_rancher_full.yaml doesn't work because need high CPU and RAM.