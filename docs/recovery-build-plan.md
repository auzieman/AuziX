# AuziX Recovery and Refinement Lane

This lane restores one known bootable baseline first, then improves packages
individually. It is deliberately the opposite of a full desktop rebuild.

## Current baseline

- Strict root: `out/auzix-strict/AuzixRoot`
- Kernel and driver contract: `6.1.0-48-amd64`
- Recovery media: `artifacts/auzix/auzix-strict-shell-uefi-beta.iso`
- Disposable Proxmox target: VM135 (`Auzix-VM135`)

The ISO has passed the static media gate: `AUZIXLIVE`, BIOS El Torito, and UEFI
El Torito are all present. VM135 boots its CD before its disposable disk, so a
live-media test does not mutate the installed target unless an operator starts
the installer.

## Gates, in order

1. Static root and media contract.
2. Non-GUI container smoke of the strict root.
3. Disposable VM serial/console boot of the exact ISO.
4. One package build or receipt refinement.
5. Repeat gates 1–3 for the changed package.

Do not spend a VM boot on a package that has not passed its root and container
checks. Do not use `strict-all` as a repair tool for one package.

## Per-package receipt

Every refined package needs a small evidence record:

- source/version and build input;
- declared runtime paths, libraries, users, and service entry points;
- result of the package runtime audit;
- a minimal executable or service smoke command;
- whether it changed the boot, ISO, or graphical path.

Initial priority batches are: core shell/CA/runtime tools, network tools, then
one GUI or container-runtime component at a time. Debian remains a source and
build-input donor; the runtime contract is the AuziX root and its receipts.

## Build placement

The workstation may perform small static checks, but large root imports and
package builds belong on `lab-build` once the private route is restored. Keep
the workstation as the operator console and retain the resulting artifact,
checksum, and validation receipt in the repository/pipeline evidence.
