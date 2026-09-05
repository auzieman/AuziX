# AX-012/task65 — AuziX terms, not a DPKG_ROOT helper

September 5, 2026 16:46 PDT. Operator correction on `cbcdcc0`.

There is no DPKG_ROOT in AuziX. Not exactly. The layout is the root:
`/Programs`, `/System/Settings`, `/System/Run`, `/Services`. Debian's
empty-root guard is "we are not in a chroot." AuziX never was.

There is no `deb-systemd-helper` analog to port. What can fire the
equivalent is already in the package format:

- shell on the APK scriptlet (`Package/Scripts`, FPM after-install)
- Lua
- Python (`python_lifecycle` already exists)
- apk triggers (`--apk-trigger` on owned paths)

`auzix_reload_service` / `auzix_enable_service` as a shadow of
`invoke-rc.d` / `update-rc.d` is the wrong object. Packages own a
`/Services` run or a trigger script. Image/first-boot owns whether a
deployment starts it. A generated systemd scaffold should become an
operation plus one of those four, not a new helper namespace that still
thinks in dpkg.

Next import: leftover `triggers` → `--apk-trigger` (shell/lua/python).
Leftover divert/account stay operations. Do not grow more `auzix_*`
Debian understudies. HDD still locked.

16:50 PDT: templates are `packaging/templates/apk-path.trigger` and
`packaging/templates/service-run.sh`. Intake applies them generically.
