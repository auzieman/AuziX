# AX-012/task65 — intake validate before HDD

September 5, 2026 16:09 PDT, before lab run. VM145 stays diagnostic. HDD
stays locked. This run only converts the held set and writes a validation
boundary.

- Pipeline: `auzix-release-container-validate`
- Mode: `apk-alpha-prove-factory`
- Run ID: `20260905-intake-validate`
- Method: `bkc-cli trigger-pipeline` on OpenStack `bkc-alt`
- Output: `/var/lib/auzix-build/package-proof/AX-012-<source12>`
- Protected: VM145, existing R8/R10, healthy r730 containers, HDD lane

Rollback: leave the new proof directory; do not reuse its run ID.
Acceptance: conversion completes (`passed` or `completed-with-review`),
`validation-boundary.json` exists, install/HDD remain untested.

Outcome: BKC `56cb1604-a763-4f4c-a6d7-dbf0ac83735a` queued. R730 stopped
in `python3 -m unittest discover` (81 tests, 3 failed) before conversion.
Failures: constant-false debconf, package-owned usr rewrite, python runtime
cache — all `ready` vs expected `needs-review`. Log
`/var/lib/auzix-build/receipts/apk-alpha-20260905-intake-validate-resume-95000ccdab58.log`.
HDD still locked.
