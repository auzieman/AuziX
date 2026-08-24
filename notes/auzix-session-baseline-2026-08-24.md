# AUZiX session baseline — 2026-08-24

This is a consolidation point, not a new build design.

The earlier AUZiX notes correctly prohibited alternate glibc providers,
unlocked dependency discovery, dirty-tree builds, discarded package lifecycle
semantics, and promotion without runtime proof. The failure was enforcement:
the workstation rebuild verified that a lock file existed, then invoked broad
intake profiles which could discover new dependencies while building.

Start every AUZiX session with:

```sh
./scripts/auzix-session-bootstrap.sh --mode review
```

Release-producing work must instead pass:

```sh
./scripts/auzix-session-bootstrap.sh --mode build --lock PATH/TO/build-tree.lock.json
```

The build mode deliberately fails when the tree is dirty, the lock is absent,
or HEAD is not the exact tag recorded by the lock. Passing this bootstrap does
not make the current workstation rebuild compliant: that runner must still be
changed to consume the locked package graph and reject undeclared dependency
discovery.

Until that coupling exists, `auzix-workstation-package-rebuild` is a research
or diagnostic entry point and cannot produce a promoted beta repository or
image.
