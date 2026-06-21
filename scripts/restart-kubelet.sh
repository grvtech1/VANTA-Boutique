#!/bin/bash
set -euo pipefail
export PATH="$PATH:/home/gaurav/.local/bin"

MASTER_IP="3.111.11.116"
SSH_KEY="/home/gaurav/online-boutique/terraform/k8s-key.pem"

echo "=== Restarting Kubelet on Master Node ==="
ssh -o StrictHostKeyChecking=no -i $SSH_KEY ubuntu@$MASTER_IP 'bash -s' << 'EOF'
  echo "Restarting kubelet daemon..."
  sudo systemctl restart kubelet
  echo "✅ Kubelet restarted!"
EOF
