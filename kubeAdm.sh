#!/bin/bash

# Update package index and install dependencies
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# Create directory for apt keyrings if it doesn't exist
if [ ! -d /etc/apt/keyrings ]; then
  sudo mkdir -p -m 755 /etc/apt/keyrings
fi

# Download the public signing key for the Kubernetes package repositories
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add the Kubernetes apt repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Update package index again and install kubelet, kubeadm, and kubectl
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl

# Prevent kubelet, kubeadm, and kubectl from being updated automatically
sudo apt-mark hold kubelet kubeadm kubectl

# Enable and start the kubelet service
sudo systemctl enable --now kubelet

# Disable swap
sudo swapoff -a

# Make swapoff permanent by commenting out swap entries in /etc/fstab
sudo sed -i.bak '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Verify that swap is disabled
if [ $(swapon --show | wc -l) -eq 0 ]; then
  echo "Swap is disabled."
else
  echo "Swap is still enabled. Please check your configuration."
fi

# Verify unique MAC address
MAC_ADDRESS=$(ip link | grep link/ether | awk '{print $2}')
echo "MAC Address: $MAC_ADDRESS"

# Verify unique product_uuid
PRODUCT_UUID=$(sudo cat /sys/class/dmi/id/product_uuid)
echo "Product UUID: $PRODUCT_UUID"

# Check network adapters
ip addr show

# Check required ports (example: 6443)
REQUIRED_PORTS=(6443 2379 2380 10250 10251 10252)
for port in "${REQUIRED_PORTS[@]}"; do
  if nc -zv 127.0.0.1 $port 2>&1 | grep -q succeeded; then
    echo "Port $port is open"
  else
    echo "Port $port is not open"
  fi
done

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
sudo systemctl enable --now cri-docker.socket

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

# Verify Docker and cri-dockerd status
DOCKER_STATUS=$(sudo systemctl is-active docker)
CRIDOCKER_STATUS=$(sudo systemctl is-active cri-docker.service)

echo "Kubernetes components have been installed successfully."
echo "Docker status: $DOCKER_STATUS"
echo "cri-dockerd status: $CRIDOCKER_STATUS"

# Instructions for next steps
echo "Next steps:"
echo "1. Use kubeadm to create a Kubernetes cluster:"
echo "   sudo kubeadm init --pod-network-cidr=<your-pod-network-cidr>"
echo "2. Follow the instructions output by kubeadm init to set up your cluster."
echo "3. Apply a network plugin to your cluster, such as Calico or Weave."
