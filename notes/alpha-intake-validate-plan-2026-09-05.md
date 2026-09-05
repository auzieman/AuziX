# AX-012/task65 — plan after the 0.4s fail

September 5, 2026 16:15 PDT. Planning only. No BKC, image, or HDD.

## What just happened

A few minutes earlier the real lane still worked: `bb10336` / BKC `2fe3c934`
ran Trixie units (77 pass) then converted the 35 holds. That took minutes.
All 35 stayed `needs-review`; install untested; gate exited 1 on purpose.

`95000cc` / BKC `56cb1604` stacked protocol helpers, a shared sed table, and
a new exit gate in one shot. `prove-alpha-factory-repackage.sh` runs
`unittest discover` first. It died in 0.4s. Conversion never started.

## Why the three tests failed

`_replace_paths` is two steps: owned RootFS first, then `rewrite-paths.sed`
on whatever is left. The sed file is the *payload* map (`/usr/bin` →
Compatibility, `/usr/share` → Compatibility). Lifecycle used to only rewrite
runtime leftovers (`/etc`, `/var/lib`, `/run`, …). `/var/run` was the actual
gap from the D-Bus trace.

So:

- Unowned `/usr/bin/external-helper` and `/usr/share/external/...` became
  Compatibility and dropped `unmapped-path` (status `ready`). Those fixtures
  exist so we do not invent a home for a path the package does not own.
- `. /usr/share/debconf/confmodule` was rewritten before the constant-false
  prune, so Calc stayed `needs-review` instead of `ready`.

## Contract (keep three layers)

1. Package-owned RootFS path → `${AUZIX_PACKAGE_ROOT}/RootFS...`
2. Shared runtime leftovers (`/etc`, `/var`, `/run`, `/var/run`, `/tmp`,
   `/root`) → AUZIX_* variables. This is the lifecycle sed table.
3. `/usr/bin`, `/usr/share`, `/usr/lib` payload text → Compatibility / Libraries
   only inside `rewrite_common_payload_paths` (package files). Not for an
   unowned helper name in a maintainer script.

Debconf / constant-false prune stays on donor wording, before leftover rewrite.

## Next bounded work (then one BKC)

1. Shrink lifecycle `rewrite-paths.sed` to layer 2. Keep `/usr*` lines for the
   debian-intake payload helper, or split the file.
2. Local `python3 -m unittest discover -s tests` green. Laptop is allowed.
   Do not use BKC to discover unit failures.
3. Commit + push to the r730 git remote.
4. One `apk-alpha-prove-factory` through `bkc-cli` on the lab. New run id.
   Accept `completed-with-review` plus `validation-boundary.json`.
5. Remaining service/trigger families stay findings. HDD stays locked.
   VM145 stays diagnostic.

Rollback: revert the sed/lifecycle commit only. Leave `AX-012-95000ccdab58`
as the failed-gate receipt.
