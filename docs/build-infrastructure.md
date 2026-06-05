# Build Infrastructure

AuziX should ship the assets needed to produce the distro, not the produced
distro artifacts. Generated roots, ISOs, package repositories, and VM images
belong under ignored `out/` and `artifacts/` paths.

## Local Docker Compose

Build the builder image and run the full current strict ISO pipeline:

```sh
docker compose build builder
docker compose run --rm builder
```

Outputs are written to ignored working-tree directories:

```text
out/
artifacts/
```

For an interactive build shell:

```sh
docker compose run --rm --profile shell shell
```

## k3s / Kustomize

The Kubernetes manifests are intentionally generic. They assume a builder image
exists at:

```text
ghcr.io/auzieman/auzix-builder:latest
```

Build and push that image from a workstation or CI runner:

```sh
docker build -t ghcr.io/auzieman/auzix-builder:latest -f docker/builder/Dockerfile .
docker push ghcr.io/auzieman/auzix-builder:latest
```

Run the default cluster build:

```sh
kubectl apply -k k8s/base
kubectl -n auzix-build logs -f job/auzix-build
```

For clusters with an NFS dynamic provisioner using the `nfs-client` storage
class:

```sh
kubectl apply -k k8s/overlays/nfs
kubectl -n auzix-build logs -f job/auzix-build
```

The NFS overlay switches the workspace PVC to `ReadWriteMany` and increases the
requested size. Adjust `storageClassName` to match the local k3s cluster.

For the current workstation/BKC target names, see `docs/controller-targets.md`.

## Swarm / Compose

The Compose file is also the Swarm starting point. A small internal builder
swarm can run the same image and mount shared build storage:

```sh
docker compose build builder
docker stack deploy -c compose.yaml auzix
```

For Swarm, prefer a shared filesystem such as NFS for `out/` and `artifacts/`
if builds may move between nodes. The Compose defaults use local bind mounts for
developer clarity; production builder nodes should replace those with cluster
storage.

## Scope

This repo does not need Black Knight Controller to build AuziX. BKC can still
orchestrate VM deployment and lab testing externally, but the distro repo should
remain self-producing with Docker and Kubernetes primitives.

Local themes, wallpapers, and workstation defaults are optional inputs. They are
not part of the default Compose or k3s build; run `make auzix-strict-e-assets`
explicitly when producing a personal spin.
