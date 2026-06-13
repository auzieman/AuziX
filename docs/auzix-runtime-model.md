# Auzix Runtime Model

## Purpose

The strict-root ISO proves that Auzix can boot with the native root contract as
the real `/`. The next design problem is deciding which tree owns applications,
services, stacks, and build/runtime substrates.

This note is the first checkpoint for that model. It is intentionally practical:
native host processes must work, containerized services must work, and graphical
applications must have a migration path without turning `/usr` back into the
center of the system.

## Working Definitions

```text
/System    OS, kernel, drivers, settings, state, logs, shared system libraries
/Programs  versioned application payloads and user-facing executable families
/Services  supervised long-running host services
/Stacks    composed service groups, container bundles, and deployment graphs
/Work      builds, sources, caches, scratch data, pipelines
/Users     user homes and profiles
/Volumes   mounted local and remote storage
/Network   network identity, routes, DNS, service discovery views
```

The short version:

- `/Programs` answers "what is installed?"
- `/Services` answers "what is running as an operating-system service?"
- `/Stacks` answers "what pieces are deployed together?"
- `/Work` answers "where do builds, source trees, caches, and pipelines happen?"

## Containerd Fit

Containerd should be treated as an execution substrate, not as the whole service
model. Its strong fit is running OCI bundles, managing image content, snapshots,
runtime shims, and namespaces. Auzix should expose that through native paths and
receipts rather than adopting `/var/lib/containerd` as a design center.

Suggested mapping:

```text
/Programs/containerd/<version>/Commands/containerd
/Programs/runc/<version>/Commands/runc
/Programs/nerdctl/<version>/Commands/nerdctl
/Services/containerd
/System/Settings/containerd/config.toml
/System/State/containerd
/System/Logs/containerd
/Work/Containers/content
/Work/Containers/snapshots
/Work/Containers/buildkit
```

The compatibility layer can publish:

```text
/System/Compatibility/bin/containerd
/System/Compatibility/bin/ctr
/System/Compatibility/bin/nerdctl
/System/Compatibility/bin/runc
```

Containerd namespaces map cleanly to Auzix stack ownership:

```text
auzix.system      host service substrate
auzix.build       BuildKit and native package construction
auzix.desktop     sandboxed graphical application experiments
auzix.lab         lab/demo workloads
k8s.io            Kubernetes-owned containers when k3s or kubelet is present
```

## Services

`/Services` owns service identity, desired state, restart policy, dependency
notes, and logs/state pointers. It should not be limited to containers.

Examples:

```text
/Services/ssh
/Services/sftp
/Services/containerd
/Services/buildkit
/Services/display-manager
```

A service receipt should describe:

- native command path
- settings path
- state path
- log path
- runtime type: `host-process`, `containerd`, `kubernetes`, or `external`
- dependencies
- exposed sockets and ports

Early host service example:

```text
/Services/ssh/service.auzix.json
/Programs/OpenSSH/10.0/Commands/sshd
/System/Settings/ssh/sshd_config
/System/State/ssh
/System/Logs/ssh
```

SFTP should start as an SSH capability, not a separate daemon, unless a later
storage product needs a dedicated service boundary.

## Stacks

`/Stacks` owns relationships and composed deployments. It is the right place for
"these services make a functional block" rather than "this binary is installed."

Examples:

```text
/Stacks/remote-access
/Stacks/native-build
/Stacks/desktop-sandbox
/Stacks/graphical-porting
```

`/Stacks/remote-access` might include:

- service: `/Services/ssh`
- service capability: SFTP
- settings: `/System/Settings/ssh`
- firewall policy
- user/group requirements

`/Stacks/native-build` might include:

- service: `/Services/buildkit`
- service: `/Services/containerd`
- programs: compiler, linker, make, pkg-config
- work roots: `/Work/Builds`, `/Work/Sources`, `/Work/Cache`

## Programs, Flatpaks, Snaps, And App Bundles

