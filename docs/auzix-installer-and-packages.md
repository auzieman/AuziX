# Auzix Installer And Package Substrate

## Immediate Goal

The strict-root ISO now provides live desktop access and standalone
persistence:

1. boot from the ISO
2. transpose the live Auzix root to local storage
3. install GRUB and the Auzix kernel/initramfs
4. boot the installed root without the ISO
5. refresh the repository and add packages persistently

## Current Installer Shape

The live ISO includes:

```text
/System/Tools/auzix-install-disk
```

Usage from the booted ISO:

```sh
/System/Tools/auzix-install-disk --force /dev/vda
```

That command:

- wipes the target disk partition table
- creates one Linux partition
- formats it as ext4 with label `AUZIXROOT` when e2fsprogs is available
- emits an explicit warning before falling back to ext2
- copies the live Auzix root onto it
- installs GRUB for BIOS boot
- writes the kernel command line using `root=LABEL=AUZIXROOT`
- writes an install note under `/System/Settings/install`

The normal result boots directly from the target disk. The ISO remains a
recovery fallback and can still hand off to an installed root with:

```text
auzix.root=LABEL=AUZIXROOT
```

The ISO init then mounts that root and `switch_root`s into it.

The current GRUB package is BIOS-first. UEFI installation remains follow-up
work.

## Package Manager Choice

Recommendation: adopt `apk-tools` as the first low-level package engine
candidate, but keep Auzix receipts as the distribution contract.

That means:

- `.apk` or apk-style packages can move files and solve dependencies.
- `/System/PackageDB/*.auzix.json` remains the higher-level receipt.
- `/Programs`, `/Services`, `/Stacks`, and `/Work` remain Auzix concepts.
- BKC pipelines should reason about Auzix receipts, not raw package-manager
  implementation details.

Why `apk-tools` is the best first candidate:

- it is small and already proven in BusyBox/musl-style systems
- it has a static tool package path, which matters during bootstrap
- it supports repository indexes and dependency solving without adopting a
  heavyweight distro base
- it is simpler to carry in a tiny live image than dpkg/rpm stacks

Why not invent a package manager first:

- package solving, repository indexes, signatures, upgrades, and file ownership
  are real projects
- Auzix needs path policy, service receipts, and stack relationships more than
  it needs a brand-new solver
- custom package metadata can wrap apk rather than replace it

Why not adopt apk as the whole identity:

- apk knows packages, not Auzix service/stack intent
- apk does not define `/Programs` ownership semantics by itself
- apk does not express BKC pipeline relationships

So the split should be:

```text
apk-tools       low-level package install/upgrade/remove engine
Auzix receipts  path, service, stack, validation, and pipeline contract
BKC             orchestration and remote execution
```

Current working decision:

- keep `/System/PackageDB/*.auzix.json` as the immediate package database
- keep repository and local transaction caches as JSON while the schema is
  still changing; move to SQLite only when package volume or query load makes
  indexed access worthwhile
- use `/System/Tools/auzix-pkg` for repository refresh, inspection, dependency
  installation, checksum verification, and installed-state updates
- treat `.apk` as the first repository/index/install transport to prototype
- do not adopt Anaconda as the installer base; it is valuable as a reference for
  partitioning and guided install flow, but too large and distro-policy-heavy for
  the live image
- keep the live ISO installer shell/Lua path small until package install,
  desktop launch, and persistence are stable
- keep one JSON install-plan contract behind every front end: shell remains the
  execution layer, Lua validates and sequences the plan, and `dialog` or
  `zenity` can collect answers without duplicating partition/install logic
- start with a terminal question flow as the fallback and a GTK question flow
  when the graphical session is available; an EFL-native installer can replace
  the GTK presentation later while consuming the same plan
- BKC follow-up: run the same install-plan validation and image contract checks
  as pipeline steps, then evaluate a bounded build/test/commit loop. Keep commit
  creation gated on a clean diff and successful checks; pushing should remain an
  explicit policy decision rather than an unconditional hook.

## Installer Foundation

The first installer implementation now follows that contract:

```text
/System/Tools/auzix-installer             Lua plan validation and sequencing
/System/Tools/auzix-installer-gui         graphical frontend dispatch/fallback
/System/Tools/auzix-install-disk          destructive shell execution boundary
/System/Settings/installer/questions.json shared frontend question contract
/System/Settings/installer/plans          versioned JSON install plans
```

`auzix-installer validate PLAN` and `summary PLAN` are non-destructive.
`auzix-installer run PLAN` accepts only the known plan format, ext4, a `/dev`
target, `grub` or `iso`, and an explicit boolean confirmation. The `dialog`
frontend performs a separate final confirmation before it emits and runs a plan.

The graphical command currently dispatches to an installed EFL frontend first,
then GTK, and otherwise falls back to the TUI. A future graphical frontend only
needs to consume `questions.json`, emit `auzix-install-plan-v1`, and invoke the
same validation and execution commands. It must not implement partitioning or
disk-copy logic itself.

The next package milestone should be an Auzix package wrapper, not a full package
manager. A useful package artifact has:

```text
/Programs/<Name>/<Version>/...
/Services/<service>/run                 optional
/System/Settings/<name>/...             optional templates
/System/PackageDB/<Name>-<Version>.auzix.json
```

The wrapper can later emit an apk package containing the same paths plus a small
post-install hook that refreshes Auzix receipts, XDG desktop caches, and service
indexes.

## First Package Tracks

The first useful package tracks should be:

```text
BusyBox          already present; bootstrap shell/tools
apk-tools-static package engine experiment
OpenSSH          remote access and SFTP subsystem
containerd       OCI runtime substrate
runc             OCI runtime implementation
nerdctl          operator-friendly containerd CLI
BuildKit         repeatable source/build pipeline substrate
```

The immediate live-desktop package track is:

```text
Terminology      restored in-UI shell access
xdg-menu-data    e-applications.menu and desktop-directories for efreet
acpid            netlink/input-layer event daemon
udev             deterministic input/device discovery
PulseAudio       mixer module support, even before real audio hardware
```

The build/inspection stack should follow quickly:

```text
GCC
Binutils
Make
PkgConfig
Git
Patchelf
Strace
File
```

The first graphical package track should bias toward Enlightenment:

```text
EFL
Enlightenment
Terminology or smaller terminal fallback
display/seat/input support
```

COSMIC remains a later workstation target after the smaller graphical substrate
is proven.

## Service Access Order

For early remote access:

1. install OpenSSH payload under `/Programs/OpenSSH/<version>`
2. create `/Services/ssh`
3. write config under `/System/Settings/ssh`
4. store host keys under `/System/State/ssh`
5. log under `/System/Logs/ssh`
6. expose SFTP as the sshd subsystem

Only after SSH works should we add containerd, because containerd will make the
machine more useful but does not solve first access by itself.

## Containerd Order

Package order:

1. runc
2. containerd
3. nerdctl
4. CNI plugins
5. BuildKit

Native paths:

```text
/Programs/runc/<version>/Commands/runc
/Programs/containerd/<version>/Commands/containerd
/Programs/nerdctl/<version>/Commands/nerdctl
/Services/containerd
/System/Settings/containerd/config.toml
/System/State/containerd
/System/Logs/containerd
/Work/Containers
```

Containerd should default its root/state away from legacy paths:

```toml
root = "/Work/Containers/containerd"
state = "/System/State/containerd"
```
