# AX-012/task65 — four held scripts vs Debian originals

September 5, 2026 16:30 PDT. Operator: the 35 are one missed Debian
protocol, not 35 bugs. Walk 1–5 originals from r2
`AX-012-016a920bda62` against the AuziX candidate. No code change yet.

Picked the smallest holds plus D-Bus common: AcpiSupportBase, Bubblewrap,
DebianArchiveKeyring, DBusSystemBusCommon. DBus is the same families plus
service scaffold.

## The simple miss

Debian maintainer scripts already say what they do:

- `in_sysroot` / `$DPKG_ROOT` — optional chroot prefix. Empty on a real
  `dpkg --configure`. Our Trixie dbus install proved that.
- `# Automatically added by dh_*` — generated protocol, not package logic.
- `invoke-rc.d NAME restart || true` — reload this service if it exists.
- `dpkg --compare-versions "$2" ...` — upgrade-only. Fresh configure has
  no `$2`.

We translate part of the block, then scan the leftover tokens with
`UNSUPPORTED_PATTERNS` and keep the whole package `needs-review`.
Across r2 that is 33× `DPKG_ROOT`, 32× `dpkg`, 31× `systemctl`/`service`,
26× `invoke-rc.d`/`deb-systemd-*`. Same four families.

## DBusSystemBusCommon (1 finding: DPKG_ROOT)

Debian `postinst` is only: define `in_sysroot` using `DPKG_ROOT`, then
sysusers-or-`adduser --system --group messagebus`.

We already emit `auzix_ensure_system_account "$MESSAGEUSER"`. The
`in_sysroot` function is still in the candidate, so `DPKG_ROOT` still
fires. Account work is done. The hold is a dead helper.

## DebianArchiveKeyring (1 finding: dpkg)

`dh_installdeb` `rm_conffile` lines are already migrations. What remains
is `dpkg --compare-versions "$2" lt 2012.1` before deleting old apt-key
bits. Regex `\bdpkg\b` treats compare-versions as an unresolved helper.
Fresh AuziX install never takes that branch.

## AcpiSupportBase (1 finding: invoke-rc.d)

Entire script: on configure, `invoke-rc.d acpid restart || true`. That is
“reload acpid if present.” Conffiles already mapped.

## Bubblewrap (1 finding: sysctl)

Entire script: if `sysctl` exists, apply `kernel.unprivileged_userns_clone`.
A command trigger, not a unique package.

## Next family (not 35 adapters)

1. Treat leftover `in_sysroot` / `DPKG_ROOT` as translated once the
   guarded command is imported.
2. `dpkg --compare-versions` is upgrade protocol, not `dpkg-helper`.
3. `invoke-rc.d NAME restart||true` and `deb-systemd-invoke` are optional
   service reload.
4. `sysctl --system` / owned sysctl snippet is a command trigger.

Local fixtures on these four shapes, then one BKC prove-factory.
HDD stays locked.

16:33 PDT implementation: AuziX helpers `auzix_upgrade_cmp`,
`auzix_reload_service`, `auzix_apply_sysctl`; drop unused `in_sysroot`.
Rendered hooks still attach as `Package/Scripts` + FPM `--after-install`.
Local `unittest discover` 86 OK. BKC not started in this cut.
