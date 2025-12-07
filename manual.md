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
# Labojam vip: "192.168.1.190/32", interface: "enp7s0" (ip a)

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
export KUBERNETES_VERSION=v1.33
export CRIO_VERSION=v1.32
curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

echo 'deb http://download.opensuse.org/repositories/isv:/cri-o:/stable:/v1.33/deb/ /' | sudo tee /etc/apt/sources.list.d/isv:cri-o:stable:v1.33.list
curl -fsSL https://download.opensuse.org/repositories/isv:cri-o:stable:v1.33/deb/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/isv_cri-o_stable_v1.33.gpg > /dev/null

sudo apt update && sudo apt upgrade -y && sudo apt install -y cri-o kubelet kubeadm kubectl

sudo systemctl start crio && sudo systemctl enable crio && sudo systemctl status crio
sudo apt-mark hold kubelet kubeadm kubectl
sudo kubeadm version
sudo systemctl enable --now kubelet

# Labojam controlPlaneEndpoint, vip: 10.10.1.30 metallb_ip_range: "10.10.1.30-10.10.1.30", demo_host: demo.www.latloto.lv
# sudo systemctl status keepalived
# ip a show enp7s0


master1 192.168.1.199
master2 192.168.1.198
master3 192.168.1.197
VIP: 192.168.1.190
===
Uz master1 jāizpilda (controlPlaneEndpoint labojam):

cat <<EOF | sudo tee kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: stable-1.33
controlPlaneEndpoint: "192.168.1.190:6443"
networking:
  podSubnet: "172.16.0.0/16"
  serviceSubnet: "172.17.0.0/12"

---
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
nodeRegistration:
  name: "master1"
  criSocket: "unix:///var/run/crio/crio.sock"
EOF
===
sudo kubeadm init --config=kubeadm-config.yaml --upload-certs

