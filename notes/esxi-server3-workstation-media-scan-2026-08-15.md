# Server3 ESXi workstation/media scan — 2026-08-15

Purpose: prepare ESXi as an AUZiX graphical workstation/media validation lane,
especially for video/input/audio behavior that is awkward through the current
Proxmox/noVNC path.

## Observed host

- SSH alias: `lab-esxi`
- Management IP: `10.20.0.114`
- Hypervisor: VMware ESXi 8.0.3 build-24677879
- Platform: Dell PowerEdge R630
- CPU: 2 packages, 24 cores, 48 threads, hyperthreading active
- Memory: 68,621,197,312 bytes
- Management vmkernel: `vmk0`, DHCP, `10.20.0.114/24`, gateway `10.20.0.9`
- vSwitch: `vSwitch0`
- Portgroups: `VM Network`, `Management Network`
- Datastore: `datastore1`, VMFS-6, about 3.46 TB total and 3.33 TB free at scan time

## Existing VMs

- `bkc-trixie-base`
- `esxi-swarm-mgr-01`
- `esxi-swarm-mgr-02`
- `esxi-swarm-worker-01`
- `esxi-swarm-worker-02`
- `esxi-swarm-worker-03`

## AUZiX changes made before graphical re-spin

- Added `vmw_pvscsi` to the ISO initramfs storage/network module attempt list.
- Added VMware SVGA/DRM detection in live desktop staging:
  - PCI vendor `0x15ad` now attempts `vmwgfx`.
- Added `profiles/hypervisors/esxi-workstation-media.profile.json` as the
  validation contract for this lane.

## Validation intent

This lane is not tiny-netinstall acceptance. It is post-install/media proof:

1. Boot AUZiX graphical ISO on ESXi.
2. Confirm DHCP/SSH recovery.
3. Confirm keyboard/mouse input.
4. Confirm X11/LightDM/Enlightenment behavior.
5. Confirm VMware video path and resolution changes.
6. Confirm audio device exposure when ESXi VM hardware provides HDA audio.
7. Run filmable apps: browser, native Office, Flatpak editor/browser, media
   player, and Podman demo services.

## Build run started

- Run id: `esxi-graphical-20260815T221503Z`
- ISO name: `auzix-live-esxi-graphical-esxi-graphical-20260815T221503Z.iso`
- Worker: `r730-ai-01`
- Source root: `/mnt/ns1/AuziX/src`
- Build target: `strict-all`

