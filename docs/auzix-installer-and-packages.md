# Auzix Installer And Package Substrate

## Immediate Goal

The strict-root ISO now boots to a shell. The next practical goal is early
machine access and persistence:

1. boot from the ISO
2. transpose the live Auzix root to local storage
3. boot the installed root through the ISO with `auzix.root=/dev/...`
4. add SSH/SFTP and containerd so the system can be worked remotely
5. later package a disk bootloader so the ISO is no longer required

This deliberately separates "install a root filesystem" from "own the entire
boot chain." It lets us start testing persistence without pretending the
bootloader package is finished.

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
- formats it as ext2 with label `AUZIXROOT`
- copies the live Auzix root onto it
- writes an install note under `/System/Settings/install`

For now, boot the installed root through the ISO by adding:

```text
auzix.root=/dev/vda1
```

The ISO init then mounts that root and `switch_root`s into it.

## Bootloader Follow-Up

Independent disk boot needs one of these later packages:

- GRUB for BIOS/UEFI VM targets
- syslinux/extlinux for a smaller BIOS-first path
- systemd-boot only after an EFI-first path exists

For the first Proxmox VM iteration, ISO-provided kernel plus installed root is
good enough. It avoids dragging a full bootloader toolchain into the first tiny
live image.

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
