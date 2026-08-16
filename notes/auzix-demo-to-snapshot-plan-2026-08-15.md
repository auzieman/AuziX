# AUZiX demo-to-snapshot plan — 2026-08-15

The demo proved the important shape: AUZiX can boot into a real desktop, run a
native-looking workstation layer, run Podman enough for container storytelling,
and show both native and Flatpak application paths. The next step is not more
live-VM sculpture. The next step is to turn the working VM135 evidence into
package contracts, pipeline gates, and a small netboot/unattended installer.

## Demo wins to preserve

- LightDM, X11, keyboard, mouse, and Enlightenment can form a usable installed
  workstation session when package ownership, permissions, and session state are
  respected.
- Flatpak can install and run useful GUI apps; Firefox and LibreOffice Flatpak
  were especially useful reference points for launch/session behavior.
- Native LibreOffice Writer and Calc launched visibly after the wrapper was
  moved back toward LibreOffice's own startup model instead of direct
  `soffice.bin` admin-style launching.
- Podman is viable as a filmable AUZiX story: AUZiX BusyBox, AUZiX Nginx, and a
  simple Python/Flask-style service are the right first demo set.
- The strict-root experiment showed that compatibility paths can shrink over
  time, but today they remain a cataloged compatibility lane rather than a
  blocker for the workstation snapshot.

## Lessons folded into contracts

- A package is not complete just because files unpack. It must preserve
  ownership, modes, setuid/sticky bits, generated state expectations, lifecycle
  hooks, desktop entries, and user-writable cache/config boundaries.
- Debian package metadata and maintainer scripts are guidebook evidence. AUZiX
  wrappers may translate paths, but they should not invent replacement behavior
  when the package already declares what it needs.
- Desktop launchers are promotion gates, not decoration. Direct command launch
  must pass first, then E menu launch must pass, then duplicate/dead entries can
  be hidden.
- LibreOffice launchers must use LibreOffice's own `soffice`/module scripts and
  package-owned runtime layout. The `fundamentalrc` path must stay relative to
  the runtime tree (`BRAND_BASE_DIR=${ORIGIN}/..`) instead of pointing at stale
  `/System/State` copies.
- Impress and Draw need stronger gates than process existence. For now isolated
  `UserInstallation` profiles are allowed only when explicitly recorded in the
  wrapper contract and proven with visible module launches.

## Current known gaps

- `AuzixInstallerEfl` and `AuzixPackageManagerEfl` are broken/twitchy again and
  should not be the default netboot path. They move to post-install validation
  until EFL library/data paths, DBus/session behavior, efreet cache behavior, and
  user-owned writes are clean.
- Native LibreOffice Impress/Draw need one more package-owned validation pass;
  Flatpak LibreOffice is a useful reference, not the final native answer.
- Some E/efreet theme and cache warnings remain, including theme filter noise
  such as `blurhighperf`; separate real launcher failures from cosmetic theme
  warnings.
- Some Flatpak apps still expose DBus/system-helper/session gaps. Flatpak itself
  is a package group with validation, not an ISO-core assumption.
- Midori, ephoto, editor choices, and the broader userspace wave need the same
  lifecycle-preserving package rebuild discipline before they are considered
  film-stable.

## Snapshot strategy

1. Freeze VM135's demo state as reference evidence only.
2. Rebuild the affected package artifacts from patched scripts/contracts:
   `LibreOfficeCommon`, `LibreOfficeWriter`, `LibreOfficeCalc`,
   `LibreOfficeImpress`, `LibreOfficeDraw`, desktop integration, installer core,
   and any E/efreet/session packages touched by the demo repair.
3. Publish those artifacts to the AUZiX repository and install them onto a
   disposable target instead of relying on VM live edits.
4. Run workstation gates in order: base shell/tools, network/SSH, LightDM input,
   E session, terminal, package manager CLI, menus, native Office, Flatpak,
   Podman.
5. Only after package-owned validation passes, snapshot the user workstation
   state for installer/package-group defaults.
6. Build the new tiny netboot ISO with installer-core only. GUI installer
   frontends are excluded from the required tiny acceptance path until
   separately revalidated.
7. Unattended install consumes a checked plan JSON and writes receipts containing
   selected package groups, target disk, repository index checksum, installer
   profile id, and validation result.

## Pipeline shape

- `tiny-netinstall`: proves boot, network, SSH/TUI installer, ext4 tools, package
  refresh, unattended plan parsing, and receipts.
- `workstation-hydrate`: installs selected package groups after base install and
  runs tiered gates rather than boiling the whole desktop at once.
- `desktop-frontends`: validates EFL installer/package-manager frontends from an
  already working desktop session.
- `demo-containers`: stages AUZiX BusyBox, AUZiX Nginx, and Python/Flask demo
  containers with notes and HTTP probes.

This keeps the installer small, the workstation reproducible, and the demo magic
where it belongs: in packages we can rebuild, not in a haunted VM.
