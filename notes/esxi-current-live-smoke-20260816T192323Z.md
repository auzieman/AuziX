# AUZiX current-live ESXi smoke — 20260816T192323Z

Run id: `current-live-20260816T185556Z`

## Artifacts

- R730 publish dir: `/var/lib/auzix-build/published`
- Installer ISO: `auzix-live-installer-current-current-live-20260816T185556Z.iso`
- Desktop ISO: `auzix-live-desktop-current-current-live-20260816T185556Z.iso`
- ESXi datastore dir: `/vmfs/volumes/datastore1/auzix-isos`

## Pipeline wrapper

- BKC lane: `AUZiX LAB 14 — Current ISO ESXi + Repo Launch Gate`
- Review run: `1ddc8209-25ac-4549-9f92-0ba97e102252`
- Scripts added under `BlackKnightController/pipelines/auzix-current-iso-esxi-launch-gate/scripts/`.

## Boot evidence

VM: `auzix-esxi-workstation-media-01` / ESXi VMID `13`.

Both current ISOs were staged to ESXi and VMID 13 was hard-cycled through the
checked-in boot script. The serial tail showed:

- SATA disk and CD-ROM detected.
- `vmxnet3` linked at 10Gb.
- DHCP address: `10.20.0.113/24`.
- `vmwgfx` loaded and initialized VMware SVGA framebuffer.
- VMware VMMouse devices detected.
- DBus system bus started.
- Display startup reached the GUI launch handoff.

## Blockers before semi-public promotion

- `ssh tcp/22 not listening` in live boot service summary.
- `terminology` segfaults in `libeina.so.1`.
- ESXi password bootstrap can append the operator key, but key auth still fails.
  Treat this as an ESXi SSH policy/key-path blocker and keep password bootstrap
  as temporary only.
- Pipeline script should clear or rotate `serial.log` before each boot so
  installer-vs-desktop evidence is separated.

## Decision

Boot plumbing is alive, but repo/ISO payloads are not public-ready. Fix SSH
service startup and Terminology/EFL runtime before public mirror promotion.
