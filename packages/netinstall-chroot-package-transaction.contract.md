# AUZiX netinstall existing-installer contract

This is the intended clean install path. It is not a live desktop repair loop,
and it is not a replacement installer. The existing AUZiX installer remains the
main engine; this contract only adds Debian-like preflight and post-install
sanity gates around it.

## Flow

1. Boot the lean netinstall/live ISO.
2. Bring up network and SSH.
3. Run a live preflight before touching the disk:
   - `BusyBox`
   - `AuzixPackageTools`
   - `E2fsprogs`
   - `Dosfstools`
   - `UtilLinux`
   - `Parted`
4. Prove the preflight tools are real:
   - `mkfs.ext4` or `mke2fs -t ext4` exists and can format a tiny scratch image;
   - block-device discovery works;
   - repo refresh works;
   - SSH/network are reachable enough to recover the install if graphics fails.
5. Run the existing installer:

   ```sh
   /System/Tools/auzix-install-disk --force --bootloader grub /dev/vda
   ```

   or, while GRUB is still being iterated:

   ```sh
   /System/Tools/auzix-install-disk --force --bootloader iso /dev/vda
   ```

6. Let the installer do the main grunt work using a package-built target root:
   - partition;
   - format;
   - mount `/Work/InstallTarget`;
   - scaffold a strict AUZiX root on the mounted target;
   - install the base boot/runtime package set into that target root using
     AUZiX package receipts and package lifecycle metadata;
   - run package lifecycle hooks and `finalize-installed-root` against the
     target root;
   - write fstab, boot config, install receipts.
   - preserve the reviewed JSON install plan when `AUZIX_INSTALL_PLAN` is set;
   - derive `/System/Settings/packages/first-boot-selection.list` and
     `/System/Settings/packages/first-boot-queue.json` for package hydration.

   A live-root copy is permitted only as an explicitly named compatibility
   fallback while the package-built root lane is being finished. Fallback runs
   must write `root_build_mode=live-copy-compat` into the install receipt and
   must normalize target symlinks before boot. The fallback is not the release
   install model.

7. Run installed-root sanity checks while `/Work/InstallTarget` is still mounted.
   Chroot may be used here, but only for validation or a declared post-install
   package group. It is not the primary install flow.

8. Unmount, disable/detach the ISO, hard power-cycle vmid135, and boot the real
   disk.

9. First boot acceptance:
   - LightDM appears;
   - keyboard and mouse work at the greeter;
   - `auzix` can log in;
   - Enlightenment starts without an explicit error dialog;
   - terminal launches;
   - menus contain only real launchable entries for the installed package set.

## Installer root filesystem target

   - ext4 is the normal target.
   - ext2 is emergency fallback only.

The installer must fail clearly before partitioning if ext4 tooling is expected
but absent. It must not silently produce an ext2 workstation image during a
normal run.

## Package-built base root seed

The first package-built install lane uses:

`profiles/packages/auzix-tiny-netinstall-remote.packages`

This seed is deliberately small:

- `BusyBox`
- `AuzixPackageTools`
- `AuzixInstaller`
- `OpenSSH`
- `Sudo`
- `CACerts`
- `Curl`
- `UtilLinux`
- `Iproute2`
- `E2fsprogs`
- `Dosfstools`
- `Parted`
- `Strace`
- `File`
- `AuzixServiceRuntime`

The package-built root acceptance gate is SSH-first, not GUI-first:

- `/init` exists and starts the installed AUZiX boot sequence;
- `/System/Tools/auzix-pkg` exists and can refresh the configured repo;
- `sh`, `cat`, `ls`, `mount`, `df`, `du`, `ip`, `curl`, `ssh/sshd`,
  `mkfs.ext4`, `parted`, `strace`, and `file` all execute from the installed
  root;
- CA trust is usable before browser or Flatpak tiers are attempted;
- the installed root records `root_build_mode=package-built`.

Desktop, office, Flatpak, Podman demos, wallpapers, screenshots, and themes are
selected package groups layered after this gate passes.

## Package group hydration

