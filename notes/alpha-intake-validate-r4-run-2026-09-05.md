# AX-012/task65 — prove-factory r4 dh_systemd scaffold

September 5, 2026 16:38 PDT, before lab run. Learn from r3 leftovers:
`DPKG_ROOT` empty guards, `${DPKG_ROOT}/etc`, `invoke-rc.d --skip-systemd-native`,
`deb-systemd-invoke` stop/`$_dh_action`, `systemctl daemon-reload`,
`update-rc.d`, `.service` false `service` matches.

- Pipeline: `auzix-release-container-validate`
- Mode: `apk-alpha-prove-factory`
- Run ID: `20260905-intake-validate-r4`
- Source: after this commit on r730 `cursor-auzix`
- Output: `/var/lib/auzix-build/package-proof/AX-012-<source12>`
- Compare: r3 `AX-012-4fae57852e38` (31 holds, 171 findings)

No HDD or VM145.

Outcome: BKC `6e873a33` completed-with-review. Findings 181→100. Holds
35→30. New pass: Fprintd (plus the r3 four). DBus 12→2. Remaining bulk
is `dpkg-helper` (23), `unmapped-path` (22), `maintainer-surface` (11).
Install/HDD not tested.
