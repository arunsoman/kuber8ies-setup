#!/bin/bash

# Generate the kubeadm join command and save it to a file
JOIN_COMMAND=$(kubeadm token create --print-join-command)
echo $JOIN_COMMAND > /tmp/kubeadm_join_command.sh
echo "Join command saved to /tmp/kubeadm_join_command.sh"
