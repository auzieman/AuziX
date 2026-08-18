# ESXi installer progress + Midori CA disk-root pass — 2026-08-16

Run focus: stop live-patching the disposable VM, rebuild from the AUZiX source/package/rootfs spine on lab-build, then validate on the ESXi AUZiX workstation media VM.

## Build artifact

- Builder host: lab-build / R730 (`lab-ai-worker`)
- Build container image: `auzix/builder:lab`
- Run id: `installer-progress-midori-r1-20260817T011953Z`
- Published ISO:
  `/var/lib/auzix-build/published/auzix-live-installer-progress-midori-installer-progress-midori-r1-20260817T011953Z.iso`
- Size: `764M`
- SHA256:
  `d34ed0a258ec6cd8ed06f696c1b6bc8f0917e3d15b00ca8c5175231ebff31e13`
- ISO validation:
  - BIOS + UEFI El Torito entries present
  - `Auzix strict root audit: PASS`
  - archive metadata audit: `archives=41 entries=2438 compared=2438 mismatches=0`
  - package metadata risk: no suspicious system-owner paths; sudo retains `4755`

## Live ISO validation

Boot target:

- ESXi VM: `auzix-esxi-workstation-media-01`
- ESXi VM id: `13`
- Live guest IP: `10.20.0.113`

Observed live boot:

- `/dev/sr0 on /run/live/iso`
- overlay root active
- SSH reachable as root
- `LD_LIBRARY_PATH` populated from AUZiX path source
- `curl -I https://auzietek.com` returns HTTP/2 200
- Midori wrapper syntax passes
- Midori launches far enough to report `Mozilla Midori 11.8`
- Midori NSS trust DB seeded with 150 CA entries during package build
- `/System/Tools/auzix-install-disk` emits:
  - `INSTALL_STAGE step=N total=9 label=...`
  - `INSTALL_DONE root=... layout=... bootloader=...`
- EFL installer source in package contains progress parser for `INSTALL_STAGE` and `INSTALL_DONE`

Live caveat:

- 14 host/proof-style `/Programs/*` directories lacked `current` symlinks in live mode. The installed-root finalizer repaired this on disk (`current_links_missing=0`). The same normalization should be applied earlier to the live root, not only during disk finalization.

## Disk install validation

Command run from live ISO:

```sh
/System/Tools/auzix-install-disk \
  --force \
  --repo https://auzix.auzietek.com/repo \
  --profile /System/Settings/install/auzix-vmid135-clean-workstation.packages \
  /dev/sda
```

Progress stream:

1. preparing target disk
2. partitioning simple AUZiX root
3. formatting filesystems
4. mounting target filesystems
5. copying AUZiX root
6. finalizing installed root
7. writing installed configuration
8. installing bootloader
9. syncing and unmounting

Completion:

```text
INSTALL_DONE root=/dev/sda1 layout=whole bootloader=grub
```

Booted from disk after disconnecting ISO:

- `/dev/sda1 on / type ext4`
- SSH reachable
- `current_links_missing=0`
- `LD_LIBRARY_PATH` populated
- installed repo URL written:
  `/System/Settings/packages/default-repository.url`
  -> `https://auzix.auzietek.com/repo`
- requested profile receipt written:
  `/System/Settings/install/requested-profile.path`
- live installer autostart disabled in installed user session:
  - `/Users/auzix/.config/autostart/auzix-installer.desktop.disabled`
  - `/Users/auzix/.e/e/applications/startup/auzix-installer.desktop.disabled`
- `curl -I https://auzietek.com` returns HTTP/2 200
- Midori wrapper syntax passes
- Midori reports `Mozilla Midori 11.8`

## Remaining targeted debts

Do not treat these as reasons to re-invent the installer path. They are now bounded package/rootfs tasks.

1. E first-run nag:
   - The ISO seeds packaged E defaults but still lets Enlightenment present first-run configuration.
   - Fix by fully pre-seeding `.e` / profile state from the known-good vmid135 theme/profile, not by clicking through each boot.

2. EFM instability:
   - Installed disk E reaches `MAIN LOOP AT LAST`, but `.e-log.log` shows an `enlightenment_fm` backtrace before recovery.
   - Compare EFM runtime/package state against Trixie vmid132 and the known-good AUZiX live state.

3. Desktop integration metadata drift:
   - Runtime audit reports `AuzixDesktopIntegration` declares menu/mime paths that are not staged:
     `/etc/xdg/menus/e-applications.menu`, desktop-directories, `auzix-flatpak.desktop`, mimeapps.
   - Fix metadata or stage files so E menus stop lying.

4. Live-root `current` symlink normalization:
   - Installed-root finalizer fixes host/proof package current links.
   - Apply equivalent normalization during live root staging before ISO.

5. Hostname/install identity:
   - Disk boot still reports `hostname=auzix-live`.
   - Add installed-hostname/default identity step during finalize-installed-root.

6. EFL UI finish state:
   - Backend emits progress events. Next EFL installer pass should visibly present progress and end with an unmount/reboot prompt instead of returning to a stale start view.

