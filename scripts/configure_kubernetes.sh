#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail
set -x

KUBERNETES_VERSION=${PACKER_KUBERNETES_VERSION:-1.15.6-0}

cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

yum install -y kubelet-${KUBERNETES_VERSION} kubeadm-${KUBERNETES_VERSION} kubectl-${KUBERNETES_VERSION} yum-plugin-versionlock --disableexcludes=kubernetes
yum versionlock kubelet kubectl kubeadm
systemctl enable kubelet

mkdir -p /etc/systemd/system/kubelet.service.d
cat <<EOF > /etc/systemd/system/kubelet.service.d/11-cgroups.conf
[Service]
CPUAccounting=true
MemoryAccounting=true
EOF

cat <<EOF > /etc/sysconfig/kubelet
KUBELET_EXTRA_ARGS=--cgroup-driver=systemd --feature-gates=CSIDriverRegistry=false,CSIBlockVolume=false,CSIMigration=false
EOF

cat <<EOF > /etc/modules-load.d/k8s.conf
# load bridge netfilter
br_netfilter
EOF

cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

systemctl start docker
kubeadm config images pull

# setup CNI
mkdir -p /etc/cni/net.d
cat > /etc/cni/net.d/10-bridge.conflist <<EOF
{
  "name": "k8s-pod-network",
  "cniVersion": "0.3.0",
  "plugins": [
    {
      "name": "mynet",
      "type": "bridge",
      "bridge": "cni0",
      "isGateway": true,
      "ipMasq": true,
      "ipam": {
        "type": "host-local",
        "subnet": "10.22.0.0/16",
        "routes": [
          {
            "dst": "0.0.0.0/0"
          }
        ]
      }
    },
    {
      "type": "portmap",
      "capabilities": {
        "portMappings": true
      },
      "snat": true
    }
  ]
}
EOF


# fix selinux permissions
semanage fcontext -a -t container_file_t /var/lib/etcd
mkdir -p /var/lib/etcd
restorecon -r /var /etc

systemctl daemon-reload
systemctl start kubelet.service

kubeadm init phase certs all
restorecon -r /etc/kubernetes
kubeadm init

export KUBECONFIG=/etc/kubernetes/admin.conf

while true; do
    kubectl get pods -n kube-system -l k8s-app=kube-dns || true
    sleep 5
done

sleep 24h
