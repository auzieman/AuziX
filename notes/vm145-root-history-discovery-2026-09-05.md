AX-004 / AX-005 / AX-012 — September5 — root history discovery

Before documentation/ticket update: record read-only discovery from operator's
timestamp-scan suggestion. No VM modifications. Preserve history and repair
archives; do not replay old destructive commands blindly.

VM145 root history is /.ash_history. Earlier searches under /root and /Users
missed it. The claim that only user history persisted was incomplete.
BusyBox find lacks -ls; equivalent -exec stat works. Broad last24h scan was
dominated by Flatpak objects and output was truncated; not a complete inventory.

History tail contains explicit recovery sequence: backup user's .e/.elementary
under /Work/repair, fetch e-user-state.tar.gz, extract into vm132-seed, copy both
trees to /Users/auzix, chown1000:1000, restart E. Several attempted endpoints
precede the later PVE endpoint. Command presence alone does not prove success.
Inspect retained archive and actual user trees next; compare package/image
profile seeding against them before changing session startup.

Relevant retained paths: /Work/repair/e-user-state.tar.gz,
/Work/repair/vm132-seed, /Work/repair/vm145-preseed-recreated-e,
/Work/repair/vm145-preseed-recreated-elementary.
Do not publish raw shell history: it contains access-setup operations.

Timestamp evidence: /System/Tools/start-enlightenment-session modified/changed
2026-09-04 20:33:36 UTC; installer launcher 22:40:37 UTC. Session script contains
Efreet prestart, DBus initialization and profile manipulation. These are leads
to reconcile with git, not permission to overwrite the running desktop.
