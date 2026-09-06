# AX-012/task65 — HDD phase 2 failed on host cp through /etc/passwd

September 5, 2026 18:35 PDT. unlock-r11 pre-hdd passed. BKC `a4e49aa4`
started `auzix-release-hdd-build-deploy`
`hdd_id=alpha-apk-20260905-alpha-unlock-r11` `target_vmid=146`.
VM145 untouched.

## Evidence

`/var/lib/auzix-build/alpha-hdd/alpha-apk-20260905-alpha-unlock-r11/run.status`
is `failed rc=1`. Last build.log line:

`cp: not writing through dangling symlink '.../root/etc/passwd'`

Staged `etc/passwd` is an absolute symlink to `/System/Settings/passwd`.
The Settings file exists in the staged root (1177 bytes). Host `cp -a`
resolves that absolute target on the R730 host, where it is absent, so
GNU cp treats the dest as dangling.

Cause: `docker/release/common/runtime-entrypoint.sh` publishes account
files as `/etc/$name -> /System/Settings/$name`. `docker start` +
`docker export` keeps those absolute links.
`scripts/stage-auzix-alpha-hdd-root.sh` then copies Settings into
`etc/passwd` after editing service accounts.

Not an AuziX OS/package bug. Not VM145. Leftover catalog not executed.

## Next

Operator 20:20 PDT: prior HDD images already had sshd, passwd, and users
through E. Confirmed on VM145 and staged r20: `/etc` account files are
regular files. unlock-r11 export left all four as absolute leaf links.
See `notes/alpha-hdd-passwd-materialize-2026-09-05.md`.

Unlink `etc/{passwd,group,shadow,gshadow}` before `cp -a`. Same intent
as those images: real files at `/etc` after Settings edits. Failed work
dirs stay as evidence. Same `hdd_id` cannot retry until those dirs are
parked. Retry needs a commit on r730, then a new BKC HDD run.

Rollback: revert the unlink-before-cp only. Do not delete the failed
hdd-run. Do not attach anything to 145.
