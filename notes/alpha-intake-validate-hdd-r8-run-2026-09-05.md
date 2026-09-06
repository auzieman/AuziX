# AX-012/task65 — prove-factory HDD 117 after held r8

September 5, 2026 17:56 PDT, before lab run. Operator: implement park-legacy,
run the held set, then rerun against the whole HDD package list.

This is intake conversion of the r10 selected runtime (117 names in
`/var/lib/auzix-build/pre-hdd-apk/20260905-alpha-bkc-r10/selected-repo/profile.json`).
It is not an HDD assemble and does not unlock the disk.

Compare against baseline conversion `AX-012-376e00389e32` (97 passed + 20
static, 0 holds on this 117). Report passed→needs-review as regressions.
Parked leftovers stay in `Package/legacy`.

- Pipeline: `auzix-release-container-validate`
- Mode: `apk-alpha-prove-factory`
- Run ID: `20260905-intake-validate-hdd-r8`
- Method: `bkc-cli trigger-pipeline` on OpenStack `bkc-alt` via lab SSH
- Output: `/var/lib/auzix-build/package-proof/AX-012-<source12>-hdd`
- Protected: VM145, HDD assemble, r7/r8 held proofs, r10 selected-repo

Start only after held r8 has a receipt. Same source commit. Rollback: leave
the new proof directory. Install/HDD remain untested.
