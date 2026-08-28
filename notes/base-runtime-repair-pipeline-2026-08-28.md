# Targeted base-runtime repair pipeline — 2026-08-28

## Evidence carried forward

- Preserve the immutable 1,133-package Trixie intake spool; do not replay it.
- `trixie-base-20260824-r3` stopped after transaction 1119 because `jq`
  exceeded the argument limit. Its resume completed the package identities,
  but the base-provider materialization contract was not proven complete.
- The reviewed base lock selects `GCC14Base 14.2.0-19` and
  `LibgccS1 14.2.0-19`.
- The r4 repository and prepared root lack `LibgccS1`, and the prepared root
  lacks `/System/Libraries/Runtime/glibc/libgcc_s.so.1`.
- Container validation reached LibreOffice and exposed that missing canonical
  runtime surface. BusyBox, Nginx, Python, Glances, and Htop passed first.

## Bounded correction

Use BKC pipeline `auzix-base-runtime-repair`.

The pipeline may build only `gcc-14-base` and `libgcc-s1`, with dependency
discovery disabled. `LibgccS1` must own both its retained `/Programs` payload
and `/System/Libraries/Runtime/glibc/libgcc_s.so.1` in the package archive.

The lane merges those two packages over frozen r4 into a new r5 release. It
must not modify r4, copy a host library, replay the workstation transaction,
or authorize the HDD lane directly.

## Promotion order

1. Commit and tag the AUZiX package ownership fix as
   `auzix-alpha-base-runtime-repair-20260828-r1`.
2. Deploy the BKC pipeline definition/executor wiring.
3. Run `auzix-base-runtime-repair` and wait for its detached receipt to become
   complete.
4. Run `auzix-release-container-validate` against the new r5 release.
5. Only a passing container receipt may hand off to the HDD build pipeline.
