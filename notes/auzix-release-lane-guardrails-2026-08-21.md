# AUZiX release-lane guardrails — 2026-08-21

AUZiX package builds must follow a single Debian release lane. For the current
alpha workstation lane that means Trixie, not Bookworm, not lab-host binaries,
and not whatever apt happens to expose from a newer or older source.

## Rules

1. The active AUZiX core is the only core.
   - `/System/Libraries/Runtime/glibc` owns glibc for the root.
   - Leaf packages must not introduce app-local glibc or loader copies.
   - If a package requires a newer `GLIBC_*` than the active root provides, stop
     and rebuild/declare a new base release first.

2. Debian metadata is source-of-truth input.
   - Binary package control data, dependency fields, maintainer scripts,
     triggers, conffiles, ownerships, modes, setuid bits, and sticky bits are
     part of the package contract.
   - AUZiX may relocate paths, but it must not throw away the package lifecycle
     semantics and then rediscover them by live debugging.

3. Trixie package-suite recipes are Trixie recipes.
   - `host-binary` / `suite: lab` is not allowed in the strict Trixie lane.
   - Legacy Bookworm helpers must be treated as legacy/tooling until replaced
     or explicitly isolated.

4. Pipelines own the loop.
   - Plan the release lock.
   - Preflight the recipe lane.
   - Build from the lock.
   - Validate in the container/VM.
   - Promote only the validated repo/ISO output.

## Enforcement added

`scripts/preflight-auzix-release-lane.sh` now checks:

- command-suite recipe source lanes;
- apt candidate provenance for the requested Debian suite;
- downloaded `.deb` ELF `GLIBC_*` requirements against the active AUZiX root.

`scripts/build-auzix-debian-intake-package.sh` calls this preflight before
extracting or packaging a Debian intake package.

`scripts/run-auzix-trixie-intake.sh` and
`scripts/run-auzix-workstation-package-rebuild.sh` default to:

```sh
AUZIX_DEBIAN_SUITE=trixie
AUZIX_STRICT_RELEASE_LANE=1
```

The workstation rebuild also lints package recipes before the build starts.

