September 5, 2026 16:09 PDT — AX-012/task65.

VM145 is close enough and stays the reference. No new HDD until intake
validation has a receipt. prove-factory was failing because the effects
script always exited 1 and `completed-with-review` was treated as a crash.
Those are mapper leftovers, not an AuziX OS bug.

Starting BKC `auzix-release-container-validate` as `apk-alpha-prove-factory`,
run `20260905-intake-validate`, through `bkc-cli`. HDD still locked.

Result: BKC `56cb1604` queued. R730 failed 3 factory units before conversion
(`ready` vs `needs-review` after rewrite-paths.sed). Log
`apk-alpha-20260905-intake-validate-resume-95000ccdab58.log`.

Plan 16:15 PDT: do not rerun yet. Split lifecycle runtime rewrites from
payload `/usr*` Compatibility. Local unittest discover green, then one
bkc-cli prove-factory. HDD still locked.
`notes/alpha-intake-validate-plan-2026-09-05.md`.

16:17 PDT: operator agreed. Implementing the split so the mapper history
stays repeatable. Local units first; no BKC in this cut.

16:19 PDT: stepping to prove-factory r2 on `016a920` through bkc-cli.
Run `20260905-intake-validate-r2`. HDD still locked.

Result: BKC `05461cd9` conversion completed-with-review. Findings 181→179
on D-Bus pair only. 35 still needs-review. validation-boundary written.
Install/HDD not tested.

16:30 PDT: walked four smallest holds vs Debian originals. The 35 are
leftover `DPKG_ROOT` / `dpkg --compare-versions` / `invoke-rc.d` /
`sysctl` after we already imported the effect. Not 35 adapters.
`notes/alpha-held-five-unpack-2026-09-05.md`.

16:33 PDT: recovering those four shapes as AuziX helpers on the APK
hook. Local units first. HDD still locked.
