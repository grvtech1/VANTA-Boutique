# Observability stack

Prometheus + Grafana + Alertmanager (kube-prometheus-stack), Loki for logs, ingress-nginx
metrics for the availability SLO. Secrets are created out of band — nothing sensitive in Git.

## 1. Secrets first

```sh
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin --from-literal=admin-password="$(openssl rand -base64 18)"
kubectl -n monitoring create secret generic alertmanager-slack \
  --from-literal=webhook='https://hooks.slack.com/services/XXX/YYY/ZZZ'
```

## 2. Install

```sh
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install kube-prom prometheus-community/kube-prometheus-stack \
  -n monitoring -f monitoring/prometheus-values.yml
helm upgrade --install loki grafana/loki-stack -n monitoring -f monitoring/loki-values.yml
kubectl apply -f monitoring/grafana/vanta-overview-dashboard.yaml

# ingress-nginx with metrics + ServiceMonitor (feeds the SLO rules)
scripts/install-ingress-nginx.sh --provider helm
```

## 3. Look

```sh
kubectl -n monitoring port-forward svc/kube-prom-grafana 3000:80        # http://localhost:3000
kubectl -n monitoring port-forward svc/kube-prom-kube-prometheus-prometheus 9090:9090
kubectl -n monitoring port-forward svc/kube-prom-kube-prometheus-alertmanager 9093:9093
```

Grafana → dashboard **VANTA Boutique — Overview** (ready ratio, ingress 5xx ratio, RPS,
restarts, CPU/memory per pod, HPA). Alertmanager → Slack `#vanta-alerts` (warning) and
`#vanta-alerts-critical` (critical, repeats hourly).

## Alerts

| Alert | Severity | Meaning |
| --- | --- | --- |
| `SLOErrorBudgetBurnFast` | critical | 1h **and** 5m 5xx ratio > 14.4× the 0.5% budget — page |
| `SLOErrorBudgetBurnSlow` | warning | 6h **and** 30m > 6× budget — ticket |
| `PodCrashLooping` / `PodNotReady` | warning / critical | app pods unhealthy |
| `DeploymentReplicasMismatch` | critical | desired ≠ ready for 5m |
| `HpaMaxedOut` | warning | autoscaler at max for 10m — capacity ceiling |
| `ReviewsDatabaseDown` | critical | Postgres for reviews has no ready replica |
| `NodeNotReady` / `NodeHigh*` / `NodeDiskPressure` | critical / warning | node health |

Each alert links to the matching entry in [`docs/RUNBOOKS.md`](../docs/RUNBOOKS.md).
