# VMID135 clean install spine checkpoint — 2026-08-14

Goal: rebuild vmid135 through package/lifecycle gates, not ad hoc desktop repair.

## What failed honestly

- `vmid135-clean-workstation-hydrate.sh` originally used `set -u`, so an ext4 preflight failure did not stop the run.
- `E2fsprogs` in the served repo had drifted to a native repack that depended on missing `Logsave`; install failed, but the old runner kept going.
- Early `Coreutils` installation polluted the live shell path/ABI surface. Several native commands then failed or stack-smashed under the current boot.
- Plain remote setup commands such as `cat`, `mkdir`, and `chmod` are unsafe on a partially hydrated host; the runner must use BusyBox explicitly for its own control plane.

## What was corrected

- Re-promoted `E2fsprogs` and `Dosfstools` from the command-suite filesystem-tools slice.
- Rebuilt the filesystem-tools slice on R730 through the intended `bkc-auzix-r730` Docker context.
- Added wrapper-level smoke validation so packages test the same AUZiX launch path they ship.
- Added BusyBox to the extended builder image and projected `/Programs/BusyBox/current/Commands/busybox` during command-suite validation.
- Published the corrected filesystem packages to ns1:
  - `E2fsprogs-1.47.2-3+b11.auzix.tar.gz`
    - sha256 `da7dd40d1ef8172ca4a50ee7b94b18462e15c409bc987c5cab3a47b20e2764cf`
  - `Dosfstools-4.2-1.2.auzix.tar.gz`
    - sha256 `1c7c68de1a2ff2861a6850e9cd762dcdd746eab777a2d889fc0451db0cd967ff`
- Overwrote vmid135's broken same-version E2fsprogs payload with the corrected package and updated installed package state.

## Proof

On vmid135:

- `auzix-pkg refresh` sees the corrected repo entry.
- `/Programs/E2fsprogs/current/Commands/mke2fs -V` works.
- `/Programs/E2fsprogs/current/Commands/mkfs.ext4 -q -F -L AUZIXTEST ...` works.
- `/Programs/E2fsprogs/current/Commands/e2fsck -fn ...` works.
- `MODE=preflight-only ./scripts/vmid135-clean-workstation-hydrate.sh` passes:
  - ext4 tooling present
  - service runtime hook present
  - DBus X11 command present
  - efreetd present
  - desktop menu paths present
  - `AuzixDesktopIntegration` is still missing and should be handled as the next package-stage item.

## Next clean layer

Do not run the full workstation hydration until:

1. `AuzixDesktopIntegration` is present and validated.
2. The hydration runner is split into explicit phases:
   - installer/storage preflight;
   - base service/session;
   - generated desktop state;
   - GUI launchers;
   - office/container/flatpak payloads.
3. Native GNU/Coreutils-style packages are delayed until the libc/loader compatibility lane is proven for the current boot or installed into a fresh target root before first boot.

This is the clean spine we should carry into the next vmid135 reinstall.
