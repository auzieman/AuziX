# AX-012/task65 — prove-factory r5 service/trigger template

September 5, 2026 16:54 PDT, before lab run. Local units 89 OK. Template
imports Debian `interest /path` as `--apk-trigger` and generated
enable/reload as `/Services/<name>/run`. Compare against r4
`AX-012-cbcdcc05f369` (30 holds, 100 findings).

This is the same held-set lane, not a new HDD and not a 117-package
rebuild. The script still selects `needs-review` names from
`AX-012-dcbcdda180fb` and converts those inputs.

- Pipeline: `auzix-release-container-validate`
- Mode: `apk-alpha-prove-factory`
- Run ID: `20260905-intake-validate-r5`
- Method: `bkc-cli trigger-pipeline` on OpenStack `bkc-alt` via lab SSH
- Output: `/var/lib/auzix-build/package-proof/AX-012-<source12>`
- Protected: VM145, HDD, r4 proof `AX-012-cbcdcc05f369`

Rollback: leave the new proof directory; do not reuse this run ID.
Acceptance: conversion completes, `validation-boundary.json` exists,
report finding/hold delta vs r4. Install/HDD remain untested.

Outcome: BKC `c6ded1e7` completed-with-review. Proof
`/var/lib/auzix-build/package-proof/AX-012-3dee50cce1c6`.
Log `apk-alpha-20260905-intake-validate-r5-resume-3dee50cce1c6.log`.
Vs r4: holds 30→28, findings 100→95. Newly ready this cut: Appstream,
XdgDesktopPortal. Vs dcbcdda baseline: 181→95, seven passed
(r3/r4 four + Fprintd + those two).

Ntfs3g remains one leftover file, not an AuziX helper:

`/Programs/Ntfs3g/1-2022.10.3-5+deb13u2/Metadata/debian-control-dir/triggers`

```
# Triggers added by dh_installinitramfs/13.24.2
activate-noawait update-initramfs
```

Recognized as `initramfs-trigger`, still `needs-review` because we do
not have `update-initramfs`. Kind-count rows (`dpkg-helper`,
`DPKG_ROOT`) are leftover Debian tokens in donor scripts, not objects
we own. Install/HDD not tested.
