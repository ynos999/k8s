1. Add the Helm Chart Repository
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
2. Create a Namespace for Rancher
kubectl create namespace cattle-system
3. Choose your SSL Configuration
Configuration	Helm Chart Option	Requires cert-manager
Rancher Generated Certificates (Default)	ingress.tls.source=rancher	yes
Let’s Encrypt	ingress.tls.source=letsEncrypt	yes
Certificates from Files	ingress.tls.source=secret	no
4. Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.1/cert-manager.yaml

vai

helm install \
  cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.19.1 \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true

5. Install Rancher with Helm and Your Chosen Certificate Option


helm install rancher rancher-<CHART_REPO>/rancher \
  --namespace cattle-system \
  --set hostname=rancher.iloto.lldev \
  --set bootstrapPassword=admin \
  --set ingress.tls.source=secret \
  --set privateCA=true

kubectl get pods --namespace cert-manager


6. 
kubectl -n cattle-system rollout status deploy/rancher
kubectl -n cattle-system get deploy rancher
kubectl get pods -n cattle-system
kubectl describe pod [RANCHER_POD_NAME] -n cattle-system

helm uninstall rancher --namespace cattle-system
helm uninstall cert-manager --namespace cert-manager
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.1/cert-manager.yaml

kubectl delete namespace cattle-system
kubectl delete namespace cert-manager

Problēma ar worker2 vietu:
# Dzēš visus (apturētos) konteinerus
sudo crictl rm --all
# Dzēš visus podu smilšu kastes (pod sandbox)
sudo crictl rmp --all --force
# Dzēš visus attēlus, kurus pašlaik neizmanto palaisti konteineri
sudo crictl rmi --all

# Dzēš visus podus ar statusu Error, Evicted un Failed
kubectl delete pods -n cattle-system --field-selector status.phase=Failed
kubectl delete pods -n cattle-system --field-selector status.phase=Evicted


# Pievienot otru disku:
---
sudo pvcreate /dev/sdb
sudo vgextend ubuntu-vg /dev/sdb
# Izmanto visu pieejamo brīvo vietu
sudo lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv
# Pārbaudiet, vai failsistēma ir ext4 (visbiežāk)
sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
---

# Formatēt un Montēt šo nevajag

sudo mkfs.ext4 /dev/sdb
sudo mkdir -p /mnt/k8s-data
sudo mount /dev/sdb /mnt/k8s-data
sudo pvdisplay /dev/sdb
sudo vgdisplay
df -h

kubectl logs rancher-84bc8d56bc-fp7fl -n cattle-system --tail=50


https://ranchermanager.docs.rancher.com/getting-started/installation-and-upgrade/install-upgrade-on-a-kubernetes-cluster#kubernetes-cluster


kubectl get secret iloto-wildcard-tls -n <source_ns> -o yaml \
  | sed "s/namespace: <source_ns>/namespace: cattle-system/" \
  | kubectl apply -f -

Pēc tam pārbaudi:
kubectl get secret iloto-wildcard-tls -n cattle-system

helm list -n cattle-system
kubectl get pods -n cattle-system -o wide
kubectl get ingress -n cattle-system
kubectl describe ingress rancher -n cattle-system
kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}{{ "\n" }}'
kubectl get secret iloto-wildcard-tls -n cattle-system
kubectl describe secret iloto-wildcard-tls -n cattle-system


kubectl logs -n cattle-system rancher-76c7856c9d-5r5ks
kubectl logs -n cattle-system -l app=rancher --all-containers=true
kubectl describe pod -n cattle-system rancher-76c7856c9d-5r5ks

nano values.yaml

hostname: rancher.iloto.lldev
bootstrapPassword: Admin123!Change
privateCA: false
ingress:
  tls:
    source: secret
    secretName: iloto-wildcard-tls

helm repo update
helm upgrade --install rancher rancher-stable/rancher \
  -n cattle-system \
  --create-namespace \
  --values values.yaml \
  --wait --timeout 900s

kubectl get crd | grep cattle

kubectl get all -n cattle-system

Dzēst:

helm uninstall rancher -n cattle-system
kubectl get all -n cattle-system
kubectl get crd | grep cattle
kubectl delete crd $(kubectl get crd | grep cattle | awk '{print $1}')
kubectl delete namespace cattle-system
kubectl create namespace cattle-system