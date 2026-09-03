#!/usr/bin/env bash
# Node-failure drill: cordon + drain one worker, watch pods reschedule, prove the store still
# answers, then uncordon. Works on any cluster (kind, kubeadm/EC2). Run in staging, not prod.
#
#   NAMESPACE=boutique-staging scripts/failover-lab.sh [node-name]
set -euo pipefail
NS="${NAMESPACE:-boutique}"
node="${1:-}"

if [ -z "$node" ]; then
  node=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')
fi
[ -n "$node" ] || { echo "no worker node found" >&2; exit 1; }

echo "== BEFORE: pods on $node =="
kubectl get pods -n "$NS" -o wide --field-selector spec.nodeName="$node"

echo; echo "== 1. cordon + drain $node (respects PodDisruptionBudgets) =="
kubectl cordon "$node"
start=$(date +%s)
kubectl drain "$node" --ignore-daemonsets --delete-emptydir-data --timeout=180s
echo "drain took $(( $(date +%s) - start ))s"

echo; echo "== 2. rescheduling — waiting for all pods Ready =="
kubectl wait -n "$NS" --for=condition=ready pod --all --timeout=240s
kubectl get pods -n "$NS" -o wide

echo; echo "== 3. is the store still serving? =="
kubectl port-forward -n "$NS" svc/frontend 18080:80 >/dev/null 2>&1 &
pf=$!; sleep 3
code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:18080/ || true)
kill $pf 2>/dev/null || true
echo "frontend HTTP $code"

echo; echo "== 4. uncordon $node =="
kubectl uncordon "$node"
echo
echo "Drill complete. Questions to answer in the runbook:"
echo "  - Did any PDB block the drain? (kubectl get pdb -n $NS)"
echo "  - Which single-replica pods went briefly unavailable?"
echo "  - Did the frontend HPA scale during the drain?"
