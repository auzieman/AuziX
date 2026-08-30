# AuziX Live Boot Contract

## Decision

AuziX live media follows the normal Linux live-media pattern. The identity of
the filesystem is AuziX; the boot mechanics are intentionally conventional and
should stay close to Debian live-build/live-boot behavior.

AUZiX begins at the init handoff. Firmware, GRUB, `vmlinuz`, kernel modules,
and the initramfs transport are ordinary Linux mechanics; do not reinvent them.
The AUZiX-specific work starts when the kernel runs `/init` and hands control
to the AUZiX root contract and `StartSequence`.

The root filesystem contract is the same whether the payload arrived from an
ISO, a dd-able HDD/USB image, a netboot staging root, or an installed disk. Media
format changes the wrapper, not the OS shape.

```text
firmware -> GRUB -> kernel + small initramfs
                     |
                    +-> mount live media read-only
                    +-> mount /live/auzix-root.squashfs read-only
                     +-> mount one tmpfs writable overlay
                     +-> switch_root to the merged AuziX root
                                      |
                                      +-> /init mounts runtime filesystems
                                      +-> StartSequence starts declared services
                                      +-> display manager / GUI is an explicit stage
```

The live medium must not expose the whole `AuzixRoot` tree as its operational
root. That makes mutations depend on accidental mount order and produces
exactly the permissions/state split seen in prior Midori, graphics, DNS, and
profile work.

## Debian-cousin media rule

Debian is the closest upstream cousin for the current AUZiX builder, so USB/HDD
media should mirror Debian's boring live-build shape before we add AUZiX twists:

```text
lb config -b hdd          # Debian concept: bootable HDD/USB-style image
firmware -> GRUB/syslinux -> kernel + initramfs
live media partition -> /live/<rootfs image>
live-boot/initramfs scans labels and partition devices, not just CD-ROMs
```

AUZiX may keep its own package layout and `/System`/`/Programs` root contract,
but the media lifecycle should remain equivalent:

1. build or select a package-composed AUZiX root;
2. create `/boot` and `/live/auzix-root.squashfs`;
3. create a raw disk image with BIOS, EFI, and `AUZIXLIVE` partitions;
4. mount the image read-write as a loop device;
5. copy the already-assembled boot/live tree into the live partition;
6. install BIOS and UEFI GRUB;
7. sync, unmount, detach, checksum;
8. QEMU/PVE/ESXi boot smoke before publication.

The raw-image path must not run an ISO packaging detour (`grub-mkrescue` /
`xorriso`) merely to get a boot tree. If the ISO builder is reused, it must be
used only in an `assemble boot tree` mode. This is the same split Debian makes
between composing a live root and choosing a binary image type.

Concrete Debian references inspected on the Trixie lab-build host:

- `/usr/lib/live/build/binary_hdd`
  - validates host/chroot tools up front (`parted`, `losetup`, `mtools`,
    filesystem tools, bootloader tools);
  - sizes the image from `du` when `LB_HDD_SIZE=auto`;
  - creates a sparse `binary.img`;
  - uses `losetup`, `parted`, `mkfs`, `mount`;
  - copies the finished `binary/` tree into the mounted image;
  - installs the selected bootloader;
  - unmounts, detaches, timestamps, and publishes the `.img`.
- `/usr/lib/live/build/binary_rootfs`
  - creates the rootfs image separately from the final media wrapper.
- `/lib/live/boot/9990-main.sh` and `/lib/live/boot/9990-misc-helpers.sh`
  - scan local block devices for live media through helper functions;
  - probe filesystem types;
  - support labels, `findiso`, persistence, and partition devices;
  - avoid a narrow CD-ROM-only probe path.

AUZiX should copy this architecture, not the exact paths: first compose a
`binary/`-equivalent tree containing `/boot`, `/live/auzix-root.squashfs`, and
`.disk`/receipt metadata; then run a small HDD-image wrapper that only performs
image sizing, partitioning, filesystem creation, copy, bootloader installation,
checksum, and smoke boot.

