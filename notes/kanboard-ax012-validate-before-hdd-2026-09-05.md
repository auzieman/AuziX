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

16:36 PDT: prove-factory r3 on `4fae578` to measure the held set.
Run `20260905-intake-validate-r3`. HDD still locked.

Result: BKC `5daa57c8`. The four unpacked scripts passed. Holds 35→31.
Findings 181→171. Same leftover families on the rest. Install/HDD not
tested.

16:38 PDT: build-measure-learn r4 — generated dh_systemd/init scaffold
and DPKG_ROOT empty/`/etc` prefix. Then prove-factory r4.

Result: BKC `6e873a33`. Findings 181→100. Holds 35→30. Fprintd passed.
DBus 12→2. Next leftover: dpkg-helper, unmapped-path, maintainer-surface.

16:46 PDT: AuziX has no DPKG_ROOT helper. Equivalents are shell, lua,
python, and apk triggers. Do not grow `auzix_*` as dpkg understudies.
`notes/alpha-auzix-no-dpkg-root-2026-09-05.md`.

16:50 PDT: that is the template for the leftover holds. Debian
`interest /path` → apk trigger; generated enable → `/Services/<name>/run`.
Local units first. Kanboard task65 sync pending.
`notes/alpha-service-trigger-template-2026-09-05.md`.

16:54 PDT: prove-factory r5 on that template. Same held-set lane, compare
to r4 (30 holds / 100 findings). HDD still locked.
`notes/alpha-intake-validate-r5-run-2026-09-05.md`.

Result: BKC `c6ded1e7`. Holds 30→28, findings 100→95. Appstream and
XdgDesktopPortal passed. Five new `if true then` syntax leftovers from
`was-enabled`. HDD still locked.

17:12 PDT: prove-factory r6 wraps leftover needed steps as
`auzix_needed_step` so intake does not throw. Same held-set lane vs r5.
Run `20260905-intake-validate-r6`. HDD still locked.
`notes/alpha-intake-validate-r6-run-2026-09-05.md`.

Result: BKC `48302007`. Holds 28→22, findings 95→61. Six newly ready
including Ntfs3g and Udisks2. `dpkg-helper` gone. HDD still locked.

17:16 PDT: those remaining unmapped `/usr` `/bin` rows are donor
coordinates. We have the objects at Programs/Compatibility/PATH; they
often fire at first-boot or trigger time. Not 22 missing AuziX items.

17:39 PDT: Debian's script is dpkg logic. apk has its own db. Do not
keep Dpkg/Debconf as runtime luggage. Adapted means apk terms.
`notes/alpha-apk-owns-the-db-2026-09-05.md`.

17:40 PDT: convert the real effect or strip the dpkg/debconf question.
No `own` wrap. Local units first. HDD still locked.

17:42 PDT: prove-factory r7 convert-or-strip vs r6. Run
`20260905-intake-validate-r7`. HDD still locked.
`notes/alpha-intake-validate-r7-run-2026-09-05.md`.

Result: BKC `7986f70b`. Holds 22→17, findings 61→40. DBus, Gzip,
Python313, SgmlBase, XMLCore passed. unmapped-path 22→1. HDD locked.

17:56 PDT: park leftover donor logic in Package/legacy, then held r8
and HDD 117 conversion. No HDD assemble.
`notes/alpha-intake-validate-r8-run-2026-09-05.md`
`notes/alpha-intake-validate-hdd-r8-run-2026-09-05.md`.
