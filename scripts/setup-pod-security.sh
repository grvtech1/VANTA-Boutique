#!/bin/bash
# =============================================================================
# Pod Security Standards — Namespace-Level Admission Control
# =============================================================================
# WHY: Individual pods have SecurityContext, but there is no CLUSTER-LEVEL
#      enforcement. A misconfigured manifest could deploy a privileged container.
#
# LEVELS:
#   enforce=baseline  -> BLOCKS privileged containers, hostNetwork, hostPID
#   warn=restricted   -> WARNS on non-compliant pods (readOnlyRootFS, caps)
#   audit=restricted  -> LOGS violations for security audit trail
# =============================================================================
set -euo pipefail

KUBECONFIG="/home/gaurav/online-boutique/kubeconfig-aws"
export KUBECONFIG

echo "=== Applying Pod Security Standards ==="

kubectl label namespace boutique \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/enforce-version=latest \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/warn-version=latest \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/audit-version=latest \
  --overwrite

echo "Pod Security Standards applied to boutique namespace"

echo ""
echo "=== Verification ==="
kubectl get namespace boutique -o jsonpath='{.metadata.labels}' | python3 -m json.tool
