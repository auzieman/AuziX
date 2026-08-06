# Issues And Build Notes

This file is a lightweight handoff ledger. Keep entries short, factual, and
linked to a validation command or artifact when possible.

## Current Open Items

### Boot Media Contract Drift (Resolved in Builder, Recovery ISO Produced)

Observed during the August 4, 2026 review:

- The last desktop ISO artifact has only a BIOS El Torito entry; it has no
  x86_64 UEFI boot image.
- `make auzix-image` still referenced a removed legacy disk-image builder,
  while the maintained path is `make auzix-strict-iso`.
- The live initramfs could continue after a failed ISO-root mount, which made a
  failed handoff look like a vague rescue-shell hang.

Decision:

- The beta ISO now requires both BIOS and UEFI GRUB media by default, uses the
  `AUZIXLIVE` volume id, and stops in an explicit rescue shell if its live-root
  handoff fails.
- Run `scripts/validate-auzix-boot-iso.sh <iso>` before publishing media to
  Proxmox or the Mirari board.
- Treat `AUZIX_REQUIRE_UEFI=0` as a labelled diagnostic exception only.

Next evidence:

```sh
make auzix-strict-iso
./scripts/validate-auzix-boot-iso.sh artifacts/auzix/auzix-strict-shell.iso
```

Recovery evidence, August 5, 2026:

- `artifacts/auzix/auzix-strict-shell-uefi-beta.iso` passed the publication
  gate and contains both a BIOS and a UEFI El Torito entry.
- The recovered kernel is `6.1.0-48-amd64`, deliberately paired with the
  existing strict-root driver tree at `System/Drivers/6.1.0-48-amd64`.
- The ISO builder now rejects a kernel path underneath its disposable work
  directory. That was the prior silent self-deletion path: the builder clears
  its work directory before it copies the kernel into the image.

Do not return to a bulk `strict-all` rebuild to repair one package. Advance
one package receipt at a time through: source/build contract -> runtime audit
-> strict root -> container smoke -> ISO -> disposable VM.

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

### SquashFS Live-Root Module Receipt Is Incomplete

Observed:

- `modules.dep` for `6.1.0-48-amd64` advertises
  `kernel/fs/squashfs/squashfs.ko`.
- The strict root and the packaged `KernelModules-6.1.0-48-amd64` archive do
  not contain that module.
- The normal live-ISO layout requires SquashFS, so a build must fail before
  publishing until the module receipt is repaired.

Impact:

- A raw ISO-root layout can conceal the missing module, but the conventional
  SquashFS-plus-overlay boot contract cannot and should not bypass it.

Next evidence:

```sh
find out/auzix-strict/AuzixRoot/System/Drivers/6.1.0-48-amd64 \
  -name 'squashfs.ko*'
```

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
