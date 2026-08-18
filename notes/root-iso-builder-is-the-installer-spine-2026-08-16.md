# Root ISO builder is the installer spine — 2026-08-16

The AUZiX live/root ISO builder is the source of truth for bootable root
assembly.  Do not maintain a second, ad hoc disk-install universe.

## Canonical flow

Use the existing build spine:

1. `scripts/build-auzix-root-from-profile.sh`
2. `scripts/add-auzix-live-tools.sh`
3. `scripts/build-auzix-boot-iso.sh`
4. `scripts/run-auzix-live-build-r730.sh` for full lab builds
5. `scripts/run-auzix-live-assemble-r730.sh` only for thin, approved deltas
   against a known-good baseline root

The live CD is the proving ground.  A disk install should receive the same
root contract the ISO builder creates: permissions, ownerships, setuid bits,
runtime services, SSH access, display/session setup, compatibility symlinks,
and package finalization.

## What went wrong in the ESXi disk-install loop

The installed target was finalized while mounted at `/Work/InstallTarget`.
Some generated compatibility symlinks pointed at the mount path itself, e.g.

```text
/System/Compatibility/bin/sh -> /Work/InstallTarget/Programs/BusyBox/current/Commands/busybox
```

That path only exists from the live installer.  After initramfs mounted the disk
and `switch_root` entered it, `/Work/InstallTarget` disappeared.  PID 1 then
failed before/around `/System/Boot/StartSequence`, causing repeated kernel
panic / half-boot symptoms.

The fix belongs in the root builder/finalizer path: when finalizing an
alternate target root, generated symlinks must be root-internal:

```text
/System/Compatibility/bin/sh -> /Programs/BusyBox/current/Commands/busybox
```

## Guardrail

If a disk install does not boot all the way:

- boot the known-good live ISO again;
- inspect enough to capture the missing builder contract;
- patch the builder/root-prep source;
- rebuild/reassemble through the R730 pipeline;
- reinstall from that artifact.

Do not spend another long session layering manual fixes into a mounted disk.
That hides builder bugs and loses the repeatable path.

