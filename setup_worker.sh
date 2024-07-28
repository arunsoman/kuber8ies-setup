#!/bin/bash

# Variables
MASTER_NODE=<master-node-ip>  # Replace with the actual IP address of the master node
JOIN_COMMAND_FILE=/tmp/kubeadm_join_command.sh

# Function to retrieve the join command from the master node
get_join_command() {
  scp root@$MASTER_NODE:$JOIN_COMMAND_FILE .
  if [ -f ./kubeadm_join_command.sh ]; then
    echo "Join command retrieved successfully."
    source ./kubeadm_join_command.sh
  else
    echo "Failed to retrieve join command."
    exit 1
  fi
}

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

# Retrieve and run the join command
get_join_command

echo "Worker node setup is complete and has joined the Kubernetes cluster."
