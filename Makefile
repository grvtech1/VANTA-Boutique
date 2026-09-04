# VANTA Boutique — developer entry points (Linux / macOS / WSL; on Git Bash run the scripts directly)
SHELL := /usr/bin/env bash
NS ?= boutique
SHA ?=

.PHONY: help kind-up kind-down deploy ingress render test argocd monitoring promote health chaos failover destroy

help:
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n",$$1,$$2}'

kind-up: ## create the local kind cluster (NodePort 30080→8888, 80/443 for ingress)
	kind create cluster --config kind-local.yaml

kind-down: ## delete the local kind cluster
	kind delete cluster --name boutique

deploy: ## apply the dev overlay and wait for pods
	kubectl apply -k kustomize/overlays/dev
	kubectl wait -n $(NS) --for=condition=ready pod --all --timeout=300s
	@echo "→ http://localhost:8888"

ingress: ## install ingress-nginx (kind) and apply the kind-ingress overlay
	scripts/install-ingress-nginx.sh --provider kind
	kubectl apply -k kustomize/overlays/kind-ingress
	@echo "→ add '127.0.0.1 vanta.local' to /etc/hosts, then http://vanta.local"

render: ## render every overlay/test + lint the Helm chart (what CI does)
	@for d in kustomize kustomize/overlays/* kustomize/tests/*/; do echo "== $$d"; kubectl kustomize $$d >/dev/null; done
	helm lint helm-chart && helm template vanta helm-chart >/dev/null && echo "helm OK"

test: ## Go vet + unit tests for every Go service; reviewsservice with the race detector (needs Go)
	@for s in checkoutservice frontend productcatalogservice shippingservice; do echo "== $$s"; (cd src/$$s && go vet -copylocks=false ./... && go test ./...) || exit 1; done
	cd src/reviewsservice && go vet ./... && go test -race ./...

argocd: ## install ArgoCD and register the app-of-apps root
	scripts/setup-argocd.sh

monitoring: ## install kube-prometheus-stack + Loki + dashboard (create secrets first, see monitoring/README.md)
	helm upgrade --install kube-prom prometheus-community/kube-prometheus-stack -n monitoring --create-namespace -f monitoring/prometheus-values.yml
	helm upgrade --install loki grafana/loki-stack -n monitoring -f monitoring/loki-values.yml
	kubectl apply -f monitoring/grafana/vanta-overview-dashboard.yaml

promote: ## pin prod to SHA=<git-sha> (commits; then git push + manual ArgoCD sync)
	@test -n "$(SHA)" || { echo "usage: make promote SHA=<git-sha>"; exit 1; }
	scripts/promote.sh $(SHA)

health: ## cluster + app health summary
	NAMESPACE=$(NS) scripts/health-check.sh

chaos: ## kill pods, verify self-healing (staging!)
	NAMESPACE=$(NS) scripts/chaos-engineering.sh

failover: ## drain a worker, watch rescheduling, verify the store (staging!)
	NAMESPACE=$(NS) scripts/failover-lab.sh

destroy: ## tear down AWS (stop the bill)
	cd terraform && terraform destroy
