# Package loop and HDD handoff — 2026-08-28

## Recentered design rule

Do not model AUZiX packaging, repository consolidation, release assembly, or
media creation as one monolithic JSON or shell operation. Each stage consumes
an explicit list and emits an immutable receipt. Whether the list contains five
packages or two thousand, the transaction loop is the same; only the list size
and bounded scheduling change.

```text
locked package list
  -> locate existing payload/build inputs
  -> apply package lifecycle metadata
  -> emit immutable package spool and receipt
  -> consolidate reviewed spools into a repository and receipt
  -> assemble an explicitly named release and receipt
  -> validate the release contract
  -> install the validated repository profile into a fresh root
  -> wrap that installed root as HDD/live media and validate boot
```

Payload build, package finalization, repository consolidation, release
publication, root installation, and media wrapping are separate phases.
Repackaging must not imply recompilation. A package such as LibreOffice is an
ordinary list entry, not a reason to create package-specific release assembly.

## Authority and receipt rules

- The frozen repository index is the dependency-closure authority for release
  packaging. Mutable build-root receipts are evidence from an earlier phase,
  not final repository truth.
- Logical release identity is an explicit input. It must never be inferred
  from a candidate or temporary directory name.
- Each downstream stage consumes the previous stage's receipt instead of
  rediscovering state from incidental directories.
- Release validation must prove index, manifest, hashes, package count,
  dependency closure, source/target identity, and receipt agreement together.
- HDD composition must install packages from the validated repository into a
  fresh target root. Copying or rsyncing a prepared/validation root is not an
  authorized substitute for the package transaction.
- The media writer owns only partitioning, filesystem creation, boot payload,
  bootloader installation, checksum, and boot smoke after root composition.

## Immediate HDD gate

The existing BKC HDD script that passes a validation root to
`build-auzix-live-disk-image.sh` and copies that tree into the image does not
meet this contract. The established package-profile installer loop in
`scripts/auzix-install-root-from-repo-profile.sh` is the intended composition
path. The HDD pipeline must invoke or factor that loop against the exact
validated release repository and profile, then pass its installed-root receipt
to the media wrapper. Do not launch HDD assembly from a copied validation root.