The AUZiX builder image must carry these Debian tools too, not merely the
current lab-build host. Otherwise a later clean builder rebuild can silently
lose the reference implementation and push us back into ad-hoc image assembly.
Required builder packages include:

```text
live-build live-boot live-config parted fdisk mount dosfstools mtools
grub-pc-bin grub-efi-amd64-bin squashfs-tools xorriso
```

The pipeline-facing runner should expose the media decision explicitly:

```text
AUZIX_MEDIA_KIND=iso       # legacy/live ISO validation path
AUZIX_MEDIA_KIND=hdd-img   # Debian-style dd-able USB/HDD image path
```

Both modes consume the same package-composed AUZiX root and the same boot/live
payload contracts. The difference is only the final binary media wrapper.

Device discovery must include both labels and partition devices:

```text
/dev/disk/by-label/AUZIXLIVE
/dev/vda3 /dev/vda2
/dev/sda3 /dev/sda2
/dev/sdb3 /dev/sdb2
/dev/xvda3 /dev/xvda2
/dev/nvme0n1p3 /dev/nvme0n1p2
```

Whole-disk probes are fallbacks only. A dd-able HDD/USB image normally stores
`/live/auzix-root.squashfs` on a partition, not on the whole disk node.

## Writable live state

The merged root is writable through **one** overlay. Runtime-owned paths are
then explicit contracts, not a collection of late boot repairs:

| Path | Owner/purpose | Live backing |
| --- | --- | --- |
| `/run` | processes, sockets, XDG runtime | tmpfs |
| `/tmp`, `/var/tmp` | temporary work | tmpfs |
| `/Users` | user profiles, browser state | overlay |
| `/Work` | user/operator workspace | overlay |
| `/System/State` | service/package runtime state | overlay |
| `/System/Logs` | bounded live diagnostics | overlay/tmpfs policy |
| `/Network/DNS` | DHCP receipt and resolver state | overlay/runtime link |

`/System/Settings` remains package-owned and effectively immutable during a
normal live boot. A service needing mutable configuration writes under
`/System/State/<service>` or the user profile—not into the ISO-origin settings
tree.

If the writable overlay cannot be mounted, boot must stop. A read-only bind
fallback can render a desktop, then fail later when Midori, DBus, or the
desktop first writes session state.

## Browser and graphics rules

- The desktop starts only after the writable-state contract and network receipt
  have passed.
- Midori owns its profile below `/Users/auzix`; its bundle/library closure,
  CA bundle, and GTK/X11 dependencies remain read-only package assets.
- DNS is published once through the live runtime resolver path; browser wrappers
  consume that path instead of each creating or copying resolver files.
- A serial/TTY shell remains available for evidence collection, but it is a
  diagnostic companion to the graphical boot—not a substitute for it.

## Operator access and desktop acceptance

SSH, serial/TTY, and the live diagnostic receipt start before the graphical
stage. They must remain available when a display component fails, but they are
not the primary user experience and must not delay a healthy desktop boot.

The live desktop acceptance target is comparable to a Debian, Ubuntu, or Elive
installer session:

- a pre-seeded, VM-safe Enlightenment profile (X11/software rendering, no GL,
  Bluetooth, or optional media modules);
- networking available from the desktop session;
- a clearly visible **Install AuziX** launcher that starts the existing
  installer flow;
- optional disk tooling such as GParted only after the base graphical
  installer path is proven.

The network module is intentionally part of the minimal profile. If it cannot
reach its service/runtime socket, the receipt must identify the path,
ownership, or DBus permission defect before broader desktop features are added.

## Recovery sequence

1. Preserve `auzix-strict-desktop-20260606-r3.iso` as the visual/runtime
   reference image.
2. Produce a normal SquashFS-plus-overlay beta using the exact current strict
   root and matching kernel/modules.
3. Prove boot, DHCP/DNS, and writable profile state on disposable VM135.
4. Run Midori's package-owned runtime audit and one HTTPS smoke request.
5. Only then bring the GUI launcher and installer paths back into the default
   media flow.

No bulk package rebuild is part of this recovery. Each failed contract becomes
a package or live-root receipt with a targeted test.
