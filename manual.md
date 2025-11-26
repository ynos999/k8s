#### ssh -i ~/.ssh/id_rsa_hetzner wolf@46.62.220.209
-----------------------------
1. Noskaidrot OS un versiju
### cat /etc/os-release
### sudo apt update && sudo apt upgrade -y
# adduser wolf
# usermod -aG sudo wolf
### sudo -i
### visudo
### wolf ALL=(ALL) NOPASSWD:ALL
### sudo visudo -c
### sudo passwd -l root
### sudo systemctl stop ufw && sudo systemctl disable ufw

Uz katra servera atsevišķi:
sudo hostnamectl set-hostname master1 && hostnamectl
sudo hostnamectl set-hostname master2 && hostnamectl
sudo hostnamectl set-hostname master3 && hostnamectl
sudo hostnamectl set-hostname worker1 && hostnamectl
sudo hostnamectl set-hostname worker2 && hostnamectl

### ip a
### sudo nano /etc/hosts

46.62.220.209 master1
10.105.28.44 master2
10.105.28.45 master3
10.10.1.20 worker1
10.105.28.47 worker2

### sudo ufw disable && sudo systemctl stop ufw && sudo systemctl disable ufw
If using UFW or another firewall, open the following ports: 6443, 2379, 2380, 10250, 10259, 10257. 
-----------------------------
2. Iestatīt SSH piekļuvi tikai ar ed25519 atslēgām (no sava datora + starp nodēm, paroles off)
# sudo ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519_vm
# nano ~/.ssh/authorized_keys
cat ~/.ssh/id_ed25519_vm.pub >> ~/.ssh/authorized_keys
# sudo chmod 600 ~/.ssh/id_ed25519_vm

All VM vienādu paroli:
# sudo passwd wolf

# sudo ssh-copy-id -i ~/.ssh/id_ed25519_vm.pub user@master1
# sudo ssh-copy-id -i ~/.ssh/id_ed25519_vm.pub user@master2
# sudo ssh-copy-id -i ~/.ssh/id_ed25519_vm.pub user@master3
# sudo ssh-copy-id -i ~/.ssh/id_ed25519_vm.pub user@worker1
# sudo ssh-copy-id -i ~/.ssh/id_ed25519_vm.pub user@worker2

sudo ssh -i ~/.ssh/id_ed25519_vm wolf@worker1
sudo ssh -i ~/.ssh/id_ed25519_vm wolf@master1

sudo scp -i ~/.ssh/id_ed25519_vm ~/.ssh/id_ed25519_vm wolf@master1:~/.ssh/
sudo scp -i ~/.ssh/id_ed25519_vm ~/.ssh/id_ed25519_vm wolf@master2:~/.ssh/
sudo scp -i ~/.ssh/id_ed25519_vm ~/.ssh/id_ed25519_vm wolf@master3:~/.ssh/
sudo scp -i ~/.ssh/id_ed25519_vm ~/.ssh/id_ed25519_vm wolf@worker1:~/.ssh/
sudo scp -i ~/.ssh/id_ed25519_vm ~/.ssh/id_ed25519_vm wolf@worker2:~/.ssh/
# sudo nano /etc/ssh/sshd_config

PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
# Atspējot vājākus atslēgas tipus, ja nepieciešams (opcionāli, bet laba prakse)
Hostkey /etc/ssh/ssh_host_ed25519_key
# Atļaut tikai ED25519 lietotāju atslēgas
PubkeyAcceptedAlgorithms ssh-ed25519
HostkeyAlgorithms ssh-ed25519

# sudo systemctl restart sshd
-----------------------------
3. Uz 3 master nodēm uzlikt KeepAlived ar vienu kopīgu virtuālo IP
# Labojam vip: "10.10.1.30/32", interface: "enp7s0" (ip a)

# sudo apt install keepalived -y
# sudo nano /etc/keepalived/keepalived.conf

global_defs {
   # Ieteicams katrai nodei iestatīt unikālu router_id
   router_id master1
}

vrrp_instance VI_1 {
    # ------------------
    # GALVENĀS ATŠĶIRĪBAS:
    # ------------------
    state MASTER          # Lomas stāvoklis
    priority 150          # Augstākā prioritāte (nosaka, kurš ir Master)
    # ------------------
    
    interface enp7s0        # Jūsu tīkla interfeiss
    virtual_router_id 51  # Jābūt vienādam visās 3 nodēs
    advert_int 1
    
    # K8s Master mezglu tīkla veselības pārbaudes skripts (Opcionāli, bet Ieteicams)
    # track_script {
    #     chk_apiserver
    # }

    authentication {
        auth_type PASS
        auth_pass K8sHApass   # Kopīga parole visām nodēm
    }
    
    virtual_ipaddress {
        # Virtuālais IP, kas tiks reklamēts
        10.10.1.30/32 dev enp7s0 label enp7s0:vip 
    }

    # RISINĀJUMS AR METALIB: ļauj dalīties ar šo IP ar MetalLB
    allow_shared_ip 
}

---
state BACKUP
priority 100
router_id master2

---
state BACKUP
priority 50
router_id master3

