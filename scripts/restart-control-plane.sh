#!/bin/bash
set -euo pipefail
export PATH="$PATH:/home/gaurav/.local/bin"

MASTER_IP="3.111.11.116"
SSH_KEY="/home/gaurav/online-boutique/terraform/k8s-key.pem"

echo "=== Restarting Master Control Plane Components ==="
ssh -o StrictHostKeyChecking=no -i $SSH_KEY ubuntu@$MASTER_IP 'bash -s' << 'EOF'
  echo "Moving manifests out of /etc/kubernetes/manifests..."
  sudo mkdir -p /tmp/k8s-manifests-temp/
  sudo mv /etc/kubernetes/manifests/*.yaml /tmp/k8s-manifests-temp/
  
  echo "Waiting 15 seconds for containerd to stop the containers..."
  sleep 15
  
  echo "Moving manifests back to /etc/kubernetes/manifests..."
  sudo mv /tmp/k8s-manifests-temp/*.yaml /etc/kubernetes/manifests/
  sudo rm -rf /tmp/k8s-manifests-temp/
  
  echo "✅ Control plane components restarted successfully!"
EOF
