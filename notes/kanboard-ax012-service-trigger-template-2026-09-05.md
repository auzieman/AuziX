AX-012 / task65 — September 5, 2026 16:52 PDT

Leftover holds are one template, not 35 adapters. Alpine has no
`init-system-helpers`. AuziX analog is `/Services/<name>/run` plus an
apk trigger (shell/lua/python). Intake now:

- Debian `interest /path` → `packaging/templates/apk-path.trigger` +
  `--apk-trigger` on Compatibility/Settings paths
- generated `invoke-rc.d` / `update-rc.d` / `deb-systemd-helper` →
  `packaging/templates/service-run.sh` at `/Services/<name>/run`

Dropped `auzix_reload_service` / `auzix_enable_service`. Local 89
tests OK. Install/HDD not tested. Sync pending if this comment is
local-only.

Remote sync: pending.
