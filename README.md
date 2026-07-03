<h1 align="center">🛍️ VANTA Boutique</h1>

<p align="center">
  <strong>Curated for the Bold</strong> — a premium, dark-themed cloud-native e-commerce store
  built on a polyglot microservices architecture.
</p>

<p align="center">
  <a href="#-architecture"><img alt="Microservices" src="https://img.shields.io/badge/architecture-microservices-7c5cff"></a>
  <a href="#-tech-stack"><img alt="gRPC" src="https://img.shields.io/badge/RPC-gRPC-244c5a"></a>
  <a href="/kustomize"><img alt="Kubernetes" src="https://img.shields.io/badge/orchestration-Kubernetes%20(kubeadm)-326ce5"></a>
  <a href="/terraform"><img alt="Terraform" src="https://img.shields.io/badge/IaC-Terraform-7b42bc"></a>
  <a href="/argocd"><img alt="ArgoCD" src="https://img.shields.io/badge/GitOps-ArgoCD-ef7b4d"></a>
  <a href="/monitoring"><img alt="Observability" src="https://img.shields.io/badge/observability-Prometheus%20%2B%20Grafana-e6522c"></a>
  <a href="/.github/workflows"><img alt="CI/CD" src="https://img.shields.io/badge/CI%2FCD-Actions%20%2B%20Jenkins-2088ff"></a>
  <img alt="License" src="https://img.shields.io/badge/license-Apache--2.0-green">
</p>

---

## Overview

