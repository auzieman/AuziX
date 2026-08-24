# AUZiX repository housekeeping baseline — 2026-08-24

## Branch and remote state

- `main` is the public product line and tracks `origin/main`.
- `r730` is the private local build remote. It is a mirror/build handoff, not a
  replacement source of truth.
- `agents/docker-swarm-package-building` is an old unmerged worktree and must
  be reviewed before removal.
- Release work must start from a clean committed and tagged tree.

## Path ownership

- Portable package contracts, profiles, builders, validators, and notes remain
  in normal tracked paths.
- `.private/` and `lab-private/` are ignored operator-local areas for machine
  inventory, credentials, runtime exports, and experiments that must not enter
  the public product history.
- Large build output remains under ignored `out/` and `artifacts/` paths on
  lab-build/R730, not on the operator workstation.

## Current cleanup buckets

The outstanding working changes predate this baseline and must be split rather
than committed as one unit:

1. package lifecycle and runtime-substrate policy;
2. package builders and package-manager behavior;
3. live boot and image assembly;
4. validation and launcher probes;
5. historical outcome notes and known-good profiles;
6. strict-lab experiments.

`scripts/normalize-auzix-elf-runtime.sh` belongs to the strict-lab historical
experiment lane. It must not be wired into `compat-beta` image or package
production.
