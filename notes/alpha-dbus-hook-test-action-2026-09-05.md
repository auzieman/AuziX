# AX-012/task65 — bounded D-Bus permission hook test

September 5, 2026, before implementation. The source walk found the retained
launch helper root:root 0755 and Debian's configure action requiring
root:messagebus 4754, respecting an existing administrator override.

Implement a reusable, explicit helper-permission operation and exercise it in
the existing isolated BKC source-audit container, using a temporary regular-file
fixture. Require the account before mutation, reject symlink targets, preserve
an explicit override, and test replay. This is a component proof, not a complete
D-Bus adapter or APK installation pass. Service activation and reload triggers
remain held. No source compilation, package promotion, image or VM mutation.

Execute committed code through the existing apk-alpha-source-audit lane on
R730. Keep source comparison and test logs in a new commit-addressed directory.
Rollback: revert this scoped commit; all prior outputs and R10 remain intact.
Acceptance: real uid/gid/mode assertions in the disposable container, failure
without the account and on symlinks, override preservation and successful
second invocation. Update task65 by comment; do not close the factory issue.
