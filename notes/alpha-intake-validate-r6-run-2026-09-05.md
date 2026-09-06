# AX-012/task65 — prove-factory r6 needed-step wrap

September 5, 2026 17:12 PDT, before lab run. Local units 92 OK. Leftover
Debian steps wrap as `auzix_needed_step` (list/rename/own/named) so hooks
do not call missing `dpkg-*` and intake does not throw. Also keep
`was-enabled 'unit'; then` as `if true; then`.

Same held-set lane as r2–r5: select `needs-review` names from
`AX-012-dcbcdda180fb`. Compare this cut against r5
`AX-012-3dee50cce1c6` (28 holds, 95 findings). HDD 117 BML is not this
run; see `notes/alpha-hdd-bml-r6-2026-09-05.md`.

- Pipeline: `auzix-release-container-validate`
- Mode: `apk-alpha-prove-factory`
- Run ID: `20260905-intake-validate-r6`
- Method: `bkc-cli trigger-pipeline` on OpenStack `bkc-alt` via lab SSH
- Output: `/var/lib/auzix-build/package-proof/AX-012-<source12>`
- Protected: VM145, HDD, r5 proof `AX-012-3dee50cce1c6`

Rollback: leave the new proof directory; do not reuse this run ID.
Acceptance: conversion completes, `validation-boundary.json` exists,
report hold/finding delta vs r5 and whether rendered hooks are path or
order steps rather than leftover `dpkg-*`. Install/HDD remain untested.

Outcome: BKC `48302007` completed-with-review. Proof
`/var/lib/auzix-build/package-proof/AX-012-732a2d4b318e`.
Log `apk-alpha-20260905-intake-validate-r6-resume-732a2d4b318e.log`.
Vs r5: holds 28→22, findings 95→61, `dpkg-helper` 23→0, `shell-syntax`
5→0. Newly ready: LibnssSystemd, Libopenni20, Librsvg2Common, Luit,
Ntfs3g, Udisks2. No regressions. Kanboard task65 comment posted.

Realistic this cut: Ntfs3g `named update-initramfs`; Udisks2
`/Services/udisks2/run` and `if true; then`; Luit/Libopenni own-path
or usrmerge-not-applicable. Weaker: LibnssSystemd `own` ate leftover
`dpkg-query` INSTCOUNT lines; Librsvg `trigger` on a gdk-pixbuf path
is a no-op. Remaining 22 holds are other families (`unmapped-path`,
`DPKG_ROOT`, debconf, accounts). Install/HDD not tested.
