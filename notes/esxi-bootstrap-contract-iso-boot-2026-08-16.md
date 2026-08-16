# AUZiX ESXi bootstrap-contract ISO boot — 2026-08-16

Purpose: record the first ESXi reboot using the bootstrap/path-contract ISO
after the packaging permission/path preservation fixes.

## Artifact

- Builder: `r730-ai-01` / `lab-ai-worker`
- Published ISO:
  `/var/lib/auzix-build/publish/auzix-live-bootstrap-contract-bootstrap-contract-20260816T163120Z.iso`
- Size: 599 MiB
- SHA256:
  `0fa3648545f737a3e81820e33c6b585a259b41be4c6febdc5ae1f0a9f12d0056`
- Boot validation: `validate-auzix-boot-iso.sh` passed with BIOS and UEFI
  El Torito entries present.

## ESXi target

- Host: `lab-esxi` / `10.20.0.114`
- VM: `auzix-esxi-workstation-media-01`
- ESXi VMID: `13`
- Datastore ISO path:
  `/vmfs/volumes/datastore1/auzix-isos/auzix-live-bootstrap-contract-bootstrap-contract-20260816T163120Z.iso`

## Boot result

- VM hard powered off, CD-ROM backing changed to the new ISO, VM reloaded, and
  powered back on.
- DHCP address after boot: `10.20.0.113/24`
- SSH accepted the lab key path with an isolated temporary known-hosts file.
- Kernel/live boot evidence:
  - `vmxnet3` loaded and linked at 10Gb.
  - `vmwgfx` loaded.
  - VMware VMMouse input devices detected.
  - DBus system bus started.
  - Xorg started.
  - Enlightenment reached `MAIN LOOP AT LAST`.

## Notes

- ESXi has no `wget`/BusyBox command available in the management shell, so the
  ISO was staged via `scp` through `lab-ns1`.
- A first VMX edit accidentally touched `sata0:0.fileName`, the disk backing,
  which made the VM configuration invalid. The VMX backup was restored, then
  only `sata0:1.fileName` was changed. The VM powered on cleanly afterward.
- Keep the CD-ROM target precise: on this VM `sata0:0` is the disk and
  `sata0:1` is the ISO CD-ROM.
