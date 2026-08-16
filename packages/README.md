# AuZiX package catalogs

This directory records package intent; it is not proof that a package is
published or runtime-ready.

- `auzix-os.source.json` is the master AUZiX OS source contract.  It defines
  canonical roots, compatibility alias policy, inherited bootstrap environment,
  package extension rules, archive permission preservation, lifecycle phases,
  and validation expectations.  Package builders, Lua package tooling, ISO
  assembly, and validation containers should read this before adding local
  path or permission logic.
- `base-ports.manifest.json` owns bootstrap through the first EFL edge.
- `extended-ports.manifest.json` orders storage/filesystem and OCI host ports.
- `core-preinstall.queue.json` defines the package-built installer spine:
  storage, filesystem, wired/wifi networking, package fetch, diagnostics,
  and optional network/advanced-storage support that should be validated before
  the next ISO rebuild.
- `source-workbench.seed.json` defines the first desktop source-build lane.
- `source-build.sources.json` holds proven or experimental package contracts.
- `installer-ui.*.json` defines the executable installer UI package batch.
- `oci-and-python.queue.json` records the executable Podman dependency order
  and the deliberately scoped Python/Flask/MicroBlog follow-up batch.
- `flatpak-desktop.queue.json` records the post-Podman Flatpak desktop lane:
  Bubblewrap, OSTree, xdg-dbus-proxy, Flatpak, portals, and program adapters.
- `desktop-control-and-userapps.queue.json` records the next desktop round:
  AUZiX Control Panel, hardware/session platform packages, native dev/debug
  tools, and a measured wave of browser/office/art/chat app seeds.
- `vmid132-workstation-clone.profile.json` records the reference workstation
  clone contract: package manifest, dpkg closure, LightDM/session evidence,
  permissions, and fall-through gates captured from vmid132.
- `auzix-control-panel.intent.json` defines the read-only probe/report contract
  for making hardware, package, service, container, and session state visible
  from the AUZiX desktop.
- `package-validation.contract.md` defines the "real duck" gate: packages must
  install into an AUZiX validation root/container and pass stat/file/readelf/ldd,
  strings, launch smoke, and desktop-entry checks before desktop promotion.

The flat files under `profiles/packages/` are assembly wish lists. A listed
package must still graduate through a JSON manifest, emit an AuZiX receipt, and
pass its declared checks before publication.

`profiles/packages/auzix-vmid132-workstation.packages` is different from the
smaller exploratory lists: it is the guidebook-derived workstation manifest
captured from vmid132 (`trixie-smoke-132`) with `apt-mark showmanual`. Use
`scripts/validate-auzix-guidebook-manifest.sh` to compare it against the
vmid132 package export and classify fall-through gaps. A guidebook metadata
mismatch is a failure; a missing AUZiX receipt is a package-factory backlog
warning.

The ISO should be assembled from package groups, not from one-off file copies.
The intended model is:

- `boot-substrate`: kernel, initramfs, BusyBox rescue shell, SquashFS/overlay
  mounts, live media discovery, and enough networking to reach the package repo.
- `installer-core`: packages required before or during install, including
  `AuzixPackageTools`, `AuzixInstaller`, `E2fsprogs`, `Dosfstools`,
  `UtilLinux`, `Parted`, `CACerts`, `Curl`, `Iproute2`, wifi runtime,
  `Coreutils`, `Procps`, `File`, and `Strace`.
- `installer-optional`: packages the installer can offer or fetch early, such
  as NFS/CIFS clients, LVM, ZFS evaluation bits, additional filesystems, and
  hardware/firmware-specific network support.
- `installer-media-builder`: packages used to produce live/installer media
  from AUZiX package groups, including the Debian/Trixie `live-build` pattern,
  ISO creation, SquashFS, BIOS/EFI boot assets, and optional Debian installer
  media references.
- `desktop-proof`: demo/workstation packages installed by selection or post
  install, not automatically bloating the base ISO.

If an ISO contains a tool outside the boot substrate, that tool should also
exist as an AUZiX package with a receipt. If the installer needs a tool before
partitioning, the package belongs in `installer-core` or must have an explicit
bootstrap path.

`planned` means ordered intent only, `first-pass` means a build script exists
but has not graduated, `seed` means enough detail exists to start a port, and
`ready` means a prior pattern exists but fresh evidence is still required.
`desktop-ready` means the package is installable, link-clean, launch-clean, and
menu-clean under the package validation contract.
Ollama receives only a failed target's manifest entry, command, log
tail, linker evidence, and receipt. It may propose a bounded contract change;
it never publishes packages or advances their state.
# AUZiX package intents and source-backed porting

## Evidence-first port loop

Do not promote a desktop/service package from “archive exists” to
“workstation-ready” by chasing one missing library or one live VM error at a
time. The source of truth is:

1. Debian source recipe (`debian/control`, `debian/rules`, install manifests,
   maintainer helpers, tests).
2. Debian binary lifecycle (`preinst`, `postinst`, `prerm`, `postrm`,
   triggers, conffiles, DBus, Polkit, systemd/init, schemas, icons, desktop
   entries, users/groups, capabilities).
3. AUZiX path/runtime mapping.
4. AUZiX package build.
5. AUZiX validation container/root and vmid135 smoke.

Use the script collection:

```bash
scripts/collect-debian-auzix-package-slice.sh <slice> <source-package> <binary-package>...
```

The script writes:

```text
out/package-slices/<slice>/source-guidebook/report/guidebook.md
out/package-slices/<slice>/lifecycle/<binary>/report/lifecycle.md
out/package-slices/<slice>/auzix-fragments/<binary>.auzix-fragment.json
out/package-slices/<slice>/shell-fragments/<binary>.shell-fragments.json
out/package-slices/<slice>/reports/slice.md
```

The shell fragments are `translate-only` evidence. AUZiX should convert those
Debian maintainer-script decisions into narrow idempotent lifecycle hooks, not
blindly execute raw Debian reconfigure logic.

On the laptop, run this through the lab Docker context / builder container, not
against the laptop shell. The laptop is the operator keyboard; build/extract
work belongs on the lab builder path.

Initial desktop-session slices captured:

- `desktop-audio-session`: `pulseaudio`, `pulseaudio-utils`, `libpulse0`
  revealed DBus, init/systemd compatibility, users/groups, `/etc/pulse`, XDG
  autostart, and runtime directory assumptions.
- `desktop-login-session`: `lightdm`, `lightdm-gtk-greeter` revealed DBus,
  Polkit, systemd/init compatibility, capabilities, users/groups, and greeter
  policy surfaces.

These are not optional “nice to have” details. If AUZiX installs the binary but
misses these lifecycle surfaces, packages can appear present while Efreet,
LightDM, PulseAudio, Flatpak, Podman, or LibreOffice fail at runtime.
