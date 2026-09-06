# AX-012/task65 — leftover systemctl is Programs/Systemd

September 5, 2026 17:46 PDT, before code. Operator: leftover `/bin/systemctl`
is a bad path; we should have systemctl or systemd.

r7 last unmapped-path is `/bin/systemctl` on SystemdSysv. The rendered line
is `ln -sf ../bin/systemctl "$fn"`. The finding scanner matches `/bin/systemctl`
inside that relative Debian usr-merge restore. It is not a missing foreign
manager.

Donor evidence (Systemd-257.13-1deb13u1.auzix.tar.gz):
- `Programs/Systemd/.../Commands/systemctl`
- `Programs/Systemd/.../RootFS/usr/bin/systemctl`
- `System/Compatibility/bin/systemctl` (published alias)

SystemdSysv only ships `RootFS/usr/sbin/halt` and restores
halt/poweroff/shutdown as links to that command.

Convert leftover `../bin/systemctl` (and classic `/bin/systemctl`) to
`/System/Compatibility/bin/systemctl`. Stop flagging the word `systemctl` as
`foreign-service-manager`. Do not invent a helper. Do not add
`Programs/Systemd` to COMMAND_ALIASES on images that may not ship it; the
Systemd package already publishes the alias.

Local units before any BKC prove-factory. Compare r8 against r7
`AX-012-ff8a8071363c` only after a commit. HDD still locked. Install not
tested. VM145 untouched.
