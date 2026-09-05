# AX-012/task65 — scripted held-package cycle

September 5, 2026, before mutation. User requests the D-Bus method for every
failed package. Exact starting set: 35 needs-review rows in
/var/lib/auzix-build/package-proof/AX-012-dcbcdda180fb/repository/conversion-proof.json.
Inputs remain the checksum-verified 545-input baseline AX-012-376e00389e32.

Extend the existing eight-worker repackage lane, not another build engine:
select the latest held rows, retain each original/rendered hook with hashes and
diffs, run registered component tests in separate disposable Trixie containers,
and aggregate per-package conversion, component and installation boundaries.
Continue through failures; do not execute unresolved donor hooks or promote a
package merely because its shell syntax or a component passed. Initially only
the D-Bus helper has a registered root component probe; missing tests must be
explicit blocked work, never synthesized passes. The script makes the full
remaining work list durable and rerunnable as adaptations/tests are added.

Scope is metadata/repackaging/testing on R730 through committed BKC execution.
No source compilation, public index refresh, VM or working-image changes.
Rollback: scoped git revert; new output directory only, refuse overwrites.
Acceptance: all 35 have receipts even on failure, identical input hashes, no
untested package marked accepted, real D-Bus component log retained, final
aggregate exits nonzero while any required boundary is unproven. Further hook
translations remain implementation work, not something this harness invents.
