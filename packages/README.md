# AuZiX package catalogs

This directory records package intent; it is not proof that a package is
published or runtime-ready.

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
- `auzix-control-panel.intent.json` defines the read-only probe/report contract
  for making hardware, package, service, container, and session state visible
  from the AUZiX desktop.
- `package-validation.contract.md` defines the "real duck" gate: packages must
  install into an AUZiX validation root/container and pass stat/file/readelf/ldd,
  strings, launch smoke, and desktop-entry checks before desktop promotion.

The flat files under `profiles/packages/` are assembly wish lists. A listed
package must still graduate through a JSON manifest, emit an AuZiX receipt, and
pass its declared checks before publication.

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
