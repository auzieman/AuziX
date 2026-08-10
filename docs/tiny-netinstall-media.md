# AUZiX tiny netinstall media

The tiny netinstall image is the AUZiX equivalent of Debian netinst discipline:
boot a very small, remotely reachable installer environment, then hydrate the
real system from package groups.

The AUZiX service container already proves the strict userspace shape can work
without carrying a kernel. The tiny netinstall image is that shape plus the
boot substrate:

- kernel and matching modules;
- initramfs;
- BIOS/UEFI boot assets;
- ISO/live-root discovery;
- SquashFS plus one writable overlay;
- network, SSH, package tools, and disk tools.

It is not the workstation image. LightDM, Enlightenment, LibreOffice, Flatpak
apps, Podman demo images, wallpapers, screenshots, and large themes are
post-install package groups.

## Debian reference pattern

Debian's `simple-cdd` sits above `debian-cd` and keeps customization small:

- `profiles/NAME.packages` lists desired top-level packages;
- `profiles/NAME.preseed` answers installer questions;
- `profiles/NAME.postinst` finishes target-root configuration;
- build logs record which lower tool ran and with what variables.

AUZiX should mirror that structure with AUZiX profiles and receipts, not with
one-off root stuffing. The profile added for this lane is:

- `packages/tiny-netinstall-remote.profile.json`
- `profiles/packages/auzix-tiny-netinstall-remote.packages`

## Acceptance gate

This image passes only when a disposable VM can be remotely entered before any
desktop stack is present:

1. ISO is below 1 GiB.
2. BIOS and UEFI boot entries are present, unless explicitly labelled otherwise.
3. Kernel, initramfs, and `live/auzix-root.squashfs` are present.
4. DHCP or declared static networking comes up.
5. SSH starts before any graphical installer path.
6. Root key login, or a declared lab-password profile, works.
7. `auzix-pkg refresh` reaches the configured package repository.
8. `mkfs.ext4`, `parted`, `mount`, `df`, `du`, `strace`, and `file` are usable.

If the GUI freezes, this profile should still be reachable. If it is not
reachable, the build failed regardless of how much of the installer painted.

## Non-goals

This profile deliberately excludes:

- display manager and Enlightenment;
- office/productivity applications;
- Flatpak applications;
- Podman demo workloads;
- artwork/demo media.

Those belong to post-install package groups once the base root is landed.
