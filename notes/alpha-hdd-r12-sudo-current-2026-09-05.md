# AX-012/task65 — HDD r12 failed after passwd on Sudo/current

September 5, 2026 20:28 PDT. BKC `a5eae325` failed `rc=1`. VM145
untouched. VM146 not created. No disk image. r730 KVM/virsh idle.

## What passed

Stager `521f14f` wrote regular files:

`/etc/passwd` and `/System/Settings/passwd` are both 1177-byte regular
files. `alpha-hdd-stage: PASS` for unlock-r11
`sha256:372909481e60db52cd10015fb867a4859fa79ca1e4a3ac47aca29d4ad3250d8e`.

## What failed

`validate-auzix-alpha-final-root.sh` then required
`/Programs/Sudo/current/Commands/sudo`. The APK payload is
`/Programs/Sudo/host/Commands/sudo` (setuid, present). Same on VM145:
`host/Commands/sudo`, no `current`. Other host-only trees in this root:
DBus, LightDM, Terminology, Udev, Xorg.

Not a missing sudo package. Not a KVM/PVE failure. The HDD script never
reached image write or boot. Live-tools already chmod the host sudo
path.

## Next

Keep proof on r730 (KVM is available there). Do not attach anything to
145 or 146 until the validator matches the host/`current` publication
that VM145 already runs. Park this failed work dir before the same
`hdd_id` retry.

Kanboard task65 comment sync pending.
