# AUZiX quickroot alpha smoke — 2026-08-23

## Scope

This run is a Black Knight style quick install / stability mule, not the public
tiny installer.

Goal:

- boot media / existing live spine as control plane;
- one large writable root disk;
- package-composed graphical AUZiX root laid onto disk;
- validate that the runtime substrate, loader paths, and desktop spine survive
outside squash/live overlay mode.

Non-goals:

- sub-GB installer media;
- public beta artifact;
- package-selection UI proof;
- ESXi/QEMU raw compatibility proof.

## Target ladder

Primary proof target:

- Proxmox/PVE VM. This is the main lab target for now.

Secondary proof target:

- VMware Workstation / ESXi. Useful for video/input/autodetection maturity.

Deferred/manual sanity target:

- VirtualBox. Useful later as a consumer-ish compatibility check, but not a
  priority while it slows the workstation.

Raw QEMU is a builder/debug smoke tool only. Most users and most geeks will not
operate AUZiX through raw QEMU, so QEMU should not be treated as the primary
acceptance target.

## Artifact

Built on lab-build/R730:

```text
/root/auzix-work/AuziX/artifacts/auzix/quickroot-20260824T004617Z.img
```

Properties:

- raw disk image: 32G;
- sparse host usage on R730: about 4.4G;
- installed root free space after build: about 26G;
- full raw stream into PVE local-lvm expands sparse holes and allocates the full
  virtual disk.

Do not publish this as the normal download. If published at all, label it as a
fat alpha / lab preview.

## Important runtime changes included

`AuzixPackageTools` was rebuilt with a stricter runtime linker lifecycle:

- write AUZiX `ld.so.conf` before `ldconfig`;
- global loader cache is limited to active runtime substrate paths;
- leaf package-local `/Programs/*/current/RootFS` libraries stay out of the
  global loader cache;
- leaf installs must not replace libc/core runtime paths or linker config/cache.

This directly addresses the libc/loader breakage seen when installing packages
into the live graphical root.

## Build notes

Build used:

```text
AUZIX_IMG_SIZE=32768M
AUZIX_LINK_MODE=compat
AUZIX_LEGACY_POLICY=compat
AUZIX_INCLUDE_OPENSSH=0
AUZIX_LIVE_CURRENT_ONLY=1
AUZIX_SKIP_EFL_INSTALLER=1
AUZIX_SKIP_INSTALLER_TESTS=1
AUZIX_SKIP_LIVE_AGENT_VALIDATION=1
```

The EFL installer/package-manager were skipped because their disposable EFL
builder/header lane was not ready. The shell/TUI installer spine and package
tools are present.

OpenSSH was intentionally excluded. BusyBox/dropbear/rescue access needs a
separate proof on the HDD path.

## PVE VM142 state

VM:

```text
VMID: 142
Name: Auzix-PVE-Control-142
Boot: scsi0;ide2;net0
Disk: local-lvm:vm-142-disk-0,size=32G
CPU/RAM: 8 vCPU, about 12.6G RAM
NIC: e1000, MAC 46:85:5A:C8:3E:53, bridge vmbr0
```

After disk stream and first boot:

- GRUB/kernel/init reached AUZiX `StartSequence`;
- serial showed display startup;
- X appeared after a long delay, so do not call the HDD path dead too quickly;
- SSH was not listening, expected-ish because OpenSSH was excluded and the HDD
  rescue SSH path still needs proof;
- PVE host resources were acceptable: memory available, light swap, VM process
  active rather than wedged.

## Lessons

- The fat-root image is useful for installed-root stability, but it is not the
  public installer story.
- Streaming a sparse 32G image through `dd` into LVM thin allocates the whole
  virtual disk. Next iteration should use a sparse-aware import path such as
  `qemu-img convert`, bmap-style copy, or a smaller generated image.
- PVE and VMware/ESXi are the right near-term compatibility targets.
- Debian live-media hardware autodetection is still worth mining, especially for
  Xorg/input/video setup, but the immediate package-manager issue is the
  libc/loader/ldconfig/substrate boundary.

## Late smoke: desktop/menu failure

VM142 booted the first quickroot image far enough to show X/E, but it is not a
desktop pass:

- menus were effectively busted;
- installer launcher did not launch from the desktop;
- terminal launchers were dead or missing from the usable menu surface;
- SSH/tcp22 refused connections, so rescue remained console-only.

The root probe showed the spine payload mostly existed, but the HDD image path
was copying a filesystem and seeding receipts without running the installed-root
finalize/configure stage afterward. That made the HDD image diverge from the
known-good live-root pattern.

Patch direction applied:

- `build-auzix-live-disk-image.sh` now chroots into the target root and runs
  `/System/Tools/finalize-installed-root /`;
- it then runs `AuzixDesktopIntegration` activation/sync when present;
- it refreshes the AUZiX runtime linker cache through `auzix-pkg refresh-ldcache`;
- it records `System/Logs/packages/desktop-launcher-probe-build.txt`;
- `AuzixDesktopIntegration` now writes the E menu file to both
  `/etc/xdg/menus/e-applications.menu` and
  `/System/Settings/xdg/menus/e-applications.menu`.
