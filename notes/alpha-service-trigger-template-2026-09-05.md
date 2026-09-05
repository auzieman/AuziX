# AX-012/task65 — service/trigger template

September 5, 2026 16:50 PDT. Operator: leftover holds have the makings
of a template. Alpine analog of `init-system-helpers` is the init or
nothing. AuziX analog is `/Services/<name>/run` plus an apk trigger
(shell, lua, or python). Not another `auzix_*` dpkg understudy.

Target: `packaging/templates/apk-path.trigger`,
`packaging/templates/service-run.sh`, `auzix/lifecycle_intake.py`.
Families: Debian `interest /path` → `--apk-trigger`; generated
`invoke-rc.d` / `update-rc.d` / `deb-systemd-helper` → package-owned
`/Services/<name>/run`. Image/first-boot still owns start policy.

Method: local laptop units only. No BKC, HDD, or VM145. Rollback:
revert these three files plus tests. Acceptance: `unittest discover`
green; Appstream-shaped `interest` becomes `--apk-trigger`; generated
enable writes `/Services/<name>/run` and drops `auzix_reload_service`.

Kanboard task65 comment after the tests; sync pending if the board is
down. HDD stays locked.

Outcome: local `python3 -m unittest discover -s tests` — 89 OK. Debian
`interest /usr/share/...` and `/etc/...` become `--apk-trigger` on
Compatibility/Settings paths. Generated enable/reload writes
`/Services/<name>/run` from `service-run.sh` and no longer emits
`auzix_reload_service` / `auzix_enable_service`. Named leftover
`interest example-cache` still needs-review. No BKC, no HDD. Next:
commit when asked, then prove-factory vs r4 (30 holds / 100 findings).
