# AX-012/task65 — Debian's script is dpkg's; apk has its own db

September 5, 2026 17:39 PDT. Operator: their logic produces and runs a
script. apk has its own database.

dpkg maintainer scripts exist because dpkg tracks INSTCOUNT, Conffiles,
diverts, triggers, and debconf. That script is not portable luggage.
AuziX/apk already knows what it installed. Do not ship `Programs/Dpkg`
or `Programs/Debconf` so the donor script can keep asking dpkg.

Adapted means the effect is expressed in apk terms:

- this scriptlet (after-install / after-remove), not `dpkg-query`
- owned RootFS / Settings path, not `dpkg -L` / divert db
- `--apk-trigger` or `/Services/<name>/run`, not `dpkg-trigger` / confmodule
- Compatibility only for a published command alias

Convert the filesystem or service effect into apk terms, or strip the
line if it only asked dpkg/debconf. Do not wrap leftover `dpkg-query` as
`own`. Do not keep `. confmodule` / `db_*` so Debconf can run.

HDD still locked.

17:40 PDT: implementing convert-or-strip in intake. Local units first.
