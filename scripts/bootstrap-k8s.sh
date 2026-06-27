#!/bin/bash
# =============================================================================
# K8s Cluster Bootstrap via SSH — Ansible-style but no Ansible needed
# =============================================================================
# Run this from WSL terminal: bash ~/online-boutique/scripts/bootstrap-k8s.sh
# =============================================================================

set -e
export PATH=/home/gaurav/.local/bin:/usr/bin:/bin:$PATH

MASTER_IP="15.206.221.59"
MASTER_PRIVATE_IP="10.0.1.10"
WORKER1_IP="13.206.95.146"
WORKER2_IP="13.206.145.240"
KEY="$HOME/online-boutique/terraform/k8s-key.pem"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=30 -i $KEY"

echo "╔══════════════════════════════════════════════════╗"
echo "║   K8s CLUSTER BOOTSTRAP — 3-Node AWS Cluster    ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ─── Step 1: Wait for servers to be SSH-ready ───
echo "=== STEP 1: Waiting for servers to be SSH-ready ==="
for IP in $MASTER_IP $WORKER1_IP $WORKER2_IP; do
  echo -n "  Waiting for $IP ..."
  for i in $(seq 1 30); do
    if ssh $SSH_OPTS ubuntu@$IP "echo ok" &>/dev/null 2>&1; then
      echo " READY!"
      break
    fi
    echo -n "."
    sleep 10
  done
done
echo ""

# ─── Step 2: Wait for user_data (kubeadm install) to complete ───
echo "=== STEP 2: Waiting for kubeadm install to complete on all nodes ==="
for IP in $MASTER_IP $WORKER1_IP $WORKER2_IP; do
  echo -n "  $IP: Checking kubeadm ..."
  for i in $(seq 1 20); do
    if ssh $SSH_OPTS ubuntu@$IP "which kubeadm" &>/dev/null 2>&1; then
      echo " READY!"
      break
    fi
    echo -n "."
    sleep 15
  done
done
echo ""

# ─── Step 3: Verify node specs ───
echo "=== STEP 3: Node Specs ==="
for NAME_IP in "master:$MASTER_IP" "worker-1:$WORKER1_IP" "worker-2:$WORKER2_IP"; do
  NAME="${NAME_IP%%:*}"
  IP="${NAME_IP##*:}"
  INFO=$(ssh $SSH_OPTS ubuntu@$IP "echo CPU: \$(nproc) vCPU, RAM: \$(free -h | awk '/^Mem:/{print \$2}')" 2>/dev/null)
  echo "  $NAME ($IP): $INFO"
done
echo ""

# ─── Step 4: Initialize Master ───
echo "=== STEP 4: Running kubeadm init on master ==="
ssh $SSH_OPTS ubuntu@$MASTER_IP "
  if [ ! -f /etc/kubernetes/admin.conf ]; then
    echo 'Running kubeadm init...'
    sudo kubeadm init \
      --pod-network-cidr=192.168.0.0/16 \
      --apiserver-advertise-address=$MASTER_PRIVATE_IP \
      --apiserver-cert-extra-sans=$MASTER_IP \
      --node-name=k8s-master 2>&1
  else
    echo 'Cluster already initialized!'
  fi
"
echo ""

# ─── Step 5: Configure kubectl on master ───
echo "=== STEP 5: Configuring kubectl for ubuntu user ==="
ssh $SSH_OPTS ubuntu@$MASTER_IP "
  mkdir -p \$HOME/.kube
  sudo cp /etc/kubernetes/admin.conf \$HOME/.kube/config
  sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config
  echo 'kubectl configured!'
  kubectl get nodes
"
echo ""

# ─── Step 6: Install Calico CNI ───
echo "=== STEP 6: Installing Calico CNI (pod networking) ==="
ssh $SSH_OPTS ubuntu@$MASTER_IP "
  kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml
  echo 'Calico installed!'
"
echo ""

# ─── Step 7: Get join command ───
echo "=== STEP 7: Getting worker join command ==="
JOIN_CMD=$(ssh $SSH_OPTS ubuntu@$MASTER_IP "sudo kubeadm token create --print-join-command 2>/dev/null")
echo "  Join command: $JOIN_CMD"
echo ""

# ─── Step 8: Join workers ───
echo "=== STEP 8: Joining workers to cluster ==="
for NAME_IP in "worker-1:$WORKER1_IP" "worker-2:$WORKER2_IP"; do
  NAME="${NAME_IP%%:*}"
  IP="${NAME_IP##*:}"
  echo "  Joining $NAME ($IP)..."
  ssh $SSH_OPTS ubuntu@$IP "
    if [ ! -f /etc/kubernetes/kubelet.conf ]; then
      sudo $JOIN_CMD 2>&1
      echo '$NAME joined!'
    else
      echo '$NAME already in cluster!'
    fi
  "
done
echo ""

# ─── Step 9: Wait for nodes Ready ───
echo "=== STEP 9: Waiting for all nodes to be Ready ==="
ssh $SSH_OPTS ubuntu@$MASTER_IP "
  for i in \$(seq 1 24); do
    NOT_READY=\$(kubectl get nodes --no-headers 2>/dev/null | grep -v ' Ready' | wc -l)
    if [ \"\$NOT_READY\" = \"0\" ]; then
      echo 'All nodes are READY!'
      break
    fi
    echo 'Waiting... (\$i/24)'
    sleep 10
  done
  echo ''
  kubectl get nodes -o wide
"
echo ""

# ─── Step 10: Copy kubeconfig locally ───
echo "=== STEP 10: Copying kubeconfig to local machine ==="
scp $SSH_OPTS ubuntu@$MASTER_IP:/home/ubuntu/.kube/config ~/online-boutique/kubeconfig-aws
sed -i "s|server: https://.*:6443|server: https://$MASTER_IP:6443|g" ~/online-boutique/kubeconfig-aws
echo "Kubeconfig saved to ~/online-boutique/kubeconfig-aws"
echo ""

echo "╔══════════════════════════════════════════════════╗"
echo "║   🎉 K8s CLUSTER IS LIVE ON AWS!                ║"
echo "║                                                  ║"
echo "║   To use kubectl from WSL:                       ║"
echo "║   export KUBECONFIG=~/online-boutique/kubeconfig-aws ║"
echo "║   kubectl get nodes                              ║"
echo "╚══════════════════════════════════════════════════╝"
