# AuziX 🌀

An elegant, decentralized workstation operating system built on absolute state determinism, micro-isolated runtimes, and an autonomous personal compute fabric.

Inspired by the structural sanity of GoboLinux, the lightweight orchestration philosophy of AmigaOS (ARexx), and the simplicity of Slackware.

<img width="1185" height="737" alt="AuziX System Architecture" src="https://github.com/user-attachments/assets/be8e7786-9d3a-402a-b027-0ca8af2c21c3" />

## The Root Contract

```
/System/        ← Immutable Host Base (Minimal, Read-Only Core)
/Programs/      ← Human-Readable Application Hierarchies
/Services/      ← Micro-Isolated, Containerized Daemons
/Stacks/        ← Declarative Runtime Environments
/Work/          ← Ephemeral Build & Compilation Spaces
/Users/         ← User Data & Profiles
/Volumes/       ← Sanitized, Context-Aware Mount Points
/Network/       ← Distributed Grid Configuration
```

Compatibility paths live under `/System/Compatibility` and are treated as bridges, not as the distro identity.

<img width="1920" height="1080" alt="AuziX Live Environment" src="https://github.com/user-attachments/assets/541bc7de-3168-45fb-8abc-0d16c450bee3" />

## 👁️ The Vision

Modern operating systems are broken. Standard Linux is plagued by a century of messy legacy pathing, brittle global dependencies, and environment pollution. Modern "immutable" alternatives fix the stability but introduce extreme configuration complexity.

AuziX carves a third path: **Unrivaled structural simplicity.** By isolating a minimalist core from runtime bloat and using a systemic Lua + JSON orchestration mesh, AuziX treats your local network not as a collection of separate computers, but as a single, organic, elastic supercomputer.

## 🛠️ Core Architecture

### 1. Systemic Lua-JSON Mesh (Codex)

Say goodbye to fragile shell scripts, sed loops, and erratic environmental variables. The AuziX package engine, **Codex**, unifies system state declarations using explicit JSON manifests and executes them via a hyper-efficient Lua runtime. Every package, localized build, Snap, or Flatpak is treated as an abstract, self-describing payload.

### 2. Ephemeral Isolation & Clean Overlays

The host system stays permanently clean. Core items like SSH and SFTP are protected in the immutable base, while user programs, environments, and compilation build steps are entirely sandboxed. Turn on **Ephemeral Overlay Mode**, break the system, test experimental configurations, and reboot to wipe away the chaos.

### 3. Micro-Containerized Services

System services do not leak binaries or state files into a global `/etc` or `/var`. Extended services run inside native, lightweight container sandboxes. The local system remains fast, predictable, and virtually unbrickable.

### 4. Autonomous Grid Scheduling (The Compute Fabric)

AuziX is built for the personal multi-device era. Using autonomous mDNS discovery and a lightweight, resource-aware Lua scheduler, your machines cooperate natively. Ask a weaker laptop to execute a heavy build or AI container, and Codex will seamlessly offload the computation to a stronger node on your local network—piping the results back to your screen instantly.

## 📦 Current State

The foundational bootstrap stack includes:

- **Core Runtime:** BusyBox bootstrap root, Bash, OpenSSH, sudo
- **System Services:** udev, DBus, acpid, PulseAudio probes
- **Display Stack:** Xorg fallback path, LightDM optional greeter, Enlightenment desktop environment
- **Terminals:** Terminology and XTerm
- **Network Browsers:** NetSurf (minimal), Midori (pragmatic)
- **Package Management:** Explicit `/System/PackageDB` receipts, `.auzix.tar.gz` artifacts with `index.json` manifests
- **Boot & Install:** GRUB-backed installer for standalone BIOS/UEFI VM boot; Live ISO with complete root mounted directly

![Midori](docs/images/auzix-midori.jpg)
![NetSurf](docs/images/netsurf.jpg)

The live image uses a small boot initramfs and keeps the complete root on the ISO. Installed systems boot directly from GRUB without the ISO.

## 🚀 Current Engineering Focus

We are actively refactoring the foundational bootstrap layers to realize this architecture:

- **The Great Lua Shift:** Migrating legacy shell logic to pure, deterministic Lua modules to eradicate permission bleeding and environmental "dubs."
- **Path Context Resolution:** Upgrading installer logic so Codex dynamically isolates the Target disk state from the Live ISO memory space.
- **Legacy Path Vaporization:** Eradicating hardcoded Linux FHS paths in favor of declarative, relative directory mappings.
- **Compute Fabric Mesh:** Prototyping autonomous mDNS discovery and lightweight scheduler for decentralized workload orchestration.

## 🔨 Build

For local containerized builds:

```sh
docker compose build builder
docker compose run --rm builder
```

For k3s/Kubernetes builds, see:

```
docs/build-infrastructure.md
```

For the source-build/staging flow and current handoff notes, see:

```
docs/build-flow-notes.md
docs/source-workbench.md
docs/issues-and-build-notes.md
docs/core-validation-loop.md
```

**Direct host build flow:**

```sh
make auzix-strict-root
make auzix-strict-busybox
make auzix-strict-live-tools
make auzix-strict-access
make auzix-strict-dbus
make auzix-strict-udev
make auzix-strict-acpid
make auzix-strict-host-xorg
make auzix-strict-host-e
make auzix-strict-host-terminology
make auzix-strict-host-xterm
make auzix-strict-netsurf
make auzix-strict-lightdm
make auzix-strict-desktop-repo-packages
make auzix-strict-package-repo
make auzix-strict-iso
```

Or use the unified target:

```sh
make auzix-strict-all
```

**Output:**

```
artifacts/auzix/auzix-strict-shell.iso
```

**Desktop Assets:**

Local Enlightenment wallpapers/themes can be staged with `make auzix-strict-e-assets` and published as repository packages with `make auzix-strict-desktop-repo-packages`.

## ⚖️ License & Contributions

AuziX is licensed under the **GNU General Public License v3.0** (GPLv3). This ensures that all derivatives, modifications, and commercial distributions must disclose their source code and remain under the same copyleft framework.

- **Hobbyist & Personal Use:** Completely free, open, and community-driven.
- **Commercial Use:** Must comply with GPLv3 copyleft obligations—source code disclosure is required.

For licensing details and dual-licensing inquiries, see `docs/licensing.md` or contact the maintainer.

---

> "The absolute sanity of a human-readable file system. The safety of a cloud fabric. The spirit of the Amiga."

## History

This repo was forked out of the Tabor Linux Forge experiments once AuziX became its own distro track. The Amiga/Tabor work remains useful design feedback, but AuziX owns the x86_64 live workstation path.
