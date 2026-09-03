#!/bin/bash
set -euo pipefail
export PATH="$PATH:/home/gaurav/.local/bin"

MASTER_IP="3.111.11.116"
SSH_KEY="/home/gaurav/online-boutique/terraform/k8s-key.pem"

echo "=== Checking CPU Consumers on Master ==="
ssh -o StrictHostKeyChecking=no -i $SSH_KEY ubuntu@$MASTER_IP 'bash -s' << 'EOF'
  echo "--- System Uptime ---"
  uptime
  
  echo ""
  echo "--- Top 15 CPU Consumers ---"
  sudo ps -eo pid,ppid,%cpu,%mem,user,cmd --sort=-%cpu | head -n 20
EOF
