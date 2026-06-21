# Issues And Build Notes

This file is a lightweight handoff ledger. Keep entries short, factual, and
linked to a validation command or artifact when possible.

## Current Open Items

### VM135 Live ISO Appears Hung

Observed on June 21, 2026:

- Proxmox reports VM135 as `running`.
- Boot order is ISO first: `ide2;scsi0;net0`.
- VM135 MAC is `56:81:B6:4E:FD:36`.
- Proxmox neighbor table only shows IPv6 link-local for that MAC:
  `fe80::5481:b6ff:fe4e:fd36`.
- No confirmed DHCP IPv4 address was observed.
- QEMU process was alive with low CPU usage and no disk writes.

Interpretation: the guest booted far enough to initialize the virtual NIC, but
this is not a healthy installer validation state.

Next useful evidence:

```sh
qm status 135 --verbose
qm config 135
ip neigh show | grep -i 56:81:B6:4E:FD:36
```

If graphical console access is available, capture whether the hang is before
Enlightenment, during the first-run/config path, or after installer autostart.

### Package Runtime Audit Is Noisy

The first local audit-only `make auzix-core-validation` run produced:

```text
strict-root failures: 0
package-runtime failures: 77
warnings: 315
package receipts: 31
executables: 358
```

Interpretation: the root layout contract is currently cleaner than the package
runtime/linker contract. Fix package receipts and build-time path adaptation
before adding more boot repair logic.

## Note Format

Use this shape for new entries:

```text
### Short Title

Observed:
- concrete facts

Impact:
- why it matters

Next evidence:
- command or artifact path

Likely owner:
- package contract, boot sequence, ISO media, BKC pipeline, or VM target
```
