#!/usr/bin/env bash
# Install the ingress-nginx controller.
#   --provider kind       : official kind manifest (hostPort 80/443 on the ingress-ready node)
#   --provider baremetal  : NodePort manifest for kubeadm/EC2 clusters (30080/30443 by default)
#   --provider helm       : Helm chart with monitoring/ingress-nginx-values.yml (metrics + ServiceMonitor)
set -euo pipefail
provider="${2:-kind}"; [ "${1:-}" = "--provider" ] || provider="${1:-kind}"
version="controller-v1.12.1"

case "$provider" in
  kind)
    kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${version}/deploy/static/provider/kind/deploy.yaml" ;;
  baremetal)
    kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${version}/deploy/static/provider/baremetal/deploy.yaml" ;;
  helm)
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null
    helm repo update >/dev/null
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
      -n ingress-nginx --create-namespace -f monitoring/ingress-nginx-values.yml ;;
  *) echo "unknown provider: $provider" >&2; exit 1 ;;
esac

echo "waiting for the controller to be Ready..."
kubectl wait -n ingress-nginx --for=condition=ready pod \
  -l app.kubernetes.io/component=controller --timeout=180s
echo "ingress-nginx ready. Next: kubectl apply -k kustomize/overlays/kind-ingress  (add '127.0.0.1 vanta.local' to /etc/hosts)"
