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

### VM135 Installed-System Validation (Supersedes Prior Hang Note)

Validated August 6/7, 2026:

- VM135 boots the installed AUZiX root and is reachable at `192.168.1.60`.
- `auzix-pkg refresh` reads 110 packages from the public repository.
- ext4 tooling and the rootful Podman runtime pass functional tests.
- AUZiX BusyBox and Nginx images plus upstream Alpine execute successfully.
- Rootless initialization passes; rootless unpack awaits Uidmap.
- Netavark bridge creation fails because the active module tree omits bridge,
  veth, and netfilter modules.

See `docs/2026-08-06-vm135-podman-proving-ground.md` for commands, decisions,
and remaining release gates.

### VM135 Does Not Complete ACPI Shutdown

Observed during the August 6/7 nightly shutdown:

- AUZiX containers stopped cleanly and the guest filesystem was synced.
- `qm shutdown 135 --timeout 60` left VM135 running.
- `qm stop 135 --timeout 30` was required and completed successfully.

Next evidence:

- verify the Lua/init service path handles the QEMU ACPI power-button event;
- confirm the next installed image can power off from both the guest command
  path and Proxmox `qm shutdown` before filming or unattended lab operation.

### VM135 Flatpak App Proof And Shortcut Contract

Validated August 7, 2026:

- `CACerts` ports Debian `ca-certificates` into the AUZiX trust-store
  contract and fixes Flatpak/Flathub TLS.
- `GnuPG` provides `gpg`, `gpgconf`, `gpg-agent`, `gpgsm`, and `gpgv` through
  `/Programs/GnuPG/current/Commands`, fixing Flatpak's GPGME engine setup.
- VM135 can search Flathub, install Flatpak runtimes, and install apps from
  Flathub.
- Installed proof apps:
  - `io.github.zyedidia.micro` / Micro Text Editor `2.0.15`
  - `io.github.kolunmi.Bazaar` / Bazaar `0.9.2`
- `MicroFlatpakAdapter` and `BazaarFlatpakAdapter` expose short AUZiX commands:
  - `/Programs/Micro/current/Commands/micro`
  - `/Programs/Bazaar/current/Commands/bazaar`
- `FlatpakRuntimeSupport` changes `/var` from a top-level symlink into a real
  alias directory with children such as `/var/lib -> /System/State/lib`.
  Bubblewrap refuses a top-level `/var` symlink, but accepts the alias-directory
  shape.

Evidence:

```sh
sudo auzix-pkg install CACerts GnuPG FlatpakRuntimeSupport \
  MicroFlatpakAdapter BazaarFlatpakAdapter
/Programs/Micro/current/Commands/micro --version
/Programs/Bazaar/current/Commands/bazaar --help
```

Observed:

- `micro --version` works over SSH after `FlatpakRuntimeSupport`.
- Bazaar gets past Bubblewrap and stops only at the expected SSH-session GUI
  boundary: no active display.

Next package-factory rule:

- Add a scanner that reads installed Flatpak refs and exports them as AUZiX
  adapter recipes/packages. Users should get `/Programs/<App>/current/Commands`
  launchers and optional `/System/Compatibility/bin` links, not reverse-DNS
  commands like `flatpak run io.github.zyedidia.micro`.
- The scanner should read Flatpak metadata (`command=...`, app id, version,
  runtime, desktop file/appdata when present), produce
  `auzix-flatpak-adapter-v1` recipes, and rebuild the package repository.

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
