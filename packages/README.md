# AuZiX package catalogs

This directory records package intent; it is not proof that a package is
published or runtime-ready.

- `base-ports.manifest.json` owns bootstrap through the first EFL edge.
- `extended-ports.manifest.json` orders storage/filesystem and OCI host ports.
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

The flat files under `profiles/packages/` are assembly wish lists. A listed
package must still graduate through a JSON manifest, emit an AuZiX receipt, and
pass its declared checks before publication.

`planned` means ordered intent only, `first-pass` means a build script exists
but has not graduated, `seed` means enough detail exists to start a port, and
`ready` means a prior pattern exists but fresh evidence is still required.
Ollama receives only a failed target's manifest entry, command, log
tail, linker evidence, and receipt. It may propose a bounded contract change;
it never publishes packages or advances their state.
