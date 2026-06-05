# Auzix Strict Root Prototype

## Purpose

This track is for the version of Auzix where `AuzixRoot` becomes the real `/`.
It is intentionally stricter than the current Debian-backed KVM image path.

The current image builder can keep proving boot, desktop, and VM behavior. The
strict root prototype proves the filesystem contract and package migration
rules without touching the host root filesystem.

## Inspiration

GoboLinux proves that a Linux system can be organized around
program/version-owned trees rather than the traditional FHS layout. Its Recipes
repository is useful less as a binary-compatible target and more as a reminder
that package metadata can own source, version, patch, and install behavior in a
regular tree.

Auzix borrows that discipline, but makes services, stacks, and automation
first-class concepts because those map better to the lab and BKC model.

## Canonical Top Level

Strict Auzix root uses these native top-level directories:

```text
/System
/Programs
/Services
/Stacks
/Work
/Users
/Volumes
/Network
```

These are not aliases. In a final image they are the real root layout.

## Linux Plumbing Kept Native

The following Linux runtime interfaces remain real because they are kernel and
runtime ABI surfaces, not packaging taste:

```text
/dev
/proc
/sys
/run
```

We can add Auzix views over them later, but the first strict prototype should
not rename them.

## Core System Areas

```text
/System/Boot
/System/Kernel
/System/Drivers
/System/Settings
/System/State
/System/Logs
/System/Libraries
/System/Tools
/System/Compatibility
/System/PackageDB
/System/BuildTools
```

Core runtime libraries live under `/System/Libraries`. Program-owned libraries
live with the owning program:

```text
/Programs/OpenSSL/3.5/Libraries
/Programs/Bash/5.2/Libraries
```

The goal is to end the spread of `/lib`, `/lib64`, `/usr/lib`, and
`/usr/local/lib` as primary concepts.

## Compatibility Is Scaffolding

Legacy FHS locations may exist only as declared compatibility links or generated
compatibility trees:

```text
/bin
/sbin
/lib
/lib64
/usr
/etc
/var
/tmp
/opt
/home
```

They should never be package-owned destinations in a native Auzix recipe.

Suggested compatibility mapping:

```text
/bin      -> /System/Compatibility/bin
/sbin     -> /System/Compatibility/sbin
/lib      -> /System/Compatibility/lib
/lib64    -> /System/Compatibility/lib64
/usr      -> /System/Compatibility/usr
/etc      -> /System/Settings
/var      -> /System/State
/tmp      -> /Work/Temp
/opt      -> /Programs
/home     -> /Users
```

The strict audit treats undeclared files under legacy paths as build failures.

## Package Migration Stages

Each recipe should move through these states:

```text
stage-0-fhs-build
stage-1-compat-install
stage-2-native-paths
stage-3-target-arch-trimmed
stage-4-dead-code-trimmed
```

Stage 1 is useful for bootstrapping. Stage 2 is the real target. Stages 3 and 4
are where architecture-specific and dead legacy branches start coming out.

## Recipe Responsibilities

Auzix recipes are not just build scripts. They are contracts for:

- source origin and trust
- target architecture
- native install paths
- service ownership
- compatibility exports
- path migration debt
- validation commands

That means a recipe can be consumed by a shell builder first and later by BKC as
a real pipeline definition.

## First Prototype Target

Use the local workstation or a disposable Fedora/Debian clone as the build host,
but only write under:

```text
out/auzix-strict/AuzixRoot
```

Do not attempt a native boot image until the staged root can pass:

- top-level skeleton validation
- compatibility-link validation
- stray legacy-path scan
- recipe schema sanity
- `ldd`/`readelf` checks for any executable payload we add

## Success Criteria For This Pass

The first useful pass is deliberately small:

1. create the strict root skeleton
2. generate declared compatibility links
3. add a sample recipe that installs into native paths
4. audit for illegal legacy writes
5. produce a text report that shows what is native versus compatibility debt

## First Payload

The first compiled payload is intentionally small:

```text
/Programs/AuzixProbe/0.1/Commands/auzix-probe
/System/Compatibility/bin/auzix-probe
/System/PackageDB/AuzixProbe-0.1.auzix.json
```

Build and audit it with:

```sh
make auzix-strict-root
make auzix-strict-probe
make auzix-strict-audit
```

`AuzixProbe` is not meant to be a real system tool. It exists to prove native
program ownership, generated compatibility exports, receipts, and executable
dependency checks before we move on to Bash, Coreutils, or a dynamic linker
experiment.

The first shell-capable payload is BusyBox:

```text
/Programs/BusyBox/1.36.1/Commands/busybox
/System/Compatibility/bin/busybox
/System/Compatibility/bin/sh
```

Build it with:

```sh
make auzix-strict-root
make auzix-strict-busybox
make auzix-strict-audit
```

That gives the staged root a small shell surface without accepting `/bin` as a
native ownership location. `/bin/sh` remains a compatibility path into the
native BusyBox program tree.

## Tiny Container

Once BusyBox is present, the strict root can be wrapped as a scratch-based
container:

```sh
make auzix-strict-container
docker run --rm -it auzix-strict:local
```

Inside the container, the root filesystem is the staged AuzixRoot tree. That
makes it a cheap shellable target before we attempt a bootable VM image.

## Legacy Link Prune Test

The strict audit now writes a second evidence file next to the normal report:

```text
out/auzix-strict/audit-report.evidence.txt
```

That evidence includes `stat`, `file`, `readelf`, `objdump`, `ldd`, and
legacy-path hits from `strings` for each executable payload.

To test whether the current payloads actually require top-level legacy links,
build a pruned scratch container:

```sh
make auzix-strict-pruned-test
```

This copies the staged root, removes top-level compatibility links such as
`/bin`, `/usr`, `/lib`, and `/var`, imports the result as
`auzix-strict:pruned`, and runs the native BusyBox and AuzixProbe paths. If that
passes, the current runtime payload does not require those top-level legacy
links.
