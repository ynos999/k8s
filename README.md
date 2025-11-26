sudo apt update && sudo apt install software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible && sudo apt install ansible -y
# 0.1 Uz datora izģenerēt ssh atslēgu.
sudo ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519_vm
# 0.2 rediģējiet hosts.ini failu.
# 0.3 rediģējiet hosts_wolf.ini failu.
# 0.4 Ģenerēt CA privāto atslēgu
openssl genrsa -aes256 -out ca.key 4096
Izveidojiet pašparakstītu CA sertifikātu
openssl req -new -x509 -sha256 -key ca.key -out ca.crt -days 3650
# 0.5 Kopēt privāto atslēgu (šo pieliku 1_setup)
sudo scp -i ~/.ssh/id_ed25519_vm ~/.ssh/id_ed25519_vm wolf@master1:~/.ssh/
sudo scp -i ~/.ssh/id_ed25519_vm ~/.ssh/id_ed25519_vm wolf@master2:~/.ssh/
sudo scp -i ~/.ssh/id_ed25519_vm ~/.ssh/id_ed25519_vm wolf@master3:~/.ssh/
sudo scp -i ~/.ssh/id_ed25519_vm ~/.ssh/id_ed25519_vm wolf@worker1:~/.ssh/
sudo scp -i ~/.ssh/id_ed25519_vm ~/.ssh/id_ed25519_vm wolf@worker2:~/.ssh/
sudo chmod 600 ~/.ssh/id_ed25519_vm
---
# 1. ansible-playbook -i hosts.ini 1_setup.yml
---
# 2. ansible-playbook -i hosts_wolf.ini 2_keepalived.yml
---
# 3. ansible-playbook -i hosts_wolf.ini 3_ca_import.yml
---
# 4. ansible-playbook -i hosts_wolf.ini 4_k8s_ha.yml
===
master1 10.10.0.2
master2 10.10.0.3
VIP: 10.10.0.30
===
Uz master1 jāizpilda:

cat <<EOF | sudo tee kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: stable
controlPlaneEndpoint: "10.10.0.30:6443"
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  bindAddress: 10.10.0.2 # <--- IEKŠĒJĀ IP
  bindPort: 6443
nodeRegistration:
  criSocket: "unix:///var/run/crio/crio.sock"
EOF
===
sudo kubeadm init --config=kubeadm-config.yaml --upload-certs

===
To start using your cluster, you need to run the following as a regular user:
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

You can now join any number of control-plane nodes running the following command on each as root:

  kubeadm join 10.10.0.30:6443 --token b21j0t.9zq1dbp1p09eu8dc \
	--discovery-token-ca-cert-hash sha256:32e163147af6afffb6f90b6da9c9f71d03b2ca8bf3bc4b1c9556e9514ed869ee \
	--control-plane --certificate-key abe474090300517159cc7741abd6703fc498ab25c6acb72df0031cf1df8ccb2b

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 10.10.0.30:6443 --token b21j0t.9zq1dbp1p09eu8dc \
	--discovery-token-ca-cert-hash sha256:32e163147af6afffb6f90b6da9c9f71d03b2ca8bf3bc4b1c9556e9514ed869ee

# Pēc kubeadm init un konfigurācijas iestatīšanas uz Master 1 weave
kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml

kubectl get nodes
kubectl get po -A
kubectl get pods -n kube-system
---
7. Uzlikt MetalLB (Layer 2) + Traefik kā Ingress Controller
# ansible-playbook -i hosts_wolf.ini 5_install_helm.yml
vai
# Uz Master 1 VM Helm:

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm install traefik traefik/traefik \
  --namespace kube-system \
  --set service.type=LoadBalancer \
  --set service.loadBalancerIP="10.10.1.30" \
  --set service.annotations."metallb\.universe\.tf/address-pool"="external-ip-pool" \
  --set providers.kubernetesIngress.ingressClass=traefik \
  --set providers.kubernetesIngress.publishedService.enabled=true \
  --set providers.kubernetesIngress.publishedService.ingressClassName=traefik

kubectl get svc traefik -n kube-system

# ansible-playbook -i hosts_wolf.ini 6_metalb_traefik.yml
kubectl create namespace metallb-system
kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.3/config/manifests/metallb-native.yaml

kubectl get pods -n metallb-system
kubectl get svc webhook-service -n metallb-system

vai:
helm upgrade --install metallb metallb/metallb --namespace metallb-system
nano metallb-config.yaml

apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  namespace: metallb-system
  name: layer2-pool
spec:
  addresses:
    - 10.10.1.30-10.10.1.30

---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  namespace: metallb-system
  name: l2-advert

kubectl apply -f metallb-config.yaml

8. Panākt, lai viens un tas pats virtuālais IP apkalpo gan Kubernetes API, gan ārējo HTTP/HTTPS trafiku
9. Atrisināt ARP konfliktu ar KeepAlived (allow-shared-ip triks)  
10. Uzlikt TLS sertifikātu, 80 → 443 redirect un vienkāršu demo URL ar HTTPS