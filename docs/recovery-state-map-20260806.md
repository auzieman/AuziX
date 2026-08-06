# AuziX live recovery state map — 2026-08-06

## Inputs

- Last bootable ISO: `auzix-live-theme-app-candidate.iso`
- ISO SHA-256: `dbc37d309059b70cc39e37b7a5e0be7d27dae770654bf3ccf7ddf7d142c25cb6`
- Embedded SquashFS SHA-256: `7e2cc1a249e76c2711dd3659fc5485637229e9afd158584b6c937104ed37220a`
- Recovered staged root: `out/auzix-iso/iso/AuzixRoot`
- Source checkpoint: `393bf95`

The generated itemized comparison is committed at:

`out/recovery-audit/baseline-to-staged-root.rsync`

The comparison is an `rsync -nai --delete` plan with the preserved SquashFS
root as the source and yesterday's staged root as the destination. Runtime-only
`/dev`, `/proc`, `/sys`, and `/run` contents are excluded.

## Bounded recovery areas

- Existing installer core integration and launchers.
- Existing live tools and startup integration.
- Existing AuziX user defaults and desktop application metadata.
- Existing validated theme and wallpaper compatibility exports.
- SquashFS/loop modules for the preserved `6.1.0-48-amd64` kernel.
- Operator SSH configuration and authorized keys.
- InstallerEFL frontend payload.

The recovery build must retain the preserved ISO kernel, initramfs boot map,
and SquashFS-overlay contract. It must not select a worker-host kernel or run a
broad package/root rebuild.
