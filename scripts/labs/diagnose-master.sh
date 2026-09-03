#!/bin/bash
# =============================================================================
# Diagnose and Fix K8s Master — API Server not running
# =============================================================================
export PATH=/home/gaurav/.local/bin:/usr/bin:/bin:$PATH

MASTER_IP="15.206.68.141"
KEY="/home/gaurav/online-boutique/terraform/k8s-key.pem"
SSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 -i $KEY ubuntu@$MASTER_IP"

echo "=== DIAGNOSING MASTER NODE ==="
$SSH "
  echo '--- kubelet status ---'
  sudo systemctl status kubelet --no-pager | head -20

  echo ''
  echo '--- containerd status ---'
  sudo systemctl status containerd --no-pager | head -5

  echo ''
  echo '--- K8s manifest pods (static pods) ---'
  sudo ls /etc/kubernetes/manifests/ 2>/dev/null || echo 'No manifests found!'

  echo ''
  echo '--- admin.conf exists? ---'
  ls -la /etc/kubernetes/admin.conf 2>/dev/null || echo 'admin.conf missing!'

  echo ''
  echo '--- kubelet logs (last 30 lines) ---'
  sudo journalctl -u kubelet --no-pager -n 30
"
