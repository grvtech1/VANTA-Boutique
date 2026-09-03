#!/bin/bash
set -euo pipefail
export PATH="$PATH:/home/gaurav/.local/bin"

IP="13.206.95.146"
SSH_KEY="/home/gaurav/online-boutique/terraform/k8s-key.pem"

echo "=== Checking Kubelet on Worker 1 ($IP) ==="
ssh -o StrictHostKeyChecking=no -i $SSH_KEY ubuntu@$IP 'bash -s' << 'EOF'
  echo "Is Kubelet running?"
  sudo systemctl is-active kubelet || echo "Kubelet is NOT running!"
  
  echo ""
  echo "Kubelet status:"
  sudo systemctl status kubelet --no-pager | head -n 20
EOF
