#!/bin/bash
set -e

echo "=== Configuring 2GB Swap Memory ==="

if [ ! -f /swapfile ]; then
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  echo "✅ Swap file created and enabled!"
else
  echo "ℹ️ Swap file already exists!"
fi

echo "=== Updating Kubelet Configuration for Swap ==="
if [ -f /var/lib/kubelet/config.yaml ]; then
  if grep -q "failSwapOn" /var/lib/kubelet/config.yaml; then
    sudo sed -i 's/failSwapOn: true/failSwapOn: false/g' /var/lib/kubelet/config.yaml
  else
    echo "failSwapOn: false" | sudo tee -a /var/lib/kubelet/config.yaml
  fi
  sudo systemctl restart kubelet
  echo "✅ Kubelet configuration updated and restarted!"
else
  echo "⚠️ /var/lib/kubelet/config.yaml not found!"
fi

free -h
