#!/bin/bash
set -euo pipefail
export PATH="$PATH:/home/gaurav/.local/bin"

MASTER_IP="3.111.11.116"
SSH_KEY="/home/gaurav/online-boutique/terraform/k8s-key.pem"

echo "=== Running Master Node Diagnostics ==="
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

  echo ""
  echo "--- CoreDNS Pod Logs ---"
  # Find logs of coredns pods
  COREDNS_POD=$(sudo crictl pods --name coredns -q | head -n 1)
  if [ -n "$COREDNS_POD" ]; then
    echo "CoreDNS Pod ID: $COREDNS_POD"
    sudo crictl ps -p $COREDNS_POD
    COREDNS_CONTAINER=$(sudo crictl ps -p $COREDNS_POD -q | head -n 1)
    if [ -n "$COREDNS_CONTAINER" ]; then
      echo "CoreDNS Container ID: $COREDNS_CONTAINER"
      sudo crictl logs $COREDNS_CONTAINER | tail -n 25
    fi
  else
    echo "No CoreDNS pods found via crictl!"
  fi
EOF
