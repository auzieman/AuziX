# VM145 is the alpha workstation reference

Read-only capture requested by the operator; raw inventory is in
`vm145-alpha-reference-2026-09-04.json`. No VM configuration or filesystem
changes were made.

PVE name: `Auzix-Alpha-R30-E-Menu-145`; 8 GiB scsi0 disk, disk-first boot,
4 cores, 8 GiB RAM. SSH address: `192.168.1.57`.

`/System/State/alpha-hdd-stage.receipt` identifies the userspace source:

- Image: `auzix/alpha:pre-hdd-final-20260904-r30-e-menu2`
- Image ID: `sha256:07b66b7fe24094ef36ec339aaca8e5a74294eec355ab64bf658f6eee1383c005`
- Anchor SHA-256: `dbc37d309059b70cc39e37b7a5e0be7d27dae770654bf3ccf7ddf7d142c25cb6`
- Kernel: `6.1.0-48-amd64`

The repaired VM is newer than this base image: capture live repairs as well
as the source identity. Do not assume exporting that old tag retains them.

## Manifest reconciliation

The VM has 409 APK inventory entries and 483 directories under `/Programs`.
Directory count is not a package count: alternate names and unregistered
payloads exist. EFL components, DesktopAssets and installer frontends are
present beyond the APK inventory. Sudo is under `/Programs/Sudo/host` with no
`current` link. These are delivery/registration details to reconcile, not
evidence that the software needs to be built again.

The VM's `/System/Settings/install/apk-groups/*.list` requests 90 packages.
The current pre-HDD group files omit none of them and add 13 explicit items:

- sudo, e2fsprogs, dosfstools and service runtime support;
- Podman, conmon, crun, containers-common, netavark and aardvark-dns;
- the APK package-manager EFL frontend, desktop integration and Flatpak
  runtime support.

These additions correspond to the already discussed alpha requirements.
The full workstation group lists and the separate minimal installer list
are different manifests and should remain distinct.

Flatpak already has persistent `org.gnome.Calculator` on stable and a Flathub
remote at `https://dl.flathub.org/repo/`. Earlier statements that only a
temporary smoke app had been installed were incomplete. Retain this real
application and its launcher in the reproduced alpha. This inventory capture
does not itself revalidate its GUI launch.

The APK CLI warns that the cached `https://auzix-repo.test:8443` index is
missing, but successfully reads the installed database. Public repository
configuration and trust remain release provisioning work.

Use this VM's manifest, script hashes and demonstrated behavior as the
comparison baseline for the next image. File presence or matching names alone
do not prove identical payloads, activation, permissions or launch behavior.
