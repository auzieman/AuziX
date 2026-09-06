# AX-012/task65 — dpkg-helper is not an AuziX item

September 5, 2026 17:02 PDT. Operator: leftover `dpkg-helper` findings
must not fail intake. Replace the donor protocol with the AuziX
equivalent.

r5 tokens were `dpkg-maintscript-helper` (`mv_conffile`,
`symlink_to_dir`), `dpkg-divert` queries/add, `dpkg-query`,
`dpkg-trigger`, `dpkg -L`, leftover `dpkg-statoverride --list`, and
false hits on `.dpkg-bak`. None of those are AuziX objects.

Otherwise it is path ownership and install order. AuziX objects:

- Settings / owned RootFS path (rename, list, mode)
- this package owns the path (no divert database)
- which scriptlet is running (install vs remove), not `dpkg-query`

The steps are still needed. Wrap them in `auzix_needed_step` (path, rename,
list, named/order) so the hook does not call missing `dpkg-*` and intake
does not throw. Not a `Named` type and not `auzix_dpkg_*`.

Local units first. No BKC/HDD in this cut unless asked.
