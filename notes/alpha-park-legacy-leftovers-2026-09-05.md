# AX-012/task65 — park leftover donor logic, do not run it

September 5, 2026 17:50 PDT, before code. Operator: last thought before a
big run — nerf the leftover errors. Keep stray logic as a package artifact
for later. Do not run it.

`~/legacy` is a user-home sketch. Package leftovers belong in
`/Programs/<Name>/<version>/Package/legacy/`. Not `/Users/root/legacy`.
Not executed by apk. chmod 0644.

Converted effects still run: `/Services/<name>/run`, `--apk-trigger`,
clean `auzix_needed_step` hooks, configuration, library publication.
A rendered maintainer script that still has leftover tokens, unmapped
paths, or broken strip syntax is copied to `Package/legacy/<stage>` and
dropped from FPM hooks. Residual findings become `legacy_findings`, not
`needs-review`.

Local units before any BKC prove-factory. Next measure is r8 vs r7
`AX-012-ff8a8071363c` only after a commit. HDD still locked. Install not
tested. VM145 untouched.
