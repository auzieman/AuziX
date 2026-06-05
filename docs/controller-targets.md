# Controller Targets

AuziX build assets are designed to run locally, through Docker Swarm, or through
k3s. The repo should not own BlackKnightController, but it should name the API
targets BKC and operator shells can use.

## Local Shell Targets

```sh
docker context use auzix-swarm
kubectl config use-context auzix-k3s
```

For repeatable scripts, prefer explicit targets:

```sh
docker --host ssh://root@swarm1.lab.auzietek.com compose build builder
kubectl --context auzix-k3s apply -k k8s/base
```

## Build Placement

- Compose is the single-node and swarm-friendly build runner.
- Kustomize is the k3s runner for cluster build jobs.
- NFS-backed workspaces are optional, but useful when artifacts need to survive
  job replacement or move between `ns1`, the swarm, and k3s.
- BKC should call Docker and Kubernetes APIs directly for scans, deploys, and
  health checks; SSH and Ansible remain host bootstrap tools.