`/Programs` is the native ownership model. Flatpak and Snap are useful reference
points, but they should not become the native package identity.

Suggested approach:

- Native Auzix programs install under `/Programs/<Name>/<Version>/...`.
- OCI-delivered graphical applications can be represented by program receipts
  that point at container images or unpacked OCI bundles.
- Flatpak-style runtimes can inspire shared runtime layering, but the exposed
  Auzix identity should still be `/Programs`.
- Snap-style service/app bundles can inspire app plus service packaging, but
  Auzix should keep service identity in `/Services` and composition in
  `/Stacks`.

Potential graphical app layout:

```text
/Programs/Midori/<version>/Commands/midori
/Programs/Midori/<version>/Libraries
/Programs/Midori/<version>/Resources
/Programs/Midori/<version>/Receipts/program.auzix.json
/Services/midori-update-helper
/Stacks/desktop-web
```

For containerized graphical experiments:

```text
/Programs/Midori/<version>/Receipts/program.auzix.json
/Stacks/desktop-sandbox/midori.stack.auzix.json
/Work/Containers/content
/Work/Containers/snapshots
```

## Shared Graphical Runtimes

Graphical package promotion needs an explicit boundary between shared toolkit
runtime and application-owned code:

```text
/System/Libraries/Runtime/glibc
/System/Libraries/Runtime/GTK3/<abi>
/System/Libraries/Runtime/GLib/<abi>
/System/Resources/GTK3
/Programs/Gnumeric/<version>/Libraries
/Programs/Gnumeric/<version>/Resources
```

Libraries that define a stable toolkit ABI and are used by several applications
are candidates for `/System/Libraries/Runtime`. Application plugins, private
libraries, data files, schemas, icons, and version-coupled modules remain under
the owning `/Programs/<Name>/<Version>` tree.

Promotion should happen in two phases:

1. Build a self-contained program package and prove it starts with its declared
   loader, libraries, plugins, and resources.
2. Use package audits to identify duplicated SONAMEs, then move only verified
   shared ABI sets into a separately versioned system runtime package.

`scripts/audit-auzix-package-runtime.sh` validates declared commands, exports,
runtime paths, and bundled-loader dependency resolution. A package should not
be promoted from the Debian intake tree merely because its main executable
starts; plugin loading and data-path behavior are part of the runtime contract.

## Build Requirements

The first build stack should be boring and visible. It needs enough tools to
compile native programs and inspect path debt:

```text
/Programs/GCC
/Programs/Binutils
/Programs/Make
/Programs/PkgConfig
/Programs/CMake
/Programs/Ninja
/Programs/Git
/Programs/Patchelf
/Programs/Strace
/Programs/File
/Programs/Binutils/Commands/readelf
/Programs/Binutils/Commands/objdump
```

The build substrate should write to:

```text
/Work/Sources
/Work/Builds
/Work/Cache
/Work/Pipelines
```

Containerized builds can use BuildKit/containerd, but native bootstrap builds
still matter because Auzix has to prove binaries can be compiled and linked
against native paths.

## Near-Term Implementation Order

1. Keep the boot ISO small and shell-first.
2. Add a `Services` scaffold and receipt schema.
3. Add a `Stacks` scaffold and receipt schema.
4. Package OpenSSH as the first meaningful host service.
5. Package containerd/runc/nerdctl as the first runtime substrate.
6. Add BuildKit as the first build stack service.
7. Add native build tools and keep `readelf`, `ldd`, `strings`, `stat`, and
   `strace` checks in the audit loop.
8. Attempt a tiny graphical stack only after service supervision, storage, and
   dynamic library path checks are boring.

## Key Rule

Containerd can run services and app sandboxes, but it should not erase the Auzix
model. The Auzix model is:

```text
Program payloads live in /Programs.
Running service identity lives in /Services.
Composed deployment intent lives in /Stacks.
Mutable build/runtime substrate lives in /Work.
```
