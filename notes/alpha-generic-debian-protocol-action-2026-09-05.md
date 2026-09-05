# AX-012/task65 — generic Debian protocol intake, not 35 adapters

September 5, 2026 15:58 PDT, before code change. Operator: each held package
does not need special care. Repackaging must intake Debian metadata and
maintainer-script logic, then inject AuziX path logic.

Evidence: `build-auzix-debian-intake-package.sh` already keeps
`Metadata/debian-control-dir` and payload. `normalize_lifecycle` path-rewrites
and then flags leftover `dpkg-statoverride`, `adduser`, `DPKG_ROOT`,
`invoke-rc.d` as needs-review. Trixie dbus=1.16.2-2 proved those tokens are
normal Debian configure effects. Codex/Astra answered with per-package
reviews and a D-Bus-named fixture.

Change: teach `_apply_generated_script_rules` generic translations for
protocol families, starting with:

1. `dpkg-statoverride --update --add USER GROUP MODE PATH`
2. `systemd-sysusers` / `adduser --system --group`

Emit operations and rewritten hooks. No package-named adapter. No compilation,
repository, image, or VM145 change in this step. Rollback: revert the
lifecycle_intake commit. Acceptance: unit tests on unnamed fixtures; a D-Bus
shaped script becomes ready for those two families without a DBus adapter.
Remaining service/trigger tokens stay findings until their families land.

After those families prove on a factory receipt, rebuild the HDD package
list by *repackaging* through this intake — not another live VM sculpture.
Earlier overcorrections replaced Debian script logic that should have been
imported. Do not start that HDD wave until this mapper proof exists.
