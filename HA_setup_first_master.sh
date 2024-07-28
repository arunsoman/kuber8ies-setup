#!/bin/bash

# Variables
LOAD_BALANCER_DNS=<load-balancer-dns>
LOAD_BALANCER_PORT=<load-balancer-port>
KUBE_VERSION="v1.30.0"

# Update package index and install dependencies
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# Create directory for apt keyrings if it doesn't exist
if [ ! -d /etc/apt/keyrings ]; then
  sudo mkdir -p -m 755 /etc/apt/keyrings
fi

# Download the public signing key for the Kubernetes package repositories
curl -fsSL https://pkgs.k8s.io/core:/stable:/${KUBE_VERSION}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add the Kubernetes apt repository
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBE_VERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Update package index again and install kubelet, kubeadm, and kubectl
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl

# Prevent kubelet, kubeadm, and kubectl from being updated automatically
sudo apt-mark hold kubelet kubeadm kubectl

# Enable and start the kubelet service
sudo systemctl enable --now kubelet

# Disable swap
sudo swapoff -a
sudo sed -i.bak '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Verify that swap is disabled
if [ $(swapon --show | wc -l) -eq 0 ]; then
  echo "Swap is disabled."
else
  echo "Swap is still enabled. Please check your configuration."
fi

# Install Docker
sudo apt-get update
sudo apt-get install -y docker.io

# Enable and start Docker service
sudo systemctl enable docker
sudo systemctl start docker

# Install cri-dockerd
VERSION=$(curl -s https://api.github.com/repos/Mirantis/cri-dockerd/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
wget https://github.com/Mirantis/cri-dockerd/releases/download/$VERSION/cri-dockerd-$VERSION.amd64.tgz
tar xvf cri-dockerd-$VERSION.amd64.tgz
sudo mv cri-dockerd/cri-dockerd /usr/local/bin/

# Create systemd service for cri-dockerd
cat <<EOF | sudo tee /etc/systemd/system/cri-docker.service
[Unit]
Description=CRI Interface for Docker Application Container Engine
Documentation=https://docs.mirantis.com
After=docker.service
Wants=docker.service

[Service]
Type=exec
ExecStart=/usr/local/bin/cri-dockerd --container-runtime-endpoint fd://
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF | sudo tee /etc/systemd/system/cri-docker.socket
[Unit]
Description=CRI Dockerd Socket for the Docker Engine
PartOf=cri-docker.service

[Socket]
ListenStream=/run/cri-dockerd.sock
SocketMode=0660
SocketUser=root
SocketGroup=docker

[Install]
WantedBy=sockets.target
EOF

# Enable and start cri-dockerd
sudo systemctl daemon-reload
sudo systemctl enable cri-docker.service
sudo systemctl enable --now cri-dockerd.socket

# Configure Docker to use systemd as the cgroup driver
sudo mkdir -p /etc/docker
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

sudo systemctl restart docker

# Configure kubelet to use systemd as the cgroup driver
cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS=--cgroup-driver=systemd
EOF

sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Create the kubeadm configuration file
cat <<EOF | sudo tee kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: "${KUBE_VERSION}"
controlPlaneEndpoint: "${LOAD_BALANCER_DNS}:${LOAD_BALANCER_PORT}"
networking:
  podSubnet: "10.244.0.0/16"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: KubeletConfiguration
cgroupDriver: "systemd"
EOF

# Initialize Kubernetes control-plane node using the configuration file
sudo kubeadm init --config kubeadm-config.yaml --upload-certs

# Set up kubeconfig for the regular user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install a Pod network add-on (using Flannel as an example)
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

# Remove taint from master to allow scheduling pods on master node (optional, for single-node cluster)
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

# Verify Docker, cri-dockerd, and kubelet status
DOCKER_STATUS=$(sudo systemctl is-active docker)
CRIDOCKER_STATUS=$(sudo systemctl is-active cri-docker.service)
KUBELET_STATUS=$(sudo systemctl is-active kubelet)

echo "Kubernetes components have been installed successfully."
echo "Docker status: $DOCKER_STATUS"
echo "cri-dockerd status: $CRIDOCKER_STATUS"
echo "kubelet status: $KUBELET_STATUS"

# Generate join command for control-plane and worker nodes
sudo kubeadm token create --print-join-command > /tmp/kubeadm_join_command.sh
echo "Join command saved to /tmp/kubeadm_join_command.sh"

echo "Next steps:"
echo "1. Use the join command saved in /tmp/kubeadm_join_command.sh to join additional control-plane nodes and worker nodes."
