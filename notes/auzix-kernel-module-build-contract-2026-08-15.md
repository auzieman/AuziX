# AUZiX kernel module build contract — 2026-08-15

This note records the Kmod/KernelModules lesson from VMID135 and expands it for
the next hardware target, including USB thumbdrive boot on non-VM machines.

## Why this exists

VMID135 had `Fuse3`, `Libfuse34`, and later `Kmod`, but Flatpak still could not
mount `/run/user/1000/doc`. The kernel module package had `modules.dep` entries
for `kernel/fs/fuse/fuse.ko` but did not include the actual module payload.

That state is worse than an obvious missing package: it looks installed, but
`modprobe fuse` fails at runtime and desktop apps degrade through portal errors.

## Contract

`KernelModules` must preserve a coherent module tree:

- if `modules.dep`, `modules.order`, or aliases mention a module selected for an
  AUZiX tier, the corresponding `.ko` payload must be present;
- module indexes must not be copied in a way that references omitted selected
  modules;
- the package must match the running or installed kernel release exactly;
- `/System/Drivers/<kernel-release>` is the AUZiX authority path;
- `/lib/modules/<kernel-release>` may be a compatibility alias to
  `/System/Drivers/<kernel-release>` because `kmod`/`modprobe` and the kernel
  module loader expect that conventional lookup path.

## Current tiers

Base VM/live boot:

- virtio block/network/scsi;
- common SATA/NVMe fallback;
- loop, ISO9660, SquashFS, overlay;
- ext2/ext4 and their dependency modules;
- common emulated NICs such as e1000/e1000e/vmxnet3/r8169.

Desktop/input:

- DRM/KMS basics used by QEMU/virtio/bochs/qxl paths;
- evdev, psmouse, HID, USB HID;
- Xorg input dependencies must be validated against VMID132/Trixie and VMID135
  logs.

Container/Flatpak:

- bridge, veth, tun;
- nftables/netfilter/NAT modules used by Podman;
- fuse, cuse, virtiofs for Flatpak document portal and filesystem handoff.

USB thumbdrive / dead-tower hardware boot:

- usbcore, xhci/ehci/uhci host controllers;
- usb-storage and UAS;
- sd/scsi stack;
- FAT/exFAT if installer media or recovery handoff needs it;
- ext4 for install target;
- likely realtek/intel NIC families beyond the VM set;
- firmware package strategy is still a separate contract.

## Validation gates

Before publishing `KernelModules`:

1. For each selected tier, `find /System/Drivers/<krel> -name '<module>.ko*'`
   must find required payloads.
2. `modprobe --dry-run` is useful when available, but the package must also
   stat the files because VMID135 proved indexes alone are not enough.
3. If `modules.dep` mentions a selected module and the file is absent, the build
   must fail.
4. For Flatpak desktop images, `modprobe fuse` and `cat /proc/filesystems |
   grep fuse` are required runtime checks.
5. For Podman images, `modprobe overlay`, `modprobe br_netfilter`, and `podman
   info` are required runtime checks.

## Implementation status

- `scripts/package-auzix-kernel-modules.sh` now includes `fuse`, `cuse`, and
  `virtiofs` in the container/desktop module tier.
- The same script hard-fails if `fuse.ko` is not copied when that tier is
  enabled.
- `Kmod` must be installed for desktop/container hosts, and Debian intake now
  exports `sbin` commands such as `modprobe` into AUZiX compatibility paths.

Next pass: rebuild `KernelModules` from the same kernel package used by VMID135
or the next installer kernel, then install it on VMID135 and validate Flatpak
document portal and Podman networking.
