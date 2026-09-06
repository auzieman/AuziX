# AX-012/task65 — Sudo current assert followed the builder, not the guest

September 5, 2026 20:47 PDT. BKC `cce7464a` is not hung. `run.status` is
`failed rc=1`. `build.log` stopped after live-tools because the next
section is silent and `set -e` exited on `test -x` with no message.

The link was created: `Programs/Sudo/current -> /Programs/Sudo/host`.
Passwd files are regular files. The builder then did
`test -x $OUTPUT_ROOT/Programs/Sudo/current/Commands/sudo`, which
follows the absolute target on r730, where `/Programs/Sudo/host` does
not exist.

Change: keep the in-guest `current -> host` link. Assert `host/Commands/sudo`
on the staged tree, then `chroot` `test -x /Programs/Sudo/current/Commands/sudo`.
Print a line after publishing the link so the log is not silent there.

Park `cce7464a` dirs before the same `hdd_id` retry. Target 146. Not 145.
Proof stays on r730.

Kanboard task65 comment sync pending.
