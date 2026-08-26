# Trixie r3 build/output review — 2026-08-26

## Scope

This review correlates the declared native-rebase contract, the executed
workstation rebuild script, Docker container history, and the package artifacts
written by `trixie-base-20260824-r3`.  It is the gate before another HDD image
assembly or boot pipeline run.

## Timestamped evidence

- Build container: `auzix-native-rebase-trixie-base-20260824-r3`
  - started `2026-08-25T00:19:12Z`
  - stopped at transaction `1119/1133` because `jq` exceeded the argument limit
- Resume container: `auzix-native-rebase-trixie-base-20260824-r6-resume`
  - started at offset 1119
  - completed the remaining 14 locked transactions
  - entered the unlocked Flatpak post-stage and was stopped while recursively
    discovering `libarchive13t64 -> libacl1 -> ...`
- Immutable intake spool:
  `artifacts/auzix/package-spool-trixie-base-20260824-r3`
  - 1,133 archives
  - 1,133 numeric-owner metadata files
  - 1,133 repository entries
  - all entries identify the Trixie suite
  - no Bookworm text was found
  - no duplicate AUZiX package names were found
  - all archive hashes and tar streams pass
- Resume defect: the intended `less` transaction is absent and the unlocked
  post-stage `libacl1` artifact occupies the final spool slot.
- Later Flatpak closure attempts changed the mutable validation root. Their 39
  downloaded archives are under that root's transaction cache and are not part
  of the immutable 1,133-package spool.

## Contract versus implementation

`packages/rebase-native-build.pipeline.json` and
`packages/session-bootstrap.policy.json` require:

1. metadata-only discovery and a committed lock;
2. prefetch without target-root mutation;
3. a separately built base/runtime substrate and development surface;
4. an AUZiX-native builder made from that substrate;
5. leaf builds against that native builder;
6. installation into a fresh validation root;
7. image assembly through the same package lifecycle.

The current `scripts/run-auzix-workstation-package-rebuild.sh` does not yet
implement that staged graph. It:

- accepts an already-populated, mutable `AUZIX_ROOT`;
- rebuilds several native helper packages directly into that root;
- executes the complete locked Debian selection as one serial intake;
- runs additional desktop/Flatpak stages after the locked intake;
- allows those post-stages to request dependencies not represented by the
  reviewed lock;
- creates a spool for the Debian intake but does not emit a complete,
  standalone base/substrate repository closure.

## Repository proof result

An isolated repository generated only from the immutable spool contains 1,133
valid, unique Trixie packages. It is not installable as a standalone fresh root:
5,860 dependency edges reference 327 unique AUZiX package names absent from the
spool repository. Many are expected substrate providers (glibc, GCC runtime,
DBus, EFL, X11, PAM, SSL, font and input libraries), proving that the base and
application artifact lanes were never joined into one reviewed release set.

This is a pipeline composition failure, not evidence that the 1,133 archives
must all be rebuilt.

## Required correction before HDD assembly

1. Freeze the r3 spool and never append post-stage output to it.
2. Resolve the complete release set before execution, including native AUZiX
   packages, substrate providers, development surfaces, desktop packages, and
   leaf applications.
3. Give each phase a separate immutable spool and receipt:
   `base`, `dev`, `native-builder`, `apps`, and `desktop-finalize`.
4. Merge those spools only after rejecting duplicate package identities,
   conflicting providers, suite drift, missing dependency edges, and alternate
   glibc providers.
5. Replace offset-based resume with package-identity completion state. A resume
   must compute `locked set - completed set`; it must not skip by line number.
6. Disable dependency discovery in every execution/post stage. Missing edges
   return to discovery and produce a new reviewed lock.
7. Build a fresh validation root solely through repository package lifecycle;
   do not validate or promote the mutable build root.
8. Validate representative normal-user front doors (Terminology, Flatpak,
   LibreOffice Writer/Calc/Impress, AbiWord/Pluma, Glances, Midori and desktop
   launchers) before the HDD pipeline is eligible to run.
9. Assemble the HDD root through the same package transaction and validate both
   live-media and installed-disk boots before promotion.

## Parallel execution rule

Parallelism begins only after the locked dependency graph is partitioned.
Packages in the same topological level may run in bounded worker lanes with
isolated work directories and spools. A barrier validates and merges each level
before dependants begin. No worker may discover or build a new dependency while
executing its assigned level.

## Current decision

HDD image build is **not authorized yet**. The r3 package payloads are preserved
and largely reusable, but the release repository must first gain a complete,
locked substrate closure and pass a fresh-root lifecycle validation.
