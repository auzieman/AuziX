# AUZiX pkg-state hotfix live CD proof — 2026-08-17

Scope: tight proof of the installer/package-manager loop fix. Do not expand this note into a workstation package rebuild.

## What changed

- `auzix-pkg`/package tools now seed a transaction-level provided-state list before install.
- Base runtime packages are treated as already provided when their runtime files exist:
  - `Libc6`
  - `LibgccS1`
  - `GCC14Base`
- Dependency resolution checks the live/target installed-state during the same install wave, not only the initial cache.
- Alternate-root installs now preserve/write `System/State/packages/installed.json`.
- Low-level package extraction keeps tar ownership/modes via `tar -xzpf`.

## Built proof ISO

- Built on lab-build/R730.
- ISO: `/var/lib/auzix-build/published/auzix-live-installer-pkgstate-hotfix-20260817.iso`
- PVE copy: `/var/lib/vz/template/iso/auzix-live-installer-pkgstate-hotfix-20260817.iso`
- SHA256: `d1323b2069c4007d66615d5c7a99c167bc0db6e4076395471169e07ae9587b2c`
- Build receipt: `/var/lib/auzix-build/receipts/live-build-20260817T024010Z.receipt`

## Proofs completed

1. Baked ISO booted on VMID135.
2. `/System/Tools/auzix-install-package` in the ISO contains the installed-state writer.
3. Alternate-root package install proof succeeded:
   - package: `Dosfstools-4.2-1.2.auzix.tar.gz`
   - target: `/Work/Temp/pkg-hotfix-proof`
   - result: target `installed.json` was created and contained `Dosfstools`.
4. Live `auzix-pkg install Bubblewrap` succeeded against `http://192.168.1.10/auzix/repo`.
   - The critical signal was repeated `Dependency Libc6 already satisfied; not reinstalling`.
   - Same for `LibgccS1` and `GCC14Base`.
5. Disk-profile install was started against `/dev/sda` from the live CD.
   - It reached 193 installed packages before being stopped intentionally for the night.
   - The broad workstation profile was progressing, not looping on base runtime packages.
   - Current target state was preserved under `/Work/InstallTarget`.

## Known issue found during proof

The served repo at `http://192.168.1.10/auzix/repo` is stale/mismatched relative to the new ISO build repo for at least:

- `E2fsprogs -> E2fsprogs`
- `Parted -> Parted`

These showed as missing during profile install. Next pass should sync/publish the fresh repo or add the intended package-name aliases before declaring the disk installer done.

## Next clean step

Do not restart by debugging random desktop symptoms.

1. Sync/publish the freshly built repo from lab-build/R730 to the served repo location.
2. Convert installer JSON plan selections into `.packages` profile output inside the real EFL/backend path.
3. Re-run a smaller disk install proof first:
   - base
   - ssh/network
   - x11/lightdm/enlightenment
   - midori/terminology
4. Only after that passes, run the full workstation profile with Flatpak/Podman/LibreOffice.