---
## VIP (Virtuālais IP): 10.10.1.30
## VRID (Virtual Router ID): 51 (Jābūt vienādam visām nodēm)
## Tīkla Interfeiss: eth0 (Pārbaudiet, vai jūsu VM tas nav, piemēram, ens18!)
## Konflikta Atrisinašana: Iekļauts allow_shared_ip (priekš MetalLB).
## interface enp7s0
## virtual_ipaddress { 10.10.1.30/32 dev enp7s0 label enp7s0:vip}
---
# sudo systemctl restart keepalived
# sudo systemctl enable keepalived
-----------------------------
4. Importēt norādītos CA sertifikātus Trust Store katrā VM 

Ģenerējiet CA privāto atslēgu
openssl genrsa -aes256 -out ca.key 4096
Izveidojiet pašparakstītu CA sertifikātu
openssl req -new -x509 -sha256 -key ca.key -out ca.crt -days 3650

ca.crt (Publiskais CA sertifikāts – jākopē uz visām VM).
# sudo scp ca.crt user@vm_ip_address:/tmp/ca.crt

# sudo scp -i ~/.ssh/id_ed25519_vm ca.crt wolf@worker1:/tmp/ca.crt

CA sertifikātu imports 
Importējiet norādītos CA sertifikātus Trust Store katrā VM.
Pievienojiet sertifikātu (ca.crt) paredzētajā direktorijā.
# Debian/Ubuntu
# sudo cp /tmp/ca.crt /usr/local/share/ca-certificates/
# sudo update-ca-certificates
-----------------------------
5. Ar kubeadm no nulles uzstādīt HA Kubernetes klasteri (3 master HA caur VIP, CRI-O, Weave Net, doti CIDR)

# sudo swapoff -a
Noņemt no /etc/fstab, lai neatjaunotos pēc restart
# sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
# free -m
# cat /etc/fstab | grep swap
## sudo nano /etc/fstab

# sudo apt update && sudo apt -y upgrade && sudo apt -y install apt-transport-https ca-certificates curl gnupg2 software-properties-common gpg systemd-timesyncd -y
# sudo timedatectl set-ntp true

sudo su

cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# Kodola moduļi
modprobe overlay && modprobe br_netfilter

lsmod | grep "overlay\|br_netfilter"

# Tīkla parametri
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
---
Uz visām VM instalēt CRI-O
# ls -la /etc/apt/keyrings
# sudo mkdir -p -m 755 /etc/apt/keyrings

export OS=xUbuntu_22.04
export KUBERNETES_VERSION=v1.32
export CRIO_VERSION=v1.32

curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:$KUBERNETES_VERSION/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/ /" | tee /etc/apt/sources.list.d/cri-o.list

sudo apt update && sudo apt upgrade -y && sudo apt install -y cri-o cri-o-runc cri-tools kubelet kubeadm kubectl

sudo systemctl start crio && sudo systemctl enable crio && sudo systemctl status crio
sudo apt-mark hold kubelet kubeadm kubectl
sudo kubeadm version
sudo systemctl enable --now kubelet

# Labojam controlPlaneEndpoint, vip: 10.10.1.30 metallb_ip_range: "10.10.1.30-10.10.1.30", demo_host: demo.www.latloto.lv
====================
cat <<EOF | sudo tee kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: stable
controlPlaneEndpoint: "10.10.1.30:6443" # Jālabo!
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  bindAddress: 10.10.0.10 # <--- IEKŠĒJĀ IP JĀLABO
  bindPort: 6443
nodeRegistration:
  criSocket: "unix:///var/run/crio/crio.sock"
EOF
====================
sudo kubeadm init --config=kubeadm-config.yaml --upload-certs
===================================================
Korektā kubeadm init komanda (Uz Master 1). Izpildi augšējo komandu... JĀLABO

sudo kubeadm init \
  --control-plane-endpoint "10.10.1.30:6443" \
  --apiserver-bind-address	10.10.1.10 \
  --upload-certs \
  --pod-network-cidr 10.244.0.0/16 \
  --cri-socket unix:///var/run/crio/crio.sock \
  # Opcionāli, ja ir doti Service CIDR
  # --service-cidr 10.96.0.0/12
===================================================
# sudo systemctl status keepalived
# ip a show enp7s0

Zem user wolf:

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

Weave Net uzstādīšana:

# Pēc kubeadm init un konfigurācijas iestatīšanas uz Master 1
kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml

---
6. Pievienot pārējās nodes un pārliecināties, ka viss strādā.
kubectl get nodes
kubectl get po -A
kubectl get pods -n kube-system

---
7. Uzlikt MetalLB (Layer 2) + Traefik kā Ingress Controller

# Izpildīt UZ MASTER 1 VM

kubectl create namespace metallb-system
kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.3/config/manifests/metallb-native.yaml

kubectl get pods -n metallb-system
kubectl get svc webhook-service -n metallb-system

Pieņemsim, ka jūsu KeepAlived VIP ir 10.10.1.30.

Izveidojiet konfigurācijas failu (metallb-config.yaml):
nano metallb-config.yaml

# Uz Master 1 VM
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: external-ip-pool
  namespace: metallb-system
