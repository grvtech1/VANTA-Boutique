#!/bin/bash
set -euo pipefail
export PATH="$PATH:/home/gaurav/.local/bin"
export KUBECONFIG=/home/gaurav/online-boutique/kubeconfig-aws

# 1. Find the master node name dynamically
MASTER_NODE=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}')
echo "Found Master Node: $MASTER_NODE"

# 2. Patch each deployment to use the correct master node name in nodeSelector
for deploy in argocd-server argocd-repo-server argocd-redis argocd-dex-server argocd-notifications-controller argocd-applicationset-controller; do
  echo "Patching deployment $deploy..."
  kubectl patch deployment "$deploy" -n argocd \
    --type='json' \
    -p="[{\"op\":\"replace\",\"path\":\"/spec/template/spec/nodeSelector/kubernetes.io~1hostname\",\"value\":\"$MASTER_NODE\"}]" || echo "Failed to patch $deploy"
done

# 3. Patch statefulset
echo "Patching statefulset argocd-application-controller..."
kubectl patch statefulset argocd-application-controller -n argocd \
  --type='json' \
  -p="[{\"op\":\"replace\",\"path\":\"/spec/template/spec/nodeSelector/kubernetes.io~1hostname\",\"value\":\"$MASTER_NODE\"}]" || echo "Failed to patch statefulset"

echo "✅ All ArgoCD components patched to use $MASTER_NODE"
