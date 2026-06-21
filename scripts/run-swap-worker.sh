#!/bin/bash
set -euo pipefail

IP=$1
echo "Configuring swap on node at IP: $IP..."

scp -o StrictHostKeyChecking=no -i /home/gaurav/online-boutique/terraform/k8s-key.pem /home/gaurav/online-boutique/scripts/setup-swap.sh ubuntu@$IP:/tmp/setup-swap.sh
ssh -o StrictHostKeyChecking=no -i /home/gaurav/online-boutique/terraform/k8s-key.pem ubuntu@$IP "chmod +x /tmp/setup-swap.sh && sudo /tmp/setup-swap.sh"

echo "✅ Swap configured successfully on $IP!"
