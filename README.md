# AuziX

AuziX is a small custom Linux distribution experiment built around readable
system structure, live workstation boot, and explicit package receipts.
   <img width="1185" height="737" alt="image" src="https://github.com/user-attachments/assets/be8e7786-9d3a-402a-b027-0ca8af2c21c3" />

The current root contract is:

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
<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/541bc7de-3168-45fb-8abc-0d16c450bee3" />

Compatibility paths live under `/System/Compatibility` and are treated as
bridges, not as the distro identity.

## Current State

- BusyBox bootstrap root
- Bash, OpenSSH, sudo
- udev, DBus, acpid, PulseAudio probes
- Xorg fallback display path
- LightDM optional greeter path
- Enlightenment desktop path
- Terminology and XTerm
- NetSurf as the first small optional browser proof
- package receipts under `/System/PackageDB`
- package repo builder producing `.auzix.tar.gz` artifacts and `index.json`
- early disk installer that transposes the live root to a target disk

The stable VM test path currently uses the whole-root initramfs ISO. The
split ISO-root mode is promising but still experimental.

## Build

For local containerized builds:

```sh
docker compose build builder
docker compose run --rm builder
```

For k3s/Kubernetes builds, see:

```text
docs/build-infrastructure.md
```

For licensing direction, see:

```text
docs/licensing.md
```

The direct host build flow remains:

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
make auzix-strict-package-repo
make auzix-strict-iso
```

The same sequence is wrapped by:

```sh
make auzix-strict-all
```

Local Enlightenment wallpapers/themes can be staged separately with
`make auzix-strict-e-assets`, but they are not part of the default reproducible
build.

The default ISO output is:

```text
artifacts/auzix/auzix-strict-shell.iso
```

## Notes

This repo was forked out of the Tabor Linux Forge experiments once AuziX became
its own distro track. The Amiga/Tabor work remains useful design feedback, but
AuziX owns the x86_64 live workstation path.
