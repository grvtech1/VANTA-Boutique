#!/bin/bash
set -euo pipefail
export PATH="$PATH:/home/gaurav/.local/bin"

MASTER_IP="15.206.221.59"
SSH_KEY="/home/gaurav/online-boutique/terraform/k8s-key.pem"

echo "=== Running Master Node Diagnostics ($MASTER_IP) ==="
ssh -o StrictHostKeyChecking=no -i $SSH_KEY ubuntu@$MASTER_IP 'bash -s' << 'EOF'
  echo "--- System Load & Uptime ---"
  uptime
  free -h

  echo ""
  echo "--- Kubelet Service Status ---"
  systemctl is-active kubelet || echo "Kubelet is inactive!"
  sudo systemctl status kubelet --no-pager | head -n 15

  echo ""
  echo "--- Containerd Service Status ---"
  systemctl is-active containerd || echo "Containerd is inactive!"
  sudo systemctl status containerd --no-pager | head -n 15
EOF
