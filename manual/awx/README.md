https://www.linuxtechi.com/install-ansible-awx-on-kubernetes-cluster/

================================================================
1.
helm repo add awx-operator https://ansible-community.github.io/awx-operator-helm/
helm repo update
helm install ansible-awx-operator awx-operator/awx-operator -n awx --create-namespace
kubectl get pods -n awx

# Jums vajadzētu redzēt "awx-operator-controller-manager" podu ar statusu Running.
2.
nano awx-storage-class.yaml

---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage-awx # Izmantojam unikālu nosaukumu
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer


kubectl apply -f awx-storage-class.yaml
kubectl get sc

3. Uz katra servera

# Izveido AWX direktoriju
sudo mkdir -p /mnt/awx-storage
sudo chmod 777 /mnt/awx-storage

4. 
nano awx-pv.yaml

---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: postgres-pv-awx # Unikāls nosaukums
spec:
  capacity:
    storage: 10Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage-awx # Jāsakrīt ar SC
  hostPath:
    path: /mnt/awx-storage # Jāsakrīt ar direktoriju uz mezgla

kubectl apply -f awx-pv.yaml
kubectl get pv

5. 
nano ansible-awx.yaml

---
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: ansible-awx
  namespace: awx
spec:
  # Izmantojam atpakaļsaderīgu lauku (service_type ar mazo s)
  service_type: NodePort
  # Jūsu definētā krātuves klase
  postgres_storage_class: local-storage-awx
  # AWX Operatora versijai, kas ir instalēta jūsu klasterī, šis ir vienīgais atļautais lauks krātuves klasei

kubectl apply -f ansible-awx.yaml -n awx
kubectl get pods -n awx
kubectl get svc -n awx
6. 
nano awx-ingressroute.yaml

---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: awx-http-redirect-route
  namespace: awx # Svarīgi: Jābūt awx namespace!
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`awx.iloto.lldev`)
      kind: Rule
      middlewares:
        - name: redirect-to-https@kubernetescrd # Jūsu globālais Middleware
      services:
        - name: ansible-awx-service # AWX Service, ko operators izveidoja
          port: 80 # AWX Service ports
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: awx-https-secure-route
  namespace: awx # Svarīgi: Jābūt awx namespace!
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`awx.iloto.lldev`)
      kind: Rule
      services:
        - name: ansible-awx-service
          port: 80 # AWX Service ports
  tls:
    secretName: iloto-wildcard-tls # Jūsu esošais sertifikāts


kubectl apply -f awx-ingressroute.yaml -n awx

kubectl get secret ansible-awx-admin-password -o jsonpath="{.data.password}" -n awx | base64 --decode ; echo

AOFktCycia19CqYUoFs2z17WyubAo8c8

Adrese: https://awx.iloto.lldev Lietotājvārds: admin


kubectl get pods -n kube-system -o wide