# Auzix VirtualBox Path

## Purpose

Provide a less fiddly host-side review path than raw QEMU command lines by
converting the current `Auzix` disk image into a VirtualBox-friendly `VDI`.

## Targets

Convert the current `Auzix` image:

```bash
make auzix-vdi
```

Create a VirtualBox VM around that `VDI`:

```bash
make auzix-vbox-create
```

## Scripts

- [scripts/build-auzix-vdi.sh](/home/auzieman/Projects/tabor-linux-forge/scripts/build-auzix-vdi.sh:1)
- [scripts/create-auzix-virtualbox-vm.sh](/home/auzieman/Projects/tabor-linux-forge/scripts/create-auzix-virtualbox-vm.sh:1)

## Notes

- VirtualBox does not consume QEMU command-line flags directly.
- It does work well with an existing `VDI` attached to a new VM.
- This is mainly a host-side convenience/debug path:
  - easier hardware tweaking
  - easier display setup
  - easier storage inspection

## Current Expectation

If the converted `VDI` still fails to boot, that is useful evidence that the
problem is the guest image itself, not just the QEMU command line.
