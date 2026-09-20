# How this was built

The platform in this repo did not start as a 3-node cluster on AWS. It went through three
phases, and the order matters because each one exposed a problem the next one solved.

## 1. minikube on WSL

The upstream Online Boutique running on a single minikube node. Enough to learn the objects
(Deployment, Service, ConfigMap, Secret, probes) and to get the first custom service, reviews,
talking gRPC to the frontend. What it could not teach: anything about nodes, networking between
machines, or what happens when a node dies.

## 2. Single node on EC2

The same app on one Ubuntu instance with kubeadm. First contact with the control plane as a
real thing: kubeadm init, the CNI choice (Calico), certificates and SANs when kubectl comes in
over a public IP, containerd configuration, swap. Also the first time cost mattered, which is
where the stop/start and teardown habits come from.

## 3. Three nodes on EC2, provisioned from code

One master and two workers from Terraform, formed by Ansible and kubeadm, delivered by Argo CD.
This is the platform the rest of the repo documents. The drills that matter were only possible
here: drain a worker and watch pods reschedule, kill pods and watch the store self-heal, break a
deploy and roll back with `git revert`, take an etcd snapshot and restore it.

## Retired lab scripts

Each phase produced one-off scripts (RBAC and HPA walkthroughs, node rescue, swap setup, a
minikube failover lab). They hard-coded old paths, node IPs and registry tags, and none of them
were part of the supported flow, so they were removed from the tree on 2026-09-20. They are
still in history:

```sh
git log --oneline -- scripts/labs
git show <commit>:scripts/labs/failover-lab-minikube.sh
```

The supported equivalents live in [`/scripts`](/scripts): `failover-lab.sh`,
`chaos-engineering.sh`, `health-check.sh`, `setup-rbac.sh`, `setup-hpa.sh`,
`setup-pod-security.sh`, `etcd-backup-setup.sh`, `promote.sh`, `bump-image-tags.sh`.

## What broke along the way

Kept because the fixes are the useful part. Every row points at the code or runbook that
carries the fix today.

| Symptom | Cause | Fix in repo |
| --- | --- | --- |
| kubectl from the laptop over the public IP: `x509: certificate is valid for ..., not <public-ip>` | the apiserver certificate only had the private IP in its SANs | extra SANs passed to `kubeadm init` ([`scripts/bootstrap-k8s.sh`](/scripts/bootstrap-k8s.sh), [`terraform/outputs.tf`](/terraform/outputs.tf)) |
| kubelet install aborted on a fresh node during cloud-init | dpkg conffile prompt for `/etc/default/kubelet` with no TTY | non-interactive dpkg with `--force-confold` in the user-data ([`terraform/compute.tf`](/terraform/compute.tf)) |
| Control plane froze with Argo CD and monitoring on a 2 GB master | out of memory | swap configured in the master bootstrap ([`terraform/compute.tf`](/terraform/compute.tf)); Prometheus retention 6h and resource limits ([`monitoring/prometheus-values.yml`](/monitoring/prometheus-values.yml)) |
| Installing Argo CD failed on its CRDs: `metadata.annotations: Too long` | client-side apply stores the whole object in an annotation | `kubectl apply --server-side` ([`scripts/setup-argocd.sh`](/scripts/setup-argocd.sh)) |
| Velero backups of local-path volumes were empty | snapshots do not exist for hostPath/local-path | Velero file-system backup through the node-agent ([`backup/velero-install.sh`](/backup/velero-install.sh)) |
| Velero stopped backing up after credentials were rotated | the node-agent DaemonSet kept the old credentials | restart the node-agent after a credentials change ([`docs/RUNBOOKS.md`](/docs/RUNBOOKS.md), backup section) |
| A CVE in a base image blocked the whole release | Trivy CRITICAL gate did its job | dependency bump (Netty, `CVE-2026-75595`) then a normal promote; the gate stays |
