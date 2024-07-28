#!/bin/bash

# Variables
MASTER_NODE=<master-node-ip>  # Replace with the actual IP address of the first master node
CONTROL_PLANE_NODES=("<control-plane-node-1-ip>" "<control-plane-node-2-ip>")  # Replace with actual IPs of control plane nodes
WORKER_NODES=("<worker-node-1-ip>" "<worker-node-2-ip>")  # Replace with actual IPs of worker nodes
ALL_NODES=("${CONTROL_PLANE_NODES[@]}" "${WORKER_NODES[@]}")

# Generate SSH key pair if not already generated
if [ ! -f ~/.ssh/id_rsa ]; then
  ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa
fi

# Function to distribute SSH public key to a node
distribute_ssh_key() {
  local node_ip=$1
  ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa.pub $USER@$node_ip
}

# Distribute SSH key to all nodes
for node in "${ALL_NODES[@]}"; do
  distribute_ssh_key $node
done

# Verify SSH access
for node in "${ALL_NODES[@]}"; do
  ssh -o StrictHostKeyChecking=no $USER@$node "echo SSH access to $node successful"
done

echo "Passwordless SSH setup is complete for all nodes."
