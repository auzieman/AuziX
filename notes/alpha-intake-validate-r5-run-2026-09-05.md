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
