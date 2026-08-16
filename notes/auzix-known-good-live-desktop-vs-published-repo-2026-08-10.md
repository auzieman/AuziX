AUZiX known-good live desktop model vs published package repo
Date: 2026-08-10

Finding:
The working graphical live ISO is a package-composed squashfs model, not an ad-hoc hand edit. It includes the desktop stack as stage-1 compatibility/host packages and a full BusyBox applet compatibility surface. VM135 tiny installed root booted correctly, but package hydration used the published repo, whose user-facing package names now resolve to newer Debian-intake packages for several core desktop/runtime components.

Known-good live ISO inspected:
  artifacts/auzix/auzix-live-theme-app-candidate.iso
  payload: live/auzix-root.squashfs

Known-good live desktop packages present:
  Xorg=host
  LightDM=host
  DBus=host
  PulseAudio=host
  Terminology=host
  Enlightenment=0.25.4-2
  XTerm=379-1
  ALSA=host
  AuzixThemes=2026.06
  AuzixWallpapers=2026.06
  DesktopAssets=auzietek
  Midori=11.8
  NetSurf=3.10-1+b3
  Curl=7.88.1-10+deb12u14
  BusyBox=1.36.1
  AuzixPackageTools=0.1

Published repo drift observed at http://192.168.1.10/auzix/repo/index.json:
  Curl resolves to 8.14.1-2+deb13u4 stage-1-auzix-native-repack, while live uses 7.88.1 compat package.
  Xorg resolves to 1-7.7+24+deb13u1 staging native-repack, while live uses Xorg host package.
  Enlightenment resolves to 0.27.1-1 native-repack, while live uses 0.25.4-2 compat package.
  LightDM resolves to 1.32.0-6+b2 native-repack, while live uses LightDM host package.
  Pulseaudio resolves to 17.0+dfsg1-2+b1 native-repack, while live uses PulseAudio host package.
  Terminology resolves to 1.14.0-1 native-repack, while live uses Terminology host package.
  Strace resolves to 6.13+ds-1 native-repack, while live uses Strace host package.

Operational impact:
  A clean VM135 tiny install can boot and reach the repo, but installing desktop package names pulls a different stack than the working live ISO. This causes dependency cycles, missing dependencies, broken wrappers, and loss of the proven graphical behavior.

Package-level correction path:
  1. Restore/publish the known-good live desktop package receipts and archives into the active repo, or create explicit package IDs/profiles for the known-good set.
  2. Make the workstation/profile installer resolve those known-good package identities intentionally, not whichever duplicate/common name appears in the published repo.
  3. Keep Debian-intake/native-repack packages in a separate lane until they pass the same ldd/strings/CLI/GUI validation gates.
  4. Promote replacements only when they beat the live package contract; do not replace a working package by name merely because a newer Debian-intake artifact exists.

Immediate VM135 strategy:
  Boot or install from the known-good graphical ISO/profile first. Then apply package updates only from the known-good lane/profile. Treat the tiny netinstall as the future installer seed, not the workstation baseline for filming.

VM135 LightDM recenter result:
  The installed root reached SSH/network/repo, then failed to show a GUI because the root directory was accidentally owned by auzix with mode 0700. LightDM and DBus could start as root, but the greeter user could not traverse /, so Xauthority writes failed with misleading permission errors under /System/State/lightdm and later /var/lib/lightdm.

  Correct workstation invariant:
    /, /System, /System/Settings, /System/Compatibility, /Programs, /Services: root:root 0755
    lightdm home: /var/lib/lightdm
    /var/lib/lightdm and /System/Logs/lightdm: lightdm:lightdm 0755

  After restoring those permissions and hydrating the known-good GTK desktop runtime layer from the live ISO (mime database, icon themes, GTK themes, fontconfig/fonts, gdk-pixbuf/GTK/GIO loader trees), VM135 kept Xorg and lightdm-gtk-greeter running. Remaining warnings were non-fatal missing ConsoleKit/systemd/accounts-service style integration warnings, not the blocker.

Build/installer corrections applied locally:
  - build-auzix-access-package.sh now gives lightdm /var/lib/lightdm as home.
  - build-auzix-lightdm-package.sh stages /System/State/lib/lightdm/data/lightdm for the /var alias.
  - add-auzix-live-tools.sh repairs installed root permissions before StartSequence and before LightDM launch, and prepares /var/lib/lightdm.

Systemd workstation takeover finding:
  VM135 can execute the packaged Trixie systemd when it is launched with the
  matching packaged runtime:
    loader: /Programs/Libc6/2.41-12+deb13u3/RootFS/usr/lib64/ld-linux-x86-64.so.2
    libs: Libc6, LibsystemdShared, Libssl3t64, Libseccomp2, and systemd private libs

  Do not live-repoint /System/Compatibility/lib/x86_64-linux-gnu/libc.so.6,
  libm.so.6, or libcrypto.so.3 under a running AUZiX session. sshd and other
  already-running services can reset when the old dynamic loader sees the new
  libc. The package/wrapper contract should select the matched loader explicitly
  instead of swapping global compatibility aliases in place.

  First-class systemd units staged on VM135 for the next controlled takeover:
    /System/Settings/systemd/system/auzix-early-network.service
    /System/Settings/systemd/system/ssh.service
    /System/Settings/systemd/system/display-manager.service

  The intended order is network first, SSH second, graphical session last:
  auzix-early-network.service brings up non-loopback interfaces with udhcpc;
  ssh.service uses the staged OpenSSH config; display-manager.service waits on
  logind/DBus/network and then launches LightDM.
