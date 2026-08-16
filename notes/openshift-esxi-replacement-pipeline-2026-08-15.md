# OpenShift/OKD on ESXi replacement pipeline note — 2026-08-15

Idea captured during the ESXi AUZiX workstation-media test:

- Use server3/ESXi as a temporary bootstrap host for an OpenShift/OKD candidate.
- Prove the cluster inside ESXi first.
- Then use it as the replacement pipeline target for current ESXi/Docker Swarm
  hosted services.

BKC planning artifact:

- `BlackKnightController/pipelines/openshift-esxi-replacement-prep/`

Default stance:

- OKD single-node/compact first, unless a supported OpenShift pull-secret flow
  is explicitly supplied.
- Receipts first; destructive VM creation and workload migration disabled by
  default.
- ESXi remains useful as the bootstrap nest until OpenShift/OKD proves API,
  console, ingress, registry, storage, BKC visibility, and one migrated
  non-critical workload.

Connection to AUZiX:

- The ESXi AUZiX media run proved the lab can generate hypervisor-specific boot
  media and validate it through serial/SSH.
- The OpenShift/OKD prep pipeline should reuse that discipline: explicit VM
  shape, artifact hashes, network/DNS plan, console/proxy notes, and receipts.

