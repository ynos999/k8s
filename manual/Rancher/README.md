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

6. kubectl -n cattle-system rollout status deploy/rancher
kubectl -n cattle-system get deploy rancher


https://ranchermanager.docs.rancher.com/getting-started/installation-and-upgrade/install-upgrade-on-a-kubernetes-cluster#kubernetes-cluster