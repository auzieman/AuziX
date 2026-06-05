# Auzix KVM-First Plan

## Goal

Create a minimal x86_64 Linux image that boots reliably under KVM/QEMU and
uses an Amiga-inspired filesystem layout:

- `/system`
- `/work`
- `/ram`

The point of this track is speed and clarity. It gives us a fast loop for root
filesystem and desktop decisions before trying to force the same ideas onto
harder hardware targets.

## Naming

Working distro name: `Auzix`

This can change later. For now, the important thing is the boot model and the
filesystem contract, not branding.

## Design Rules

1. Boot in KVM first, not on Tabor first.
2. Keep the kernel and boot flow conventional.
3. Put experimentation into image layout, init, and userspace policy.
4. Treat `/system`, `/work`, and `/ram` as a userspace and mount-layout design.
5. Defer package-manager ideology until after the first graphical boot works.

## Filesystem Model

### Core mounts

- `/system`: persistent OS tree, initially ext4 on the root disk
- `/work`: persistent mutable state, initially a second ext4 partition
- `/ram`: tmpfs mounted at boot

### Compatibility mapping

Initial Linux compatibility should be done with symlinks or bind mounts:

- `/home -> /work/home`
- `/var -> /work/var`
- `/srv -> /work/srv`
- `/tmp -> /ram/tmp`
- `/root -> /work/root`

This keeps ordinary Linux software usable while the visible top-level layout
still feels Amiga-influenced.

### What not to do yet

- no kernel patching just to rename standard paths
- no custom VFS semantics
- no read-only system image until the mutable layout is proven
- no union/overlay root unless a real need appears

## Bootstrap Recommendation

For the first successful boot, use a normal Debian-based rootfs with `apt`
available for base system construction.

Why:

- fast and well-understood KVM path
- easy package availability for Enlightenment, Midori, and basic networking
- avoids mixing boot debugging with source-based distro construction

This does not prevent a later move toward:

- Gentoo-style source builds
- Flatpak for user apps
- containerd for service isolation
- a more opinionated package story

## Service Strategy

Near-term:

- keep the host OS small
- keep only essential boot, display, network, and input services
- do not design around heavy service sprawl

Pragmatic first boot recommendation:

- allow a conventional init stack for the first KVM image
- minimize enabled services aggressively
- revisit OpenRC, s6, or other alternatives only after the image boots cleanly

Trying to replace init, package delivery, desktop stack, and filesystem layout
all at once is the wrong failure mode.

## Desktop Direction

The first graphical milestone should be one lightweight desktop path, not many.

Recommended order:

1. Xorg or Wayland session with basic input, display, and networking
2. Enlightenment desktop
3. one or two small browser/app targets

Preferred early app set:

- Midori if available and maintained in the chosen base
- Firefox ESR if Iceweasel naming is no longer practical in the chosen distro
- a terminal, file manager, and network manager UI
- `mkvtoolnix-gui` if we want to intentionally pull a wider multimedia/desktop
  dependency slice into early image experiments
- `kitty` as the preferred stronger terminal, with a lighter fallback terminal
  still acceptable during early bring-up

`elementary` should still be treated as a later desktop-stack target unless we
explicitly decide to adopt more of Pantheon. The current Debian-oriented seed
can at least carry `elementary-icon-theme` now, but it does not yet represent a
full elementary desktop.

## Phased Build Plan

## Phase 0: KVM shell boot

Deliverables:

- x86_64 kernel
- initramfs
- raw or qcow2 disk image
- serial console login in QEMU/KVM

Success criteria:

- boots with no board-specific hacks
- `/system`, `/work`, and `/ram` mount as intended
- network works in the guest

## Phase 1: Minimal persistent image

Deliverables:

- image builder that creates:
  - partition 1: boot
  - partition 2: `/system`
  - partition 3: `/work`
- first-boot init logic that creates compatibility directories and symlinks

Success criteria:

- reboot preserves `/work`
- `/tmp` and other scratch paths land in `/ram`
- normal packages run without path breakage

## Phase 2: Thin desktop

Deliverables:

- graphical login or auto-login test profile
- Enlightenment session
- NetworkManager or equivalent minimal networking path
- terminal emulator and browser

Success criteria:

- desktop starts in KVM without manual recovery work
- browser and terminal run normally
- memory footprint stays intentionally small

## Phase 3: App and service containment

Deliverables:

- evaluate Flatpak as the preferred user-app path
- evaluate containerd for service packaging where it makes sense
- keep the base OS narrow and explicit

Success criteria:

- user-facing apps are separable from the base OS
- service isolation improves maintainability without breaking the minimal model

## Repo Implications

The current repository is still mostly Tabor kernel tooling. The next sensible
repo changes for Auzix are:

1. add an x86_64 image-builder script path
2. add rootfs profile files separate from kernel profiles
3. add a first-boot init script that establishes `/system`, `/work`, `/ram`
4. add a QEMU/KVM runner for local validation

The first rootfs package seed now lives at:

- `profiles/rootfs/auzix-thin-desktop.debian-packages`

The first image builder now lives at:

- `scripts/build-auzix-x86-image.sh`

There is now also a pragmatic Vagrant/libvirt path for faster review loops:

- `Vagrantfile`
- `scripts/provision-auzix-vagrant.sh`

## Immediate Next Step

Do not start with Flatpak, Snap, or containerd.

Start with a bootable KVM image builder that proves:

- partition layout
- mount layout
- init behavior
- basic networked shell access

Once that works, add the desktop on top.
