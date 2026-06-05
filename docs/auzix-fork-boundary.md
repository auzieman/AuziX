# Auzix Fork Boundary

## Decision

Auzix should become its own distro track instead of remaining only a Tabor Linux
Forge experiment.

The current Auzix work is no longer just a helper image for another target. It
has its own root contract, boot model, package receipts, live desktop path,
installer direction, and workstation identity. Keeping it embedded in the Tabor
tree will make both efforts harder to reason about.

## Auzix Owns

- x86_64 live ISO and VM bring-up
- `/System`, `/Programs`, `/Services`, `/Stacks`, `/Work`, `/Users`
- compatibility bridges under `/System/Compatibility`
- `/System/PackageDB` receipts and package repository artifacts
- live installer and installed-root handoff
- desktop stack: Xorg fallback, LightDM, Enlightenment, terminals, browser
- future apk-backed package transport
- service and stack orchestration model

## Tabor/Amiga Track Owns

- AmigaOne/Tabor kernel work
- PowerPC/SPE-specific boot media
- firmware and board-specific packaging
- Amiga-oriented UX experiments after the Auzix concepts settle
- portability feedback from Auzix back into Amiga-style startup and layout ideas

## Shared Design DNA

- readable startup sequencing
- small, inspectable services
- strong path ownership
- package receipts that describe intent, not just files
- live media that can become an installed workstation
- optional compatibility paths rather than compatibility as identity

## Near-Term Repo Shape

Until a physical repo split happens, keep Auzix work grouped under:

```text
docs/auzix-*.md
recipes/
scripts/*auzix*
profiles/rootfs/auzix-*
out/auzix-strict/
artifacts/auzix/
```

The first clean fork should preserve history, then move Auzix-specific scripts,
recipes, docs, profiles, and tests into a dedicated repository. Kernel/Tabor
tooling should stay behind unless Auzix explicitly needs it as a package input.

## Current Technical Boundary

The stable VM130 image remains the whole-root initramfs ISO. The split ISO-root
mode is promising because it reduces initramfs size sharply, but it still needs
early-media diagnostics before becoming the default.

Browser packaging should start with a small optional package, likely
`netsurf-gtk` from Debian Trixie, before adding heavyweight Firefox/Chromium
packages.
