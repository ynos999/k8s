cat /etc/os-release
sudo apt update && sudo apt install software-properties-common -y
sudo add-apt-repository --yes --update ppa:ansible/ansible && sudo apt install ansible -y
# 0.1 Uz datora izģenerēt ssh atslēgu vai iekopēt.
sudo ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519_vm
# 0.2 rediģējiet hosts.ini failu. Labot ansible_host, ansible_user, ansible_password
# 0.3 rediģējiet hosts_wolf.ini failu. Labot ansible_host, ansible_user, ansible_password
# 0.4 Ģenerēt CA privāto atslēgu vai kopēt no mapes. Mapē jābūt ca.crt.
openssl genrsa -aes256 -out ca.key 4096
openssl req -new -x509 -sha256 -key ca.key -out ca.crt -days 3650
# 0.5 Labojam /etc/hosts 1_setup.yml, 46.62.220.209 master1, 65.108.85.35 master2
# 0.6 Labojam 2_keepalived.yml vip: "10.10.1.30/32", interface: "enp7s0" (ip a)
# 0.7 Labojam 6_metalb_traefik.yml vip: 10.10.1.30 metallb_ip_range: "10.10.1.30-10.10.1.30", demo_host: demo.www.latloto.lv
# 0.8 Kopēt privāto atslēgu (šo pieliku 1_setup)
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
Uz master1 jāizpilda (controlPlaneEndpoint labojam):

cat <<EOF | sudo tee kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: stable
controlPlaneEndpoint: "10.10.0.30:6443" # Labojam!
networking:
  podSubnet: "172.16.0.0/16"
  serviceSubnet: "172.17.0.0/12"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  bindAddress: 10.10.0.2 # <--- IEKŠĒJĀ IP jālabo
  bindPort: 6443
nodeRegistration:
  criSocket: "unix:///var/run/crio/crio.sock"
EOF
===
sudo kubeadm init --config=kubeadm-config.yaml --upload-certs

===
Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:

  export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

You can now join any number of control-plane nodes running the following command on each as root:

  kubeadm join 10.10.0.30:6443 --token alhl7q.9qjsmb8wqrx2qp2p \
	--discovery-token-ca-cert-hash sha256:18edb9156e84cbea365c7d9753ff0bda96122846c4b19ac5ea77b4943dfe22ef \
	--control-plane --certificate-key 85f34af99293db62de2210410a49ba0ac3717726cb0bd03368ebd1de6d7c07dc

Please note that the certificate-key gives access to cluster sensitive data, keep it secret!
As a safeguard, uploaded-certs will be deleted in two hours; If necessary, you can use
"kubeadm init phase upload-certs --upload-certs" to reload certs afterward.

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 10.10.0.30:6443 --token alhl7q.9qjsmb8wqrx2qp2p \
	--discovery-token-ca-cert-hash sha256:18edb9156e84cbea365c7d9753ff0bda96122846c4b19ac5ea77b4943dfe22ef

kubectl get nodes
kubectl get po -A
kubectl get pods -n kube-system

# Pēc kubeadm init un konfigurācijas iestatīšanas uz Master 1 weave
kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
---
7. Uzlikt MetalLB (Layer 2) + Traefik kā Ingress Controller
# ansible-playbook -i hosts_wolf.ini 5_install_helm.yml
vai
# Uz Master 1 VM Helm:

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

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
      - 10.10.0.30-10.10.0.30
EOF

JĀLABO IP!

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

JĀLABO POOL!
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