spec:
  # Definējiet adrešu diapazonu ārējiem pakalpojumiem
  addresses:
  - 10.10.1.30-10.10.1.30
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advertisement
  namespace: metallb-system
spec:
  # Norādiet tīkla interfeisu, kuru izmantot (Jūsu iekšējais tīkls)
  interfaces:
  - enp7s0
EOF

kubectl apply -f metallb-config.yaml

# Uz Master 1 VM Helm:
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm install traefik traefik/traefik \
  --namespace kube-system \
  --set service.type=LoadBalancer \
  --set service.loadBalancerIP="10.10.1.30" \
  --set service.annotations."metallb\.io/address-pool"="external-ip-pool" \
  --set providers.kubernetesIngress.ingressClass=traefik \
  --set providers.kubernetesIngress.publishedService.enabled=true \
  --set providers.kubernetesIngress.publishedService.ingressClassName=traefik

kubectl get svc traefik -n kube-system

8. Panākt, lai viens un tas pats virtuālais IP apkalpo gan Kubernetes API, gan ārējo HTTP/HTTPS trafiku
9. Atrisināt ARP konfliktu ar KeepAlived (allow-shared-ip triks)  
10. Uzlikt TLS sertifikātu, 80 → 443 redirect un vienkāršu demo URL ar HTTPS


# Uz Master 1 VM
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: whoami-service
  namespace: default
spec:
  ports:
    - protocol: TCP
      name: web
      port: 80
      targetPort: 80
  selector:
    app: whoami
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whoami-deployment
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: whoami
  template:
    metadata:
      labels:
        app: whoami
    spec:
      containers:
        - name: whoami
          image: traefik/whoami
          ports:
            - containerPort: 80
EOF

---

# Uz Master 1 VM
kubectl apply -f ingress.yaml
sudo nano ingress.yaml

# IngressRoute (KORIĢĒTS)
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: whoami-ingressroute
  namespace: default
spec:
  entryPoints:
    - web
    - websecure
  
  # 1. HTTP -> HTTPS PĀRADRESĀCIJA
  routes: 
    - match: "Host(`10.10.1.30`)" # Izmantojiet saskaņoto VIP!
      kind: Rule
      entryPoints:
        - web # Piesaista pie HTTP (80)
      middlewares:
        - name: redirect-to-https
      services:
        - name: whoami-service
          port: 80
  
  # 2. FAKTISKĀ HTTPS TRAFIKA
    - match: "Host(`10.10.1.30`)" # Izmantojiet saskaņoto VIP!
      kind: Rule
      entryPoints:
        - websecure # Piesaista pie HTTPS (443)
      services:
        - name: whoami-service
          port: 80
  
  tls:
    secretName: default-tls-secret

openssl req -x509 -newkey rsa:4096 -keyout tls.key -out tls.crt -days 365 -nodes -subj "/CN=10.10.1.30"
kubectl create secret tls default-tls-secret --key tls.key --cert tls.crt --dry-run=client -o yaml | kubectl apply -f -

SSH key-only | KeepAlived | kubeadm HA ar VIP | CRI-O | Weave Net | MetalLB L2 + shared IP | Traefik + savs TLS | Helm + Ingress Klasisks on-prem HA k8s scenārijs no A līdz Z.

===================
## export CRIO_VERSION=1.25
## echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" | tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
## echo "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/$OS/ /" | tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION.list
## curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/libcontainers-stable-keyring.gpg

## sudo rm -f /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:*
## sudo rm -f /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
## sudo rm -f /etc/apt/sources.list.d/devel:kubic:libcontainers:*
## sudo rm -f /etc/apt/keyrings/*cri-o*

## curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
## echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
===================

# kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.3/config/manifests/metallb-native.yaml
# kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.14.3/config/manifests/metallb-native.yaml

https://hostman.com/tutorials/how-to-install-a-kubernetes-cluster-on-ubuntu/

===================================================
--control-plane-endpoint	10.10.1.30:6443	Obligāts HA klasterim. Norāda uz Virtuālo IP (VIP), ko uztur KeepAlived. Visas noder pievienosies caur šo adresi.
--apiserver-bind-address	10.10.1.10	Kritiski svarīgs! Norāda, ka API serverim ir jāsaistās ar iekšējo IP adresi (jūsu enp7s0 adrese), lai visi klastera iekšējie komponenti (Etcd, Kubelets) izmantotu iekšējo tīklu.
--upload-certs	N/A	Nodrošina, ka sertifikāti (kas nepieciešami citiem masteriem) tiek automātiski ielādēti klasterī (Secret), lai tos varētu izmantot pievienošanās procesā.
--pod-network-cidr	10.244.0.0/16	Obligāts CNI iestatīšanai. Tīkla diapazons, ko izmantos Pods (standarta diapazons, ko izmanto Weave Net).
--cri-socket	unix:///var/run/crio/crio.sock	Norāda CRI izpildlaiku. Šeit tiek norādīts CRI-O socket, kuru jūs tikko veiksmīgi instalējāt.
===================================================

# sudo kubeadm token create --print-join-command
# sudo kubeadm init phase upload-certs --upload-certs