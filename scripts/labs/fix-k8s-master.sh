#!/bin/bash
# =============================================================================
# Fix: Reset and Reinitialize K8s Master with correct IP settings
# =============================================================================
export PATH=/home/gaurav/.local/bin:/usr/bin:/bin:$PATH

MASTER_PUBLIC_IP="15.206.68.141"
MASTER_PRIVATE_IP="10.0.1.10"
WORKER1_IP="13.207.61.122"
WORKER2_IP="13.127.4.237"
KEY="/home/gaurav/online-boutique/terraform/k8s-key.pem"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=30 -i $KEY"

echo "╔══════════════════════════════════════════════════╗"
echo "║   FIXING K8s MASTER — Reset + Reinit            ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

echo "=== STEP 1: Check etcd crash reason ==="
ssh $SSH_OPTS ubuntu@$MASTER_PUBLIC_IP "
  echo '--- etcd container logs ---'
  ETCD_ID=\$(sudo crictl ps -a --name etcd 2>/dev/null | awk 'NR==2{print \$1}')
  if [ -n \"\$ETCD_ID\" ]; then
    sudo crictl logs \$ETCD_ID 2>&1 | tail -20
  else
    echo 'etcd container not found'
  fi
" 2>&1
echo ""

echo "=== STEP 2: Reset kubeadm on master ==="
ssh $SSH_OPTS ubuntu@$MASTER_PUBLIC_IP "
  echo 'Resetting kubeadm...'
  sudo kubeadm reset -f 2>&1
  sudo rm -rf /etc/kubernetes/ /var/lib/etcd/ /var/lib/kubelet/ /home/ubuntu/.kube/
  echo 'Reset complete!'
" 2>&1
echo ""

echo "=== STEP 3: Reinitialize with PRIVATE IP (correct approach) ==="
ssh $SSH_OPTS ubuntu@$MASTER_PUBLIC_IP "
  echo 'Running kubeadm init with private IP + public IP as SAN...'
  sudo kubeadm init \
    --pod-network-cidr=10.244.0.0/16 \
    --apiserver-advertise-address=$MASTER_PRIVATE_IP \
    --apiserver-cert-extra-sans=$MASTER_PUBLIC_IP \
    --node-name=k8s-master 2>&1
" 2>&1
echo ""

echo "=== STEP 4: Configure kubectl ==="
ssh $SSH_OPTS ubuntu@$MASTER_PUBLIC_IP "
  mkdir -p \$HOME/.kube
  sudo cp /etc/kubernetes/admin.conf \$HOME/.kube/config
  sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config
  echo 'kubectl configured!'
" 2>&1
echo ""

echo "=== STEP 5: Install Flannel CNI ==="
ssh $SSH_OPTS ubuntu@$MASTER_PUBLIC_IP "
  kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
  echo 'Flannel installed!'
" 2>&1
echo ""

echo "=== STEP 6: Wait for master to be Ready ==="
ssh $SSH_OPTS ubuntu@$MASTER_PUBLIC_IP "
  for i in \$(seq 1 18); do
    STATUS=\$(kubectl get node k8s-master --no-headers 2>/dev/null | awk '{print \$2}')
    echo \"  Attempt \$i/18: Master status = \$STATUS\"
    if [ \"\$STATUS\" = 'Ready' ]; then
      echo 'Master is READY!'
      break
    fi
    sleep 10
  done
  kubectl get nodes -o wide
" 2>&1
echo ""

echo "=== STEP 7: Get join command ==="
JOIN_CMD=$(ssh $SSH_OPTS ubuntu@$MASTER_PUBLIC_IP "sudo kubeadm token create --print-join-command 2>/dev/null")
echo "  Join: $JOIN_CMD"
echo ""

echo "=== STEP 8: Join Worker-1 ==="
ssh $SSH_OPTS ubuntu@$WORKER1_IP "
  sudo kubeadm reset -f 2>/dev/null
  sudo $JOIN_CMD 2>&1
" 2>&1
echo ""

echo "=== STEP 9: Join Worker-2 ==="
ssh $SSH_OPTS ubuntu@$WORKER2_IP "
  sudo kubeadm reset -f 2>/dev/null
  sudo $JOIN_CMD 2>&1
" 2>&1
echo ""

echo "=== STEP 10: Final cluster status ==="
sleep 20
ssh $SSH_OPTS ubuntu@$MASTER_PUBLIC_IP "
  kubectl get nodes -o wide
" 2>&1
echo ""

echo "=== STEP 11: Copy kubeconfig locally ==="
scp $SSH_OPTS ubuntu@$MASTER_PUBLIC_IP:/home/ubuntu/.kube/config /home/gaurav/online-boutique/kubeconfig-aws
# Replace private IP with public IP so we can connect from laptop
sed -i "s|server: https://$MASTER_PRIVATE_IP:6443|server: https://$MASTER_PUBLIC_IP:6443|g" /home/gaurav/online-boutique/kubeconfig-aws
echo "Kubeconfig saved! Test with:"
echo "  export KUBECONFIG=/home/gaurav/online-boutique/kubeconfig-aws"
echo "  kubectl get nodes"
