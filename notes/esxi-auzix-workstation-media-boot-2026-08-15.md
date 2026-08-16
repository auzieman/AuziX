# AUZiX ESXi workstation media boot — 2026-08-15

Test VM:

- ESXi host: `lab-esxi` / `10.20.0.114`
- VM name: `auzix-esxi-workstation-media-01`
- ESXi VMID: `13`
- Shape: 8 vCPU, 16 GiB RAM, 250 GiB thin SATA disk
- Network: `vmxnet3` on `VM Network`
- ISO: `auzix-live-esxi-graphical-esxi-graphical-20260815T221503Z.iso`
- ISO SHA256: `af8599636679b931faaac2301898af89d78b950266e7c0738dfdd289c89dd1e8`
- Serial log: `/vmfs/volumes/datastore1/auzix-esxi-workstation-media-01/serial.log`

## Passes

- EFI VM registered and powered on.
- AUZiX kernel booted.
- SATA disk detected as `/dev/sda`, 250 GiB.
- ISO CD detected as VMware SATA CD.
- `vmxnet3` loaded and linked at 10Gb.
- DHCP succeeded:
  - IP: `10.20.0.113/24`
  - MAC: `00:0c:29:f8:91:d9`
- SSH came up on port 22 after StartSequence completed.
- Serial rescue shell on `ttyS0` worked.
- VMware VMMouse input devices were detected.
- DBus system bus started.
- PulseAudio user session was attempted/started, but no sound device was exposed by this VM hardware.

## Current failure

Xorg fails with:

```text
(EE) open /dev/dri/card0: No such file or directory
(EE) Device(s) detected, but none match those in the config file.
(EE) no screens found
```

ESXi exposes VMware SVGA:

```text
0000:00:0f.0 vendor=0x15ad device=0x0405 class=0x030000
```

AUZiX loaded DRM helper modules but did not have `vmwgfx` packaged under
`/System/Drivers/6.1.0-52-amd64`, so no `/dev/dri/card0` appeared.

## Second pass: vmwgfx ISO

Rebuilt and staged:

- ISO: `auzix-live-esxi-vmwgfx-esxi-vmwgfx-20260815T222729Z.iso`
- ISO SHA256: `8e34ae4d3e7d30b0785f3e2dae6e2cb8cd060215705d3039db0bbde4b58bb418`
- ESXi datastore path:
  `/vmfs/volumes/datastore1/auzix-isos/auzix-live-esxi-vmwgfx-esxi-vmwgfx-20260815T222729Z.iso`

Result:

- `vmwgfx` loaded.
- `vmxnet3` loaded.
- `/dev/dri/card0` and `/dev/dri/renderD128` appeared.
- Xorg started with the `modeset` driver on VMware SVGA.
- Enlightenment reached `MAIN LOOP AT LAST`.
- Xorg selected `1920x1080` on `Virtual-1`.

Evidence:

```text
vmwgfx 372736 1 - Live
drm_ttm_helper 16384 1 vmwgfx
ttm 94208 2 vmwgfx,drm_ttm_helper
drm_kms_helper 212992 3 vmwgfx
drm 614400 6 vmwgfx,drm_ttm_helper,ttm,drm_kms_helper
vmxnet3 73728 0 - Live

/dev/dri/card0
/dev/dri/renderD128

/Programs/Xorg/current/Commands/xinit /System/Tools/start-enlightenment-session -- /Programs/Xorg/current/Commands/Xorg :0 vt7 -keeptty -nolisten tcp -config xorg.conf
/usr/bin/enlightenment_start
/usr/bin/enlightenment
```

Live-session repair found one remaining installer/profile issue: the seeded
Enlightenment `default` profile directory could be root-owned, causing E to
fail writing `e_randr2.cfg.tmp` during display setup.  The fix belongs in the
root-side GUI handoff, before `su auzix`, not inside the user session.

Patched:

- `scripts/add-auzix-live-tools.sh`
  - normalize `/Users/auzix/.cache`, `.config`, `.local`, `.e`, and `.elementary`
    ownership and writability after `/System/Tools/prepare-livecd-state` and
    before launching the display user.

Remaining warning:

- E still logs a stale disabled `wizard` module reference:
  `No module named wizard/linux-gnu-x86_64-0.25.4/module.so`
- This did not block E startup on the vmwgfx ISO and should be cleaned from the
  seeded E profile/menu state.

Console note:

- Guest-side serial/SSH and X/E are working.
- If the ESXi browser console does not open through the lab URL, treat it as a
  lab-edge/NAT/WebMKS/VMRC path issue rather than an AUZiX boot failure.
  ESXi UI HTTPS can work while console transport still needs direct/proxied
  WebMKS and/or VMRC/TCP 902 handling.

## Fix queued in first pass

Patch `scripts/package-auzix-kernel-modules.sh` to include:

- module alias/name: `vmwgfx`
- fallback path: `kernel/drivers/gpu/drm/vmwgfx/vmwgfx.ko`

The running ISO uses Debian kernel `6.1.0-52-amd64`, so do not hot-copy a module
from a different host kernel. Rebuild the ISO/package from the matching kernel
module source.
