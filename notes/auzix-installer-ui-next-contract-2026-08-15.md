# AUZiX installer UI next contract — 2026-08-15

The ESXi live ISO proved the basic boot surface, but the installer UI is still
too primitive for the next demo pass.

## Current reliable live surfaces

The installer ISO should always expose these four launcher surfaces:

- AUZiX Browser — Midori if present, NetSurf fallback
- AUZiX Rescue Terminal — `xterm` first, Terminology fallback
- Install AUZiX — reliable terminal-hosted installer launcher
- AUZiX Files — EFM / `enlightenment_filemanager`

Terminology is not stable enough to be the first-choice installer terminal on
this lean ISO. Use `xterm` first until the EFL stack is fully clean.

## UI direction

The next installer UI should feel like AUZiX, not a bare dialog script:

- full-screen/wizard-style landing page
- clear install path choices:
  - clean install
  - preserve `/Users`
  - expert/manual partition
- explicit target disk review before destructive actions
- package profile selection:
  - lean installer/base
  - desktop
  - workstation/media
  - container/podman
- network/repository check before install
- visible install log pane or “details” toggle
- first-boot preview: user, hostname, desktop/session, package group
- post-install reboot prompt with clear eject/boot-disk instructions

## Build rule

Do not make the installer depend on fragile desktop state. The graphical surface
may improve, but the rescue terminal launcher must always be able to run the
installer TUI.