**VANTA Boutique** is a web-based storefront where shoppers browse a curated catalog,
read and write **product reviews**, manage a cart, and check out — all served by **12
independent microservices** written in **six languages** (Go, C#, Node.js, Python, Java)
that communicate over **gRPC**.

It began as a fork of Google's *Online Boutique* and was rebuilt into a production-leaning
DevOps showcase: a **brand-new Reviews microservice** taken end-to-end (proto → service →
container → Kubernetes → CI/CD), a restyled **VANTA** storefront, and an automated delivery
pipeline that builds, tests, scans, and ships every service.

### What this fork adds on top of the upstream demo

- 🆕 **Reviews microservice** (`reviewsservice`, Go/gRPC) — `GetReviews` + `AddReview`, with a
  pluggable **`Store` interface**: a bounded, concurrency-safe **in-memory** store by default,
  or a durable, shared **PostgreSQL** store (pgx/v5) for multi-replica deployments.
- 🎨 **VANTA storefront** — a curated **25-product catalog across 6 categories** with a live
  **category filter, search, and sort**, a **localStorage wishlist**, "New" badges, and a
  unified set of **premium SVG product tiles** (per-category gradient art, zero external image
  deps). Reviews on the product page (★ ratings, write-a-review form), rendered with
  accessibility (`aria-label`, semantic `<article>`/`<time>`) and **schema.org JSON-LD**
  (`AggregateRating`/`Review`) for rich search snippets.
- 🛡️ **Production hardening** — graceful shutdown (`SIGTERM` → drain), gRPC message-size &
  keepalive limits, input validation/length caps, DB-connectivity-driven **gRPC health**, a
  `nonroot` distroless image, and a dedicated **NetworkPolicy**.
- ⚙️ **CI/CD** — GitHub Actions: `go vet`, **race-detector tests** with a Postgres service
  container, multi-service Docker builds, Trivy vulnerability scan, and an honest deploy gate.
  The same pipeline is also provided as a **Jenkins declarative pipeline** ([`Jenkinsfile`](/Jenkinsfile)).
- ☸️ **Self-managed platform on AWS** — the whole stack is reproducible from code:
  **Terraform** provisions a VPC + 3 EC2 nodes, **Ansible** + `kubeadm` form the cluster,
  **ArgoCD** delivers via pull-based GitOps, and **Prometheus/Grafana/Loki** provide
  observability. See **[Platform & DevOps](#-platform--devops)** below.

## Screenshots

| Landing — *Curated for the Bold* | Catalog — *25 products · 6 categories · filter, search & sort* |
| --- | --- |
| ![VANTA landing hero](/docs/screenshots/hero-landing.png) | ![VANTA product catalog](/docs/screenshots/product-catalog.png) |

| Product detail | Cart & checkout | Order confirmed |
| --- | --- | --- |
| ![VANTA product detail](/docs/screenshots/product-detail.png) | ![VANTA cart and checkout](/docs/screenshots/cart-checkout.png) | ![VANTA order confirmation](/docs/screenshots/order-confirmed.png) |

## 🏗 Architecture

VANTA Boutique is a **gRPC mesh**: the Go **frontend** is the single HTTP edge, and every
other service is an internal gRPC backend. Services are **stateless** and horizontally
scalable; state lives in two backing stores — **Redis** (cart) and an optional
**PostgreSQL** (reviews). The **checkout** service acts as the orchestrator, fanning out to
cart, catalog, currency, shipping, payment, and email to complete an order. Contracts are
defined once as **Protocol Buffers** in [`./protos`](/protos) and code-generated per language.

```mermaid
flowchart TD
    user([👤 Shopper]):::ext
    lg[loadgenerator · Py/Locust]:::ext

    user -->|HTTP| fe
    lg -. HTTP load .-> fe

    fe["frontend · Go<br/>(HTTP edge)"]:::edge

    %% frontend fan-out (gRPC)
    fe -->|gRPC| pc[productcatalog · Go]
    fe -->|gRPC| cur[currency · Node.js]
    fe -->|gRPC| cart[cart · C#]
    fe -->|gRPC| rec[recommendation · Py]
    fe -->|gRPC| ship[shipping · Go]
    fe -->|gRPC| ad[ad · Java]
    fe -->|gRPC| rev["reviews · Go ⭐"]:::new
    fe -->|gRPC| co[checkout · Go]

    %% checkout orchestration (gRPC)
    co -->|gRPC| cart
    co -->|gRPC| pc
    co -->|gRPC| cur
    co -->|gRPC| ship
    co -->|gRPC| pay[payment · Node.js]
    co -->|gRPC| email[email · Py]

    rec -->|gRPC| pc

    %% data stores
    cart --> redis[("Redis<br/>cart")]:::store
    rev --> pg[("PostgreSQL<br/>reviews · optional")]:::store

    classDef edge  fill:#7c5cff,stroke:#fff,color:#fff;
    classDef new   fill:#9d7bff,stroke:#fff,color:#fff,stroke-width:2px;
    classDef store fill:#244c5a,stroke:#fff,color:#fff;
    classDef ext   fill:#1b1b1f,stroke:#7c5cff,color:#cfc6ff;
```

> **Telemetry:** services also emit traces/metrics to an optional OpenTelemetry collector
> (`COLLECTOR_SERVICE_ADDR`), and a Gemini-powered shopping-assistant can be enabled via
> [Kustomize components](/kustomize). Both are omitted above to keep the request path clear.

| Service | Language | Description |
| --- | --- | --- |
| [frontend](/src/frontend) | Go | HTTP server for the website; auto-generates a session for every visitor (no login). Renders the reviews UI. |
| [reviewsservice](/src/reviewsservice) ⭐ | Go | **New in VANTA.** Serves product reviews & aggregate ratings over gRPC; in-memory or PostgreSQL store. |
| [cartservice](/src/cartservice) | C# | Stores cart items in Redis and retrieves them. |
| [productcatalogservice](/src/productcatalogservice) | Go | Provides the product list, search, and individual product lookups. |
| [currencyservice](/src/currencyservice) | Node.js | Converts money between currencies (ECB rates). Highest-QPS service. |
| [paymentservice](/src/paymentservice) | Node.js | Charges the (mock) credit card and returns a transaction ID. |
| [shippingservice](/src/shippingservice) | Go | Estimates shipping cost and ships the order (mock). |
| [emailservice](/src/emailservice) | Python | Sends the order-confirmation email (mock). |
| [checkoutservice](/src/checkoutservice) | Go | Orchestrates cart retrieval, payment, shipping, and email. |
| [recommendationservice](/src/recommendationservice) | Python | Recommends products based on cart contents. |
| [adservice](/src/adservice) | Java | Serves contextual text ads. |
| [loadgenerator](/src/loadgenerator) | Python/Locust | Continuously simulates realistic shopping traffic. |

> Backing stores: **Redis** (cart) and an optional **PostgreSQL** (reviews, via the
> `reviews-persistence` component).

## 🛠 Platform & DevOps

Beyond the app, this repo is a **complete, reproducible self-managed platform** — every layer
is code. Nothing is clicked in a console: **Terraform** builds the infrastructure, **Ansible +
kubeadm** form the cluster, **ArgoCD** delivers changes via pull-based GitOps, and
**Prometheus/Grafana/Loki** close the loop with observability.

```mermaid
flowchart LR
    dev([👩‍💻 git push]):::ext

    subgraph ci["CI/CD · GitHub Actions + Jenkins"]
      direction LR
      test[test + vet] --> build[build image] --> scan[Trivy scan] --> ship[push image<br/>+ bump tag in Git]
    end

    reg[("Registry")]:::store
    gitcfg[("Git · kustomize/overlays")]:::store

    subgraph aws["AWS VPC 10.0.0.0/16 · ap-south-1 · Terraform"]
      direction TB
      subgraph master["Master · t3.small"]
        api["kube-apiserver + etcd"]:::edge
        argo["ArgoCD"]:::new
        obs["Prometheus · Grafana<br/>Alertmanager · Loki"]:::edge
      end
      w1["Worker-1 · t3.micro<br/>(app pods)"]:::node
      w2["Worker-2 · t3.micro<br/>(app pods)"]:::node
    end

    dev --> test
    ship --> reg
    ship --> gitcfg
    argo -->|watch| gitcfg
    argo -->|sync| w1
    argo -->|sync| w2
    reg -->|pull| w1
    reg -->|pull| w2
    obs -.->|scrape| w1
    obs -.->|scrape| w2

    classDef edge fill:#7c5cff,stroke:#fff,color:#fff;
    classDef new  fill:#ef7b4d,stroke:#fff,color:#fff,stroke-width:2px;
    classDef node fill:#326ce5,stroke:#fff,color:#fff;
    classDef store fill:#244c5a,stroke:#fff,color:#fff;
    classDef ext  fill:#1b1b1f,stroke:#7c5cff,color:#cfc6ff;
```

**Provisioned once** — `terraform apply` (VPC, subnet, IGW, security groups, 3× EC2 with a
`containerd`+`kubeadm` user-data bootstrap) → `ansible-playbook` (kubeadm `init`/`join` + Calico
CNI) → `scripts/setup-argocd.sh` (install ArgoCD + register the Applications) → Helm-install the
monitoring stack from `monitoring/`. **Then the day-to-day loop is automatic:** push → CI tests,
builds, scans, and commits a new image tag → ArgoCD syncs the cluster → rolling update.

| Layer | Tooling | Where |
| --- | --- | --- |
| **Infrastructure as Code** | Terraform — VPC, public subnet, IGW, security groups, EIP, TLS keypair, 3× EC2 (1 master + 2 workers) | [`/terraform`](/terraform) |
| **Configuration** | Ansible — `kubeadm` cluster bootstrap + an audit playbook | [`/ansible`](/ansible) |
| **Orchestration** | Self-managed **Kubernetes** (`kubeadm` + **Calico** CNI), Kustomize base + `dev`/`staging`/`prod` overlays | [`/scripts`](/scripts) · [`/kustomize`](/kustomize) |
| **GitOps delivery** | **ArgoCD** — `staging` auto-syncs, `prod` is manual sync with prune + retry/backoff | [`/argocd`](/argocd) |
| **CI/CD** | **GitHub Actions** + **Jenkins** — test, build, Trivy scan, plus `kustomize-build` and `terraform-validate` gates | [`/.github/workflows`](/.github/workflows) · [`Jenkinsfile`](/Jenkinsfile) |
| **Observability** | **Prometheus + Grafana + Alertmanager** (with SRE alert rules) and **Loki** for logs | [`/monitoring`](/monitoring) |
| **Security** | RBAC, Pod Security, **NetworkPolicies**, least-privilege security groups, non-root distroless images | [`/scripts`](/scripts) · [`/kustomize/components/network-policies`](/kustomize/components/network-policies) |
| **Resilience / SRE** | **HPA**, PodDisruptionBudgets, plus **chaos-engineering** and **failover** lab scripts and health checks | [`/scripts`](/scripts) · [`/kustomize/components/pod-disruption-budgets`](/kustomize/components/pod-disruption-budgets) |

> 💡 **Cost-aware & reproducible:** the AWS footprint runs at roughly **~$1.5/day** and tears
> down cleanly with `terraform destroy` — state, kubeconfig, and tfvars are git-ignored, never
> committed. The same app also runs **free on local kind** (next section).

## 🚀 Run it locally (kind)

The quickest way to see the full store on your machine — a local
[kind](https://kind.sigs.k8s.io/) cluster, no cloud account required.

```sh
# 1. Create a local cluster (maps NodePort 30080 → host 8888)
kind create cluster --config kind-local.yaml

# 2. Deploy the dev overlay (all 12 services + Redis)
kubectl apply -k kustomize/overlays/dev

# 3. Wait for everything to be Ready
kubectl wait --for=condition=ready pod --all --timeout=300s

# 4. Open the store
#    NodePort:      http://localhost:8888
#    or port-forward (more robust):
kubectl port-forward --address 0.0.0.0 svc/frontend-external 8088:80
#    → http://localhost:8088
```

**Build from source** instead of pulling images, then load into kind:

```sh
docker build -t reviewsservice:dev src/reviewsservice
docker build -t frontend:dev      src/frontend
kind load docker-image reviewsservice:dev frontend:dev --name boutique
kubectl set image deployment/reviewsservice server=reviewsservice:dev
kubectl set image deployment/frontend       server=frontend:dev
```

To enable the durable **PostgreSQL** reviews store, add the component to
`kustomize/overlays/dev/kustomization.yaml`:

```yaml
components:
  - ../../components/reviews-persistence
```

> ☁️ For **GKE**, **AWS EC2 (ArgoCD)**, Terraform, Helm, and Istio options, see
> [`/kustomize`](/kustomize), [`/terraform`](/terraform), and the
> [development guide](/docs/development-guide.md).

## 🧰 Tech stack

- **Languages:** Go · C# · Node.js · Python · Java
- **Comms:** gRPC + Protocol Buffers · gRPC health protocol
- **Data:** Redis (cart) · PostgreSQL / pgx (reviews)
- **Packaging:** Multi-stage Docker, `distroless:nonroot`
- **Infrastructure:** Terraform (AWS VPC + EC2) · Ansible · self-managed Kubernetes (`kubeadm` + Calico)
- **Orchestration:** Kubernetes · Kustomize (base + `dev`/`staging`/`prod` overlays + components) · Helm
- **CI/CD & GitOps:** GitHub Actions & Jenkins (vet, `-race` tests, Postgres service container, Trivy) · ArgoCD
- **Observability:** Prometheus · Grafana · Alertmanager · Loki
- **Frontend extras:** schema.org JSON-LD · accessible review components

## 📚 Documentation

- [Development guide](/docs/development-guide.md) — run and develop locally.
- [Reviews service](/src/reviewsservice/README.md) — API, storage modes, and configuration.
- [Adding a new microservice](/docs/adding-new-microservice.md).

## Credits & license

VANTA Boutique is built on Google's [Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo)
sample and is licensed under **Apache-2.0** (see [`LICENSE`](/LICENSE)). The Reviews
microservice, VANTA storefront, and CI/CD pipeline are additions by this project.
