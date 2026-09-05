# AX-012/task65 — prove-factory r2 after rewrite split

September 5, 2026 16:19 PDT, before lab run. Source `016a920` already on
the r730 git remote. Local `unittest discover` is green. This is the
planned follow-up to the 0.4s `95000cc` fail.

- Pipeline: `auzix-release-container-validate`
- Mode: `apk-alpha-prove-factory`
- Run ID: `20260905-intake-validate-r2`
- Method: `bkc-cli trigger-pipeline` on OpenStack `bkc-alt` via lab SSH
- Output: `/var/lib/auzix-build/package-proof/AX-012-016a920bda62`
- Protected: VM145, R8/R10, HDD lane, leftover `AX-012-95000ccdab58`

Laptop stays git. Lab runs BKC. Rollback: leave the new proof directory.
Acceptance: conversion completes, `validation-boundary.json` exists,
install/HDD remain untested.

Outcome: BKC `05461cd9` completed. Trixie units passed. Conversion
`completed-with-review`. 35 still `needs-review`. Findings 181 → 179
(DBus 12→11, DBusSystemBusCommon 2→1). D-Bus helper component passed.
`newly_verified` empty. `validation-boundary.json` written. Install/HDD
not tested.
