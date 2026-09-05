# AX-012/task65 — prove-factory r3 after protocol recovery

September 5, 2026 16:36 PDT, before lab run. Source `4fae578` already on
the r730 git remote. Local units 86 OK. Compare against r2 `016a920`
(181→179 findings, 35 holds).

- Pipeline: `auzix-release-container-validate`
- Mode: `apk-alpha-prove-factory`
- Run ID: `20260905-intake-validate-r3`
- Method: `bkc-cli trigger-pipeline` on OpenStack `bkc-alt` via lab SSH
- Output: `/var/lib/auzix-build/package-proof/AX-012-4fae57852e38`
- Protected: VM145, HDD, r2 proof `AX-012-016a920bda62`

Acceptance: conversion completes, `validation-boundary.json` exists,
report finding delta vs r2. Install/HDD remain untested.

Outcome: BKC `5daa57c8` completed-with-review. Four newly verified vs the
dcbcdda baseline: AcpiSupportBase, Bubblewrap, DBusSystemBusCommon,
DebianArchiveKeyring. Findings 181→171. Held 35→31. r2 was 179 findings
and 35 holds. Remaining families: DPKG_ROOT, systemctl/service,
dpkg-helper, invoke-rc.d leftovers. Install/HDD not tested.
