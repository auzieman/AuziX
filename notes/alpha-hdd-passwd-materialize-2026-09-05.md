# AX-012/task65 — restore HDD /etc account files as regular files

September 5, 2026 20:22 PDT, before commit. Operator: prior HDD images
already had sshd, passwd, and users through Enlightenment. The unlock-r11
HDD fail is the docker-export leaf links, not a missing account/sshd/E
stack.

## Evidence (read-only)

VM145 `/etc/{passwd,group,shadow,gshadow}` are regular files, same sizes
as `/System/Settings`. Accounts present: root, sshd (uid 74, `/run/sshd`),
auzix, messagebus, lightdm. `sshd -t` pass. Enlightenment session already
running (PIDs from 17:51 PDT; not started by this inspect).

Prior staged root
`/var/lib/auzix-build/alpha-hdd/20260831-r20/root/etc/` has the same
four regular files.

Failed unlock-r11
`/var/lib/auzix-build/alpha-hdd/alpha-apk-20260905-alpha-unlock-r11/root/etc/`
still has absolute leaf links to `/System/Settings/{passwd,group,shadow,gshadow}`.
Host `cp` died on the first of those. VM145 untouched. VM146 not created.

## Change

`scripts/stage-auzix-alpha-hdd-root.sh`: unlink those four `/etc` names,
copy the edited Settings files as regular files (same as alpha-final
overlay and VM145), then assert each `/etc` database is a regular file
and matches Settings. Do not redesign users, sshd, or E.

## Execution / rollback

Commit this stager only, push to r730 `cursor-auzix`, park the failed
r11 work dirs, then a new BKC HDD id (not
`alpha-apk-20260905-alpha-unlock-r11`). Target VM 146. Not 145. Not 135.
Rollback: revert the unlink-and-copy block. Keep the failed r11 dirs as
evidence. Do not attach anything to 145.

Acceptance: staged `/etc/{passwd,group,shadow,gshadow}` are regular
files; existing `sshd -t` and E payload checks still run. Guest desktop
proof remains later.

Kanboard task65 comment sync pending.
