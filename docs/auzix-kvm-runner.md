# Auzix KVM Runner

## Purpose

Provide a stable local launch command for early `Auzix` x86_64 images.

This runner is intentionally biased toward:

- shell-first bring-up
- serial console visibility
- simple virtio devices
- KVM when available, TCG fallback when it is not

## Script

Use:

```bash
./scripts/run-auzix-kvm.sh
```

Default image lookup:

1. `artifacts/auzix/auzix.qcow2`
2. `artifacts/auzix/auzix.img`
3. `artifacts/auzix/auzix.raw`

Or pass an explicit image path:

```bash
./scripts/run-auzix-kvm.sh artifacts/auzix/auzix-shell.img
```

## Defaults

- machine: `q35`
- acceleration: `kvm:tcg`
- memory: `2048` MiB
- cpus: `2`
- network: user-mode NAT
- SSH port forward: `localhost:2222 -> guest:22`
- console: serial on stdio

## Environment Overrides

```bash
AUZIX_MEMORY_MB=4096
AUZIX_CPUS=4
AUZIX_SSH_PORT=2223
AUZIX_HEADLESS=0
AUZIX_QEMU_APPEND="-boot menu=on"
```

## Notes

- If `/dev/kvm` is not available, the script still runs and QEMU falls back to
  software emulation.
- The runner assumes a whole-disk image, not a bare kernel/initramfs pair.
- Headless mode is the default because it fits the shell-first bootstrap phase
  and keeps debugging simple.
