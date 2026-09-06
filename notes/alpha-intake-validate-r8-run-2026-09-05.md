# AX-012/task65 — prove-factory r8 park leftover logic

September 5, 2026 17:56 PDT, before lab run. Local `unittest discover`
95 OK. Operator asked to run this cut, then the HDD 117 list.
Theory: leftover donor protocol is a `Package/legacy` artifact. Do not run
it. Do not hold conversion on it. Converted Services, triggers, and
needed-steps still emit.

Same held-set lane: select `needs-review` from `AX-012-dcbcdda180fb`.
Compare this cut against r7 `AX-012-ff8a8071363c` (17 holds, 40 findings).

- Pipeline: `auzix-release-container-validate`
- Mode: `apk-alpha-prove-factory`
- Run ID: `20260905-intake-validate-r8`
- Method: `bkc-cli trigger-pipeline` on OpenStack `bkc-alt` via lab SSH
- Output: `/var/lib/auzix-build/package-proof/AX-012-<source12>`
- Protected: VM145, HDD, r7 proof `AX-012-ff8a8071363c`

Rollback: leave the new proof directory; do not reuse this run ID.
Acceptance: conversion completes, `validation-boundary.json` exists,
report hold/finding/legacy delta vs r7. Parked leftovers are in
`Package/legacy` and must not appear as FPM hooks. Install/HDD remain
untested. Do not start this run until local units are green and the
cut is committed.
