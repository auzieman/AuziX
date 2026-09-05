# AX-012/task65 — shared path rewrite table

September 5, 2026 16:01 PDT, before change. Operator asked for a grok/sed
style substitution file so intake can transform leftover Debian paths in
scripts and metadata, not one-off package edits.

Existing maps are split: `PATH_VARIABLES` in lifecycle_intake, desktop
rewrites in `rewrite_common_payload_paths`, and `DONOR_PATH_MAP` in the
fragment converter. `/var/run` is missing from the lifecycle map, which is
why the Trixie dbus trace still reported unmapped `/var/run/dbus/...`.

Add `packaging/rewrite-paths.sed` as the shared table. Lifecycle applies it
after package-owned RootFS rewrites so install-time helpers stay in the
payload. Text metadata can `sed -f` the same file. Do not sed ELF. No HDD
or VM145 change.

Correction 16:17 PDT: one table hid unowned `/usr*` leftovers. Split to
`rewrite-paths.sed` (runtime) and `rewrite-payload-paths.sed` (payload).
