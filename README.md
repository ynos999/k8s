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
2 - 6.yml:
# ansible-playbook -i hosts_wolf.ini master_playbook.yml

# 2. ansible-playbook -i hosts_wolf.ini 2_keepalived.yml
---
# 3. ansible-playbook -i hosts_wolf.ini 3_ca_import.yml
---
# 4. ansible-playbook -i hosts_wolf.ini 4_k8s_ha.yml
===
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

Open Leans tunelis:
ssh -i .\id_ed25519_vm -L 6443:192.168.1.199:6443 wolf@192.168.1.199
scp -i .\id_ed25519_vm wolf@192.168.1.199:~/.kube/config C:\Users\wolf\.kube\
ssh -i .\id_ed25519_vm -L 6443:192.168.1.199:6443 -N wolf@192.168.1.199

netstat -ano | findstr 6443

Labo 
- cluster: C:\Users\wolf\.kube\config
    # certificate-authority-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURCVENDQWUyZ0F3SUJBZ0lJZFg0WUxNRmk0em93RFFZSktvWklodmNOQVFFTEJRQXdGVEVUTUJFR0ExVUUKQXhNS2EzVmlaWEp1WlhSbGN6QWVGdzB5TlRFeE1qa3dPVE01TWpCYUZ3MHpOVEV4TWpjd09UUTBNakJhTUJVeApFekFSQmdOVkJBTVRDbXQxWW1WeWJtVjBaWE13Z2dFaU1BMEdDU3FHU0liM0RRRUJBUVVBQTRJQkR3QXdnZ0VLCkFvSUJBUURJRnFrOUh2VFRQQ1A2SlhxbUcraDZ3Z2FQbTRHNFZjbTA2eTE4WjUvNzMrYkIrUUFVclVhbDFiZ00KK2hHanY5K1hCUmxpRTZqZHR2YXh3MzZORWZCK29SSlhwMmdBYnROdkZiNW9ZS3AvakdyckJkeGw3UVdwSE9OZApSR3NxZDlnTEU5NzhCRmJhcE5XanBtaDBnRHh6OC95Qm1JeVBKanlpaWk0azRyVGxUcUFDYndMZGc4TVhSdndBCnFrVU4rU3J4Ymh2Nkp0dUNvQk9rQkhDb3dDeDJWUHRlOUtKUjVodFRKVlR1UU1tUjdwTGdoeDNsOXczZkFsRVMKUiszMjRtWXhMdnlrMExqVGRCT2lzOVlIWHRoMzNmd2RSWUZlaDNBNWtjSURMRFVTdXF1ajRNKzBnS0RXYXFJRQpuZk55cmZQMFlTL2pNaTA2YWlocjY3WTZEY01YQWdNQkFBR2pXVEJYTUE0R0ExVWREd0VCL3dRRUF3SUNwREFQCkJnTlZIUk1CQWY4RUJUQURBUUgvTUIwR0ExVWREZ1FXQkJRT0U2NkRNbHZzQmJmbkJxRkNMQUswZCtiTWh6QVYKQmdOVkhSRUVEakFNZ2dwcmRXSmxjbTVsZEdWek1BMEdDU3FHU0liM0RRRUJDd1VBQTRJQkFRQXBnUVMyaytETgpvcWZTcGZ4TzFxRXNkQVFxVm9nTTNlbnlvcjZiZlR6OFYvampYc01VdkdZVnU3RktSSURPemdpRXVONE5ha29yCkFVclVhVEE1bkZNTjhpdENXNVpRcnZYUG1EaER6RWRpdDVIUC9iOFc0bmowZThaVEhMMm9STEpqMEF3MGRPQUsKNEIvRW1pREFNdHRab0ZYbGlIUk9GTHA2dThLaFlOTnhZaTlkSUQreEpPN0VTWHoxMTcrMC9Ibzc3andIUTlNMwoveWhaTFlXalJvMFBTbFJhVFR1YzhRQ1hGcWUxbElEclNsc29DTHlkM3hnWmYzcjI2R0FKZzlsQ29CaDJpOUNnCklLMnQzSS9TQ0lSMTc0TEplZFVHRlJGc2x5RWZYMFRSeVEyaWE1NDZFaXFsNm9RZDJqRWZ1TXRBQ3hKc25jWmsKbk5UZ2VsV3FvRElICi0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K
    server: https://localhost:6443
    insecure-skip-tls-verify: true

kubectl get nodes     
NAME      STATUS   ROLES           AGE   VERSION
master1   Ready    control-plane   95m   v1.33.6
master2   Ready    control-plane   88m   v1.33.6
master3   Ready    control-plane   87m   v1.33.6

choco install kubernetes-helm