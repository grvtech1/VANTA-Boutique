# Learning-phase lab scripts (historical)

These scripts are from the minikube → single-node → 3-node AWS learning journey that produced
this platform. They are kept as an honest record of the phases (RBAC, HPA, ConfigMaps/Secrets,
failover, node rescue) but they are **not** part of the supported flow:

- many hard-code an old `~/online-boutique` path, a specific kubeconfig or node IPs;
- some target **minikube** (`failover-lab-minikube.sh`, `multi-node-setup.sh`);
- `patch-images.sh` points at an old public registry tag.

Supported equivalents live one level up in [`/scripts`](../) (`failover-lab.sh`,
`chaos-engineering.sh`, `health-check.sh`, `setup-*.sh`, `promote.sh`, `bump-image-tags.sh`).
