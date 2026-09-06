# AX-012/task65 — prove-factory r7 convert-or-strip

September 5, 2026 17:42 PDT, before lab run. Local units 94 OK. Theory:
Debian maintainer scripts are dpkg-db logic. apk has its own db. Convert
a real path/service effect, or strip the dpkg/debconf question. Classic
`/usr` `/bin` leftovers become Compatibility/Libraries except
`debconf/confmodule`, which is stripped not rewritten.

Same held-set lane: select `needs-review` from `AX-012-dcbcdda180fb`.
Compare this cut against r6 `AX-012-732a2d4b318e` (22 holds, 61 findings).

- Pipeline: `auzix-release-container-validate`
- Mode: `apk-alpha-prove-factory`
- Run ID: `20260905-intake-validate-r7`
- Method: `bkc-cli trigger-pipeline` on OpenStack `bkc-alt` via lab SSH
- Output: `/var/lib/auzix-build/package-proof/AX-012-<source12>`
- Protected: VM145, HDD, r6 proof `AX-012-732a2d4b318e`

Rollback: leave the new proof directory; do not reuse this run ID.
Acceptance: conversion completes, `validation-boundary.json` exists,
report hold/finding delta vs r6 and whether leftover `dpkg-query` /
confmodule rows converted or stripped. Install/HDD remain untested.

Outcome: BKC `7986f70b` completed-with-review. Proof
`/var/lib/auzix-build/package-proof/AX-012-ff8a8071363c`.
Log `apk-alpha-20260905-intake-validate-r7-resume-ff8a8071363c.log`.
Vs r6: holds 22→17, findings 61→40, unmapped-path 22→1, debconf 6→3.
Newly ready: DBus, Gzip, Python313, SgmlBase, XMLCore. No regressions.
DBus component-passed. Remaining unmapped-path is `/bin/systemctl`.
Leftover debconf is `ucf`/`ucfr`. Three new `shell-syntax` rows.
Install/HDD not tested.
