#!/bin/bash
cat > /usr/bin/k3s-startup.sh <<'END'
#!/bin/bash
[ENVIRONMENT_VARIABLES]
# you should add a #bin/bash at the beginning of the script. we do that in terraform
if [ "$VAR_NODE_ROLE" == "master" ] 
then
# instal dependencies
apt-get update
apt-get install git -y
wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_arm64 -O /usr/bin/yq
chmod +x /usr/bin/yq
# create needed folders
mkdir -p /etc/rancher/k3s
mkdir -p /var/lib/rancher/k3s/server/manifests
# modify kubelet configuration to lower image caching
cat > /etc/rancher/k3s/kubelet.config <<EOF
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
imageGCHighThresholdPercent: 60
imageGCLowThresholdPercent: 50
EOF
# setup k3s configuration file
cat > /etc/rancher/k3s/config.yaml <<EOF
write-kubeconfig-mode: "0644"
# this should be added on spot VMs
# node-label: 
#   spot=true
disable:
  - traefik
disable-helm-controller: true
#disable-cloud-controller: true
kubelet-arg: "config=/etc/rancher/k3s/kubelet.config"
EOF
# a storage class to use the 2nd disk of the machine
cat > /var/lib/rancher/k3s/server/manifests/storage-class.yaml <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path-ssd
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rancher.io/local-path
parameters:
  nodePath: /data/ssd
  pathPattern: "{{ .PVC.Namespace }}/{{ .PVC.Name }}"
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
EOF
# installs argocd
cat >/var/lib/rancher/k3s/server/manifests/argocd-namespace.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: argocd
spec:
  finalizers:
    - kubernetes
EOF
git clone https://github.com/argoproj/argo-cd.git --branch v2.11.2
cp ./argo-cd/manifests/install.yaml /var/lib/rancher/k3s/server/manifests/argo-cd.yaml
rm -rf ./argo-cd
yq ea '.metadata.namespace = "argocd"' -i /var/lib/rancher/k3s/server/manifests/argo-cd.yaml
cat > /var/lib/rancher/k3s/server/manifests/master-app.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: master-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    namespace: argocd
    server: https://kubernetes.default.svc
  project: default
  source:
    repoURL: https://github.com/Societatea-Hermes/hermes-on-kubernetes.git
    targetRevision: main
    path: helmcharts/apps
    helm:
      valueFiles:
        - values.yaml
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
fi

if [ "$VAR_NODE_ROLE" == "master" ] || [ "$VAR_NODE_ROLE" == "normal" ] 
then
if ! [ -e "/data/ssd" ]
then
# -- this formats and mounts the secondary disk to /data/ssd
mkdir -p /data/ssd
echo ',,linux' | sfdisk /dev/sdb
mkfs.ext4 /dev/sdb1
echo '/dev/sdb1 /data/ssd ext4 defaults 0 0' >> /etc/fstab
systemctl daemon-reload
mount -a
# --
fi
fi

if [ "$VAR_NODE_ROLE" == "master" ] 
then
# this installs k3s; the token is generated by the terraform script
curl -sfL https://get.k3s.io | K3S_TOKEN=$VAR_K3S_TOKEN sh -s
else
curl -sfL https://get.k3s.io | K3S_URL=https://VAR_MASTER_NAME K3S_TOKEN=$VAR_K3S_TOKEN sh -s
fi



# install debugging tools
curl -sS https://webinstall.dev/k9s | bash
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
source ~/.config/envman/PATH.env
END

chmod +x /usr/bin/k3s-startup.sh

cat > /lib/systemd/system/k3s-startup.service <<'END'
[Unit]
Description=K3s startup script

[Service]
ExecStart=/usr/bin/k3s-startup.sh

[Install]
WantedBy=multi-user.target
END

systemctl daemon-reload && systemctl enable k3s-startup && systemctl start k3s-startup