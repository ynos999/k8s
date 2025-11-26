#!/bin/bash
set -e

echo ">>> KUBERNETES KLASTERA SAGATAVOŠANA"

# 1. Sistēmas atjaunināšana un pamata pakotņu instalēšana, ufw izslēgšana
echo "--- 1. Sistēmas atjaunināšana un pakotņu instalēšana ---"
sudo apt update
sudo apt upgrade -y
sudo apt install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common gpg systemd-timesyncd
sudo systemctl stop ufw && sudo systemctl disable ufw

# 2. Swap atspējošana (Obligāts priekš K8s)
echo "--- 2. Swap atspējošana un FSTAB modifikācija ---"
sudo swapoff -a
# Noņemt no /etc/fstab, lai neatjaunotos pēc restart
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 3. Kodola moduļi un tīkla parametri
echo "--- 3. Kodola moduļu ielāde (overlay, br_netfilter) ---"
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay && sudo modprobe br_netfilter

echo "--- 4. Sysctl tīkla parametru iestatīšana (CRI-O un K8s) ---"
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# 4. CRI-O un K8s rīku instalēšana
echo "--- 5. CRI-O un Kubernetes rīku (kubeadm, kubelet, kubectl) instalēšana ---"

# Versiju definēšana
export OS=xUbuntu_22.04
export KUBERNETES_VERSION=v1.32
export CRIO_VERSION=v1.32

sudo mkdir -p -m 755 /etc/apt/keyrings

# Kubeadm/Kubelet/Kubectl repozitorija pievienošana
curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:$KUBERNETES_VERSION/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# CRI-O repozitorija pievienošana
curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/ /" | sudo tee /etc/apt/sources.list.d/cri-o.list

sudo apt update
sudo apt install -y cri-o cri-o-runc cri-tools kubelet kubeadm kubectl

# CRI-O un Kubelet startēšana
sudo systemctl start crio
sudo systemctl enable crio
sudo systemctl enable --now kubelet

# Novērst automātisku atjaunināšanu, kas varētu salauzt klasteri
sudo apt-mark hold kubelet kubeadm kubectl

echo ">>> PAMATVIDE SAGATAVOTA UZ $HOSTNAME!"