After the package-built base root is installed, package groups are installed in small,
auditable tiers. Each tier must use the normal AUZiX package path and its package
lifecycle metadata.

The installer may schedule package groups before first boot, but it must not
pretend package hydration happened during the destructive disk-copy phase. The
base installer writes the reviewed package intent into the installed root; the
hydration tier consumes that queue after the root filesystem, users, device
state, package database, and repository configuration are valid.

For each package tier:
   - install packages with `auzix-pkg`;
   - let `auzix-pkg` run declared package `hooks.post_install`;
   - run only the generated-state triggers owned by that tier;
   - validate files, links, permissions, command front doors, and required config surfaces;
   - stop on hard gate failure.

## Tier boundaries

`installer-preflight`

- Storage tooling only.
- No desktop cache rebuilds.
- No GUI repair.
- Required proof: `mkfs.ext4`, `mke2fs`, `e2fsck`.

`base-runtime`

- Runtime directories, users/groups, udev, DBus, service base.
- Required proof: `/run`, `/run/dbus`, target users/groups, service config surfaces.

`desktop-session`

- Xorg, input stack, LightDM, Enlightenment session entry, PAM/session handoff.
- Must mirror the working Debian/Trixie package-owned surfaces. These are not
  guesses; package ownership and maintainer scripts from vmid132/Trixie are the
  reference:
  - `x11-common` owns `/etc/X11/Xsession`;
  - `dbus-x11` and `dbus-user-session` own Xsession snippets;
  - `lightdm` owns `/etc/lightdm`, `/etc/pam.d/lightdm*`, and LightDM DBus/service files;
  - `xserver-xorg-input-libinput` owns `/usr/share/X11/xorg.conf.d` and Xorg input modules;
  - `libinput-bin`, `udev`, `xserver-xorg-core`, and device packages own udev/input rules;
  - `enlightenment-data` owns `/usr/share/xsessions/enlightenment.desktop`, Wayland session entry, and XDG menu files.

`desktop-generated-state`

- Only after desktop packages are installed.
- Run:
  - `update-mime-database`;
  - `update-desktop-database`;
  - `glib-compile-schemas`;
  - `gtk-update-icon-cache`;
  - efreet/E menu sync if the owning package provides it.

`workstation-apps`

- Office, editors, browser, graphics, multimedia, flatpak adapters, podman demos.
- Apps enter menus only after command/front-door validation passes.

## Installed-root sanity gates

Run these before detaching the ISO:

- `/Work/InstallTarget/init` exists and is executable.
- `/Work/InstallTarget/System/Boot/InstalledInit` exists.
- `/Work/InstallTarget/System/Settings/fstab` contains `LABEL=AUZIXROOT / ext4`
  for normal runs.
- `/Work/InstallTarget/System/Tools/finalize-installed-root` exists and has been
  run.
- `/Work/InstallTarget/System/State/install/installed-at.txt` exists.
- Package receipts exist under `/Work/InstallTarget/System/PackageDB`.
- Users and groups needed for first boot exist:
  - `auzix`;
  - `lightdm`;
  - `input`;
  - `video`;
  - `audio`;
  - `render`;
  - `tty`;
  - `users`.
- Desktop session files exist in AUZiX or compatibility path form:
  - LightDM config and PAM files;
  - X11 session scripts;
  - Enlightenment `.desktop` session entry;
  - DBus system/session configuration;
  - udev/libinput rules.
- Generated desktop state has either been created or is explicitly scheduled for
  first boot:
  - desktop database;
  - MIME database;
  - GLib schemas;
  - icon caches;
  - E/efreet menu cache.

## vmid135 operational rule

vmid135 ACPI shutdown is not trusted yet. For test cycles:

1. use hard stop;
2. change boot order/media explicitly;
3. hard start;
4. confirm whether the ISO or installed disk is booted before continuing.

## Current vmid132 guidebook

The current working Debian reference capture is:

`out/vmid132-debian-guidebook/session-input-lightdm-e-20260814T144036Z.txt`

That file is the source of truth for the immediate LightDM/X11/input/E session copy-map work.