----
Reset kubeadm
sudo kubeadm reset -f
sudo systemctl stop kubelet
sudo pkill kubelet
sudo lsof -i :6443
sudo lsof -i :2379
sudo rm -rf /var/lib/etcd/*
----

===
Regular user:
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:
  export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

You can now join any number of control-plane nodes running the following command on each as root:

  kubeadm join 192.168.1.190:6443 --token mn8ngd.c2icinibzb7ziity \
        --discovery-token-ca-cert-hash sha256:be73ebeed224653500dcf3ee81c8a79f4ca354c6cec01b9c2fc13297d52a6380 \
        --control-plane --certificate-key 5eaea2cba3f2977e32d02fff4e8a9f8dc7a3d80f83b40bbf632bbf6da4628762

Please note that the certificate-key gives access to cluster sensitive data, keep it secret!
As a safeguard, uploaded-certs will be deleted in two hours; If necessary, you can use
"kubeadm init phase upload-certs --upload-certs" to reload certs afterward.

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 192.168.1.190:6443 --token mn8ngd.c2icinibzb7ziity \
        --discovery-token-ca-cert-hash sha256:be73ebeed224653500dcf3ee81c8a79f4ca354c6cec01b9c2fc13297d52a6380

kubectl get nodes
kubectl get po -A
kubectl get pods -n kube-system

kubeadm token create
kubeadm token create --print-join-command
Then reload and restart kubelet:
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Pēc kubeadm init un konfigurācijas iestatīšanas uz Master 1 weave
kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml

Dzēst weave, arm64 nestrādā:
kubectl delete -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
sudo rm -rf /etc/cni/net.d/10-weave.conflist
sudo rm -rf /etc/cni/net.d/weave-kube*
sudo systemctl restart kubelet

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

Pieņemsim, ka jūsu KeepAlived VIP ir 192.168.1.190.

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
  - 192.168.1.190-192.168.1.190
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

kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: layer2-pool
      protocol: layer2
      addresses:
      - 192.168.1.190-192.168.1.190
EOF

# Uz Master 1 VM Helm:
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm install traefik traefik/traefik \
  --namespace kube-system \
  --set service.type=LoadBalancer \
  --set service.loadBalancerIP="192.168.1.190" \
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
    - match: "Host(`192.168.1.190`)" # Izmantojiet saskaņoto VIP!
      kind: Rule
      entryPoints:
        - web # Piesaista pie HTTP (80)
      middlewares:
        - name: redirect-to-https
      services:
        - name: whoami-service
          port: 80
  
  # 2. FAKTISKĀ HTTPS TRAFIKA
    - match: "Host(`192.168.1.190`)" # Izmantojiet saskaņoto VIP!
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

Taint node-role.kubernetes.io/control-plane tiek noņemts no node.
Tas ļauj, lai pods varētu tikt izvietots uz master mezgla, kas normāli tiek bloķēts.
Ja tev nav worker mezgli, tad šis ir obligāts solis, lai metallb vai citi pods varētu tikt izvietoti uz master.

# Izpildiet uz katra Master mezgla, ja tie ir vienādi
kubectl taint node master1 node-role.kubernetes.io/control-plane-
kubectl taint node master2 node-role.kubernetes.io/control-plane-
kubectl taint node master3 node-role.kubernetes.io/control-plane-

kubectl taint node master1 node-role.kubernetes.io/control-plane:NoSchedule
kubectl taint node master2 node-role.kubernetes.io/control-plane:NoSchedule
kubectl taint node master3 node-role.kubernetes.io/control-plane:NoSchedule

kubectl describe node master1 | grep Taint
kubectl describe node master2 | grep Taint
kubectl describe node master3 | grep Taint


- name: Remove master taints
  hosts: masters
  become: yes
  tasks:
    - name: Remove control-plane taint
      shell: kubectl taint node {{ inventory_hostname }} node-role.kubernetes.io/control-plane- --ignore-not-found
      environment:
        KUBECONFIG: /etc/kubernetes/admin.conf

ssh -i .\id_ed25519_vm -L 6443:192.168.1.199:6443 -N wolf@192.168.1.199

kubectl get ipaddresspools -n metallb-system
kubectl get pods -n metallb-system


helm list --all-namespaces
kubectl get pods -n traefik
kubectl describe pod traefik-5db9bb6877-bwxgh -n traefik
kubectl logs traefik-5db9bb6877-bwxgh -n traefik
helm uninstall traefik -n traefik
kubectl delete deployment traefik -n traefik
kubectl delete service traefik -n traefik
kubectl delete secret wildcard-tls -n traefik

kubectl get secret wildcard-tls -n traefik -o jsonpath='{.data.tls\.crt}' | base64 -d
kubectl get secret wildcard-tls -n traefik -o jsonpath='{.data.tls\.key}' | base64 -d

kubectl create secret generic metallb-memberlist \
  --namespace metallb-system \
  --from-literal=secretkey="$(openssl rand -base64 128)"


Ja izmantoji Helm instalāciju:
helm -n metallb-system uninstall metallb
Tas dzēs visus Helm resursus (Deployment, Service, ConfigMap utt.), kas saistīti ar MetalLB release.
Ja Helm release bija bloķēts, var dzēst arī Helm secret:
kubectl -n metallb-system delete secret sh.helm.release.v1.metallb.v1
kubectl -n metallb-system delete secret sh.helm.release.v1.metallb.v2


sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl create secret tls wildcard-tls \
  --cert=/root/certs/wildcard.crt \
  --key=/root/certs/wildcard.key \
  -n traefik


sudo systemctl stop kubelet
sudo systemctl stop crio
sudo systemctl restart crio
sudo systemctl restart kubelet

sudo systemctl restart kubelet
kubectl get nodes -o wide

sudo mkdir -p /etc/traefik/certs
sudo cp /root/certs/wildcard.* /etc/traefik/certs/
sudo chown -R $(whoami):$(whoami) /etc/traefik/certs


----
Reset kubeadm:
sudo kubeadm reset -f
sudo systemctl stop kubelet
sudo pkill kubelet
sudo lsof -i :6443
sudo lsof -i :2379
sudo rm -rf /var/lib/etcd/*


----------------------------
Tā ir diezgan kompleksa uzdevumu virkne, kas aptver vairākas svarīgas Kubernetes komponentes. Es paskaidrošu katru soli, koncentrējoties uz nepieciešamajām komandām un konfigurācijām.

## 1\. MetalLB uzstādīšana (Layer 2 režīms)

MetalLB nodrošina *LoadBalancer* servisu implementāciju, kas nepieciešama jūsu klasterī, jo tas nav izvietots publiskā mākonī.

### Uzstādīšana

MetalLB uzstāda, izmantojot **Helm** vai **Manifestus**. Izmantosim manifestus, jo tā ir oficiālā metode, kas ļauj viegli norādīt nepieciešamo vārda telpu.

```bash
# 1. Izveidot metallb-system vārda telpu, ja tā vēl nav
kubectl create namespace metallb-system

# 2. Uzstādīt MetalLB ar manifestu
# Pārbaudiet jaunāko versiju MetalLB dokumentācijā. Šis ir piemērs.
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb.yaml
```

### Konfigurācija (Layer 2 un Adreses)

Pēc uzstādīšanas ir jādefinē **IP Adrešu Baseins** un **Layer 2 konfigurācija**.

Izveidojiet failu ar nosaukumu `metallb-config.yaml`:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: traefik-vip-pool
  namespace: metallb-system
spec:
  # Šeit norādam TIKAI to IP adresi, ko vēlamies izmantot (192.168.1.190)
  addresses:
  - 192.168.1.190/32 

---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: traefik-l2-advertisement
  namespace: metallb-system
spec:
  # Norādam, ka reklamēsim IP no iepriekš definētā baseina
  ipAddressPools:
  - traefik-vip-pool
  # Var pievienot papildus iestatījumus, ja nepieciešams, 
  # bet šis ir pietiekams Layer 2 pamatrežīmam
```

```bash
# Pielietot konfigurāciju
kubectl apply -f metallb-config.yaml
```

-----

## 2\. Traefik kā Ingress Controller un LoadBalancer Serviss

Izmantosim oficiālo Helm chart.

### Sertifikātu sagatavošana

Pirms Traefik uzstādīšanas ir jāielādē jūsu sertifikāts. Jums ir sertifikāts (`*.iloto.lldev`) un atslēga, kas atrodas `/root/certs` mapē uz `master-node-01`.

1.  **Izveidojiet Kubernetes Secret:**
    Pieņemot, ka jūsu faili ir `cert.pem` (wildcard sertifikāts) un `key.pem` (privātā atslēga) mapē `/root/certs` uz `master-node-01`.

    ```bash
    # Pārliecinieties, ka esat master-node-01
    cd /root/certs
    # Izveidot secret traefik vārda telpā. Ja tā vēl nav, tā tiks izveidota ar Helm
    kubectl create secret tls iloto-wildcard-tls --cert=cert.pem --key=key.pem -n traefik
    ```
  # Apvienot sertifikātus: Servera > Intermediate 2 > Intermediate 1

cat wildcard.iloto.lldev.crt latloto-intermediate-server-v2.crt latloto-intermediate-server-v1.crt > combined-chain.crt

# Izveidot secret 'iloto-wildcard-tls' Traefik vārda telpā
kubectl create secret tls iloto-wildcard-tls \
  --cert=combined-chain.crt \
  --key=wildcard.iloto.lldev.key \
  -n traefik

### Traefik uzstādīšana ar Helm

Izveidosim `values.yaml` failu Traefik konfigurācijai.

```yaml
# traefik-values.yaml
# --- Traefik Service konfigurācija (LoadBalancer ar specifisku IP) ---
service:
  enabled: true
  type: LoadBalancer
  annotations:
    # MetalLB anotācija, lai atļautu dalīt šo IP ar KeepAlived VIP (192.168.1.190)
    metallb.universe.tf/allow-shared-ip: "k8s-shared-vip" 
  spec:
    # MetalLB piešķirs tieši šo IP adresi (jābūt IPAddressPool)
    loadBalancerIP: 192.168.1.190 

# --- Traefik Konfigurācija (Ingress Controller) ---
providers:
  kubernetesIngress:
    enabled: true

# --- Traefik HTTPS/HTTP konfigurācija ---
# Ieslēgt TLS Listener (443 ports)
tls:
  enabled: true

# Definēt Globālo/Default TLS Konfigurāciju
globalArguments:
  - --entrypoints.web.address=:80
  - --entrypoints.websecure.address=:443
  
  # Iestatīt Default Sertifikātu uz jūsu wildcard sertifikātu
  - --entrypoints.websecure.tls.defaultcertificate.secretname=iloto-wildcard-tls
  - --entrypoints.websecure.tls.defaultcertificate.namespace=traefik

# HTTP uz HTTPS novirzīšana (Entrypoint 'web' uz 'websecure')
additionalArguments:
  - --entrypoints.web.http.redirections.entrypoint.to=:443
  - --entrypoints.web.http.redirections.entrypoint.scheme=https
  - --entrypoints.web.http.redirections.entrypoint.permanent=true

# --- Pārējie iestatījumi ---
ports:
  web:
    redirectTo: websecure # Tiek pārdefinēts ar additionalArguments
  websecure:
    tls:
      enabled: true

# Izmantojiet tikai Traefik vārda telpu
namespace: traefik
```

```bash
# Pievienot Traefik Helm repozitoriju
helm repo add traefik https://helm.traefik.io/traefik
helm repo update

# Uzstādīt Traefik, izveidojot "traefik" vārda telpu un izmantojot konfigurāciju
helm install traefik traefik/traefik -n traefik --create-namespace -f traefik-values.yaml
```

Pārbaudiet, vai Traefik LoadBalancer serviss saņēma IP:

```bash
kubectl get svc traefik -n traefik
# Jāredz EXTERNAL-IP kā 192.168.1.190
```

-----

## 3\. "Hello World" Aplikācijas Uzstādīšana

Izmantosim **bitnami/nginx** kā piemēru.

```bash
# Pievienot bitnami repozitoriju
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Uzstādīt Nginx kā "hello-app"
helm install hello-app bitnami/nginx -n default --set ingress.enabled=false
```

-----

## 4\. Ingress Resursa Izveidošana

Tagad ir jāizveido *Ingress* resurss, kas:

1.  Novirza trafiku no `http://hello.iloto.lldev` uz `https://hello.iloto.lldev`.
2.  Izmanto iepriekš sagatavoto `iloto-wildcard-tls` sertifikātu.

Izveidojiet failu `hello-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-ingress
  annotations:
    # 1. Traefik anotācija, lai veiktu HTTP uz HTTPS novirzīšanu
    traefik.ingress.kubernetes.io/router.entrypoints: web, websecure
    traefik.ingress.kubernetes.io/router.middlewares: default-redirect-to-https@kubernetescrd
spec:
  # 2. TLS sertifikāta definīcija
  tls:
  - hosts:
    - hello.iloto.lldev
    secretName: iloto-wildcard-tls # Nosaukums jūsu secret, kas atrodas "traefik" namespace!

  # 3. Ingress noteikumi
  rules:
  - host: hello.iloto.lldev
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: hello-app # Tas būs bitnami/nginx servisa nosaukums (pēc noklusējuma tāds)
            port:
              number: 80 # Nginx ports
```

> **Svarīga Piezīme par TLS Secret:** Ingress resurss atsaucas uz **Service** vārda telpu (šajā gadījumā `default`), bet Traefik kā Ingress Controller meklē **TLS Secret** savā vārda telpā (`traefik`), ja nav norādīts citādi (dažreiz tas jānorāda ar papildus anotāciju, bet Traefik noklusējuma konfigurācija to parasti atbalsta).

Papildus ir jāizveido **Traefik Middleware**, kas veiks novirzīšanu, jo tas ir jādara ar Traefik IngressRoute/Middleware resursiem, nevis tikai ar Ingress anotācijām.

Izveidojiet failu `redirect-middleware.yaml` Traefik vārda telpā:

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: redirect-to-https
  namespace: default # Middleware jāatrodas tajā pašā vārda telpā, kur Ingress!
spec:
  redirectScheme:
    scheme: https
    permanent: true
```

```bash
# Pielietot Middleware
kubectl apply -f redirect-middleware.yaml

# Pielietot Ingress
kubectl apply -f hello-ingress.yaml

# Pārbaudīt, vai Ingress resurss ir izveidots
kubectl get ingress hello-ingress -n default
```

### Pārbaude

1.  Pārbaudiet, vai jūsu vietējais dators spēj atrisināt `hello.iloto.lldev` uz **192.168.1.190** (jāpievieno hosts failā, ja nav DNS).
2.  Atveriet pārlūkprogrammā: `http://hello.iloto.lldev`. Tam automātiski jānovirza uz `https://hello.iloto.lldev`.
3.  Pārlūkprogrammai jāparāda "Hello World" aplikācijas saturs ar derīgu TLS savienojumu, ko parakstījis jūsu CA.

Vai vēlaties, lai es detalizētāk paskaidrotu kādu no šiem soļiem, piemēram, **Helm vērtību** nozīmi Traefik konfigurācijā?



1. wget https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
2. nano kube-flannel.yml mainam uz 172.16.0.0/16
3. kubectl apply -f kube-flannel.yml
4. kubectl get pods -n kube-flannel
kubectl run netshoot-a --image=nicolaka/netshoot -- sleep infinity
kubectl run netshoot-b --image=nicolaka/netshoot -- sleep infinity
kubectl get nodes
kubectl get pods netshoot-a netshoot-b
kubectl describe pod netshoot-a
kubectl taint nodes master1 node.cilium.io/agent-not-ready:NoSchedule-
kubectl taint nodes master2 node.cilium.io/agent-not-ready:NoSchedule-
kubectl taint nodes master3 node.cilium.io/agent-not-ready:NoSchedule-
kubectl taint nodes worker1 node.cilium.io/agent-not-ready:NoSchedule-
kubectl taint nodes worker2 node.cilium.io/agent-not-ready:NoSchedule-
POD_B_IP=$(kubectl get pod netshoot-b -o jsonpath='{.status.podIP}')
echo "netshoot-b IP adrese: $POD_B_IP"

kubectl exec -it netshoot-b -- nc -l -p 8080
Uz citas nodes:
kubectl exec netshoot-a -- nc -vz 172.16.4.2 8080

kubectl delete pod netshoot-a netshoot-b

kubectl delete -f kube-flannel.yml


  1. CNI Nestrādāšanas Cēloņi (Kopsavilkums)
Problēma nebija viena, bet gan trīs dažādas kļūdas, kas bloķēja Flannel darbību, parasti radot stāvokli CrashLoopBackOff vai Pending:

1. Zema līmeņa OS (Linux Kodols) Kļūdas
Šīs bija pirmās kļūdas, kas neļāva CNI aģentam veikt pamata tīkla darbības:

Trūkstošs kodola modulis: Uz mezgliem nebija ielādēts modulis br_netfilter, kas ir nepieciešams, lai VXLAN (Flannel tunelēšana) integrētos ar Linux tilta (bridge) funkcionalitāti.

sysctl vērtība: Kodola iestatījums net.bridge.bridge-nf-call-iptables nebija iestatīts uz 1, kas neļāva iptables redzēt tiltu trafiku.

2. Augsta līmeņa Konfigurācijas Konflikts
Pēc kodola problēmas atrisināšanas, CNI avarēja jau cita iemesla dēļ:

CIDR nesakritība: Jūsu kubeadm klasteris tika inicializēts ar Podu CIDR diapazonu 172.16.0.0/16, bet Flannel konfigurācijas karte (ConfigMap) joprojām saturēja noklusējuma Flannel diapazonu 10.244.0.0/16. Flannel nevarēja iegūt tīkla nomu no klastera.

3. Cilium Atliekas (Taint)
Pēc tam, kad Flannel sāka strādāt, darba slodzes nespēja startēt:

Atdzīvināts Taint: Pēc neveiksmīgas Cilium instalācijas, uz mezgliem palika atzīme (Taint): node.cilium.io/agent-not-ready. Kubernetes Plānotājs to uzskatīja par aizliegumu un neļāva testa podiem (netshoot-a/b) pāriet no Pending stāvokļa.

---
Pārbaudīt Traefik Servisu un IP Adresi
Vispirms pārliecinieties, ka MetalLB ir veiksmīgi piešķīris Traefik LoadBalancer servisam paredzēto IP adresi (192.168.4.190).
kubectl get svc traefik -n traefik
Pārbaudīt Traefik IngressRoute
kubectl get ingressroute,tlsstore,middleware -n default
A.
curl -k https://192.168.4.190/ -H "Host: hello.iloto.lldev"
B. 
curl -I -v http://192.168.4.190/ -H "Host: hello.iloto.lldev"

kubectl describe svc traefik -n traefik
kubectl get svc traefik -n traefik

Šis izvads skaidri atklāj problēmas cēloni!

Problēma nav tīkla konfliktā ar ārēju ierīci, bet gan konfliktā pašā Kubernetes klasterī ar citu Servisu vai IngressRoute.

Galvenais Cēlonis: IP Adrese Lietošanā ar Citu Servisu
Aplūkojot sadaļu Events:

Warning AllocationFailed 11m metallb-controller Failed to allocate IP for "traefik/traefik": can't change sharing key for "traefik/traefik", address also in use by default/traefik-crd
1. Konflikta Adrese un Resurss
IP Adrese: 192.168.4.190

Kļūda: address also in use by default/traefik-crd

Kļūdas iemesls: can't change sharing key for "traefik/traefik"

Tas nozīmē, ka MetalLB kontrolieris redz, ka IP adrese 192.168.4.190 jau ir piesaistīta kādam citam resursam ar nosaukumu traefik-crd vārda telpā default. Šis vecais resurss, visticamāk, ir palicis pāri no viena no jūsu agrīnajiem (un neveiksmīgajiem) Traefik instalēšanas mēģinājumiem.

2. "Sharing Key" Konflikts
MetalLB izmanto metallb.universe.tf/allow-shared-ip anotāciju (k8s-shared-vip) Servisā, lai ļautu vairākiem LoadBalancer Servisiem izmantot vienu un to pašu IP adresi. Tomēr, ja viens no Servisiem (vecais traefik-crd no default namespace) šo anotāciju vai IP bija piesaistījis bez koplietošanas atbalsta, MetalLB neļaus jaunajam Servisam (šim traefik/traefik) pārņemt IP adresi.

🛠️ Risinājums: Konfliktējošā Resursa Noņemšana
Jums ir jāatrod un jāizdzēš vecais, konfliktējošais resurss traefik-crd vārda telpā default.

Solis 1: Atrodiet un Pārbaudiet Konfiktējošo Resursu
Pārbaudiet, kas tieši ir traefik-crd. Tas varētu būt Service vai IngressRoute.
# Meklēt Service ar šo nosaukumu:
kubectl get svc traefik-crd -n default
# Vai arī meklēt IngressRoute/citu resursu:
kubectl get all -n default | grep traefik
Dzēsiet Konfliktējošo Resursu
Kad esat identificējis tā tipu (piemēram, tas ir Service), izdzēsiet to:
# Pieņemsim, ka tas ir Service:
kubectl delete svc traefik-crd -n default
# Ja tas ir IngressRoute:
# kubectl delete ingressroute traefik-crd -n default

kubectl get ingressroute -n default
kubectl get middleware redirect-to-https -n default -o yaml


1. Importēt Saknes CA Sertifikātu (latloto-ca.crt)
Importējot Saknes CA sertifikātu, jūs dodat Firefox rīkojumu uzticēties visiem sertifikātiem, ko parakstījusi šī iestāde (ieskaitot jūsu wildcard sertifikātu).

Atveriet Iestatījumus: Firefox atveriet Iestatījumi (Settings).

Meklēt Sertifikātus: Kreisajā pusē izvēlieties Privātums un Drošība (Privacy & Security). Ritiniet uz leju līdz sadaļai Drošība (Security).

Sertifikātu Pārvaldība: Noklikšķiniet uz pogas Sertifikāti (Certificates) vai Skatīt Sertifikātus (View Certificates).

Importēšana: Cilnē Iestādes (Authorities) noklikšķiniet uz pogas Importēt...

Izvēlieties failu: Atrodiet un izvēlieties failu latloto-ca.crt.

Uzticēšanās Uzstādīšana: Parādīsies dialoglodziņš. Atzīmējiet izvēles rūtiņu: Uzticēties šai CA, lai identificētu vietnes (Trust this CA to identify websites).

Noklikšķiniet uz Labi.

https://manual.iloto.lldev/
https://data.iloto.lldev/
https://hello.iloto.lldev/