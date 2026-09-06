# AX-012/task65 — BML expand to the HDD image list

September 5, 2026 16:59 PDT, before lab run. Operator: expand beyond the
held slice; that slice may be why other image issues stayed hidden.

Evidence (read-only on r730):

- HDD / pre-hdd selected runtime is
  `/var/lib/auzix-build/pre-hdd-apk/20260905-alpha-bkc-r10/selected-repo/profile.json`
  (`alpha-selected-runtime`, **117** names).
- All 117 exist in the 545-input baseline `AX-012-376e00389e32`.
- In that conversion they were **97 passed + 20 static + 0 needs-review**.
- Intersection with the 35/36 held names from `AX-012-dcbcdda180fb` is
  **empty**. DBus, Udev, Systemd, Apparmor are not on this HDD list.
  The image has `Acpid`, `Python3` / `Python313Minimal`,
  `LibreOfficeWriter`, `Passwd`, `Enlightenment`, `OpensshServer`, not
  the leftover mapper rows we have been rerunning.

So r2–r5 never re-measured the APKs that actually go on the disk. The
new interest-trigger / `/Services` import has not touched that 117.

Change:

1. `was-enabled 'unit'; then` must stay `if true; then` (r5 ate the
   semicolon and created five syntax findings).
2. `prove-alpha-factory-repackage.sh` converts the 117 HDD names from
   baseline inputs, compares against `AX-012-376e00389e32` conversion
   (not the 35-hold proof). Report passed→needs-review as regressions.

- Pipeline: `auzix-release-container-validate`
- Mode: `apk-alpha-prove-factory`
- Run ID: `20260905-intake-validate-r6`
- Output: `/var/lib/auzix-build/package-proof/AX-012-<source12>`
- Protected: VM145, HDD lane, r5 proof `AX-012-3dee50cce1c6`,
  r10 selected-repo

Not launched. 17:12 PDT operator asked to re-measure the outstanding
held packages after the needed-step wrap. That run took
`20260905-intake-validate-r6`. HDD 117 BML stays a later run; do not
reuse this note's run ID.
