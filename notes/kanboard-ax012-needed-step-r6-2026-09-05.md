AX-012 / task65 — September 5, 2026 17:12 PDT

Leftover Debian steps are still needed. Intake wraps them as
`auzix_needed_step` (list / rename / own / named) so hooks do not call
missing `dpkg-*` and do not fail the package. Not a Named type and not
`auzix_dpkg_*`. Local 92 tests OK.

Starting prove-factory r6, same held-set lane vs r5
(`AX-012-3dee50cce1c6`, 28 holds / 95 findings). Run
`20260905-intake-validate-r6`. HDD still locked. Install not tested.

Remote sync: pending.
