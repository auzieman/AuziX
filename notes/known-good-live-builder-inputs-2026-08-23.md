# Known-good live builder inputs — 2026-08-23

This is the recenter point for the beta/live graphical boot lane.

The problem is not the kernel. The known-good graphical live ISO already proved
the kernel/initramfs handoff, device probing, DBus, Xorg, and Enlightenment can
come up. Recent failures came from drifting away from the known live root/squash
package spine, mutating symlinks/libs/runtime paths, and stopping rebuilds just
short of the actual X11/E/DBus package set.

## Proven artifact

- `artifacts/auzix/auzix-live-theme-app-candidate.iso`
- ISO SHA-256: `dbc37d309059b70cc39e37b7a5e0be7d27dae770654bf3ccf7ddf7d142c25cb6`
- Embedded squashfs SHA-256: `7e2cc1a249e76c2711dd3659fc5485637229e9afd158584b6c937104ed37220a`
- Runtime note: `artifacts/auzix/KNOWN_GOOD_LIVE_BASELINE.txt`

## Known-good squashfs PackageDB receipts

Extracted from `/live/auzix-root.squashfs` in the proven artifact:

```text
ALSA-host
Acpid-host
AuzixDynProbe-0.1
AuzixInstaller-0.2
AuzixPackageTools-0.1
AuzixProbe-0.1
AuzixThemes-2026.06
AuzixWallpapers-2026.06
Bash-5.2-host
BusyBox-1.36.1
Curl-7.88.1-10+deb12u14
DBus-host
DesktopAssets-auzietek
Dialog-1.3-20230209-1
Enlightenment-0.25.4-2
GRUB-2.06-13+deb12u2
IPUtils-3:20221126-1+deb12u1
KernelModules-6.1.0-48-amd64
LightDM-host
Lua-5.4.4-3+deb12u1
Midori-11.8
NetSurf-3.10-1+b3
OpenSSH-host
PulseAudio-host
Strace-host
Sudo-host
Terminology-host
Udev-host
XTerm-379-1
Xorg-host
root-layout
```

## Builder rule

For the beta graphical/live lane, recover this package-composed squashfs/root
input first. Do not micro-build a new partial root that stops short of X11,
DBus, LightDM, or Enlightenment. Do not change kernel/module logic while
recovering this lane.

The next live/HDD image should be this known-good spine plus declared fixes
only:

- CA/Midori trust fix;
- theme/background preseed fix;
- installer payload/UI fix;
- package manager state/dependency-loop fix;
- no live relinking of existing core libc/loader/symlink substrate.

Strict/no-legacy-path work remains valid, but it is a separate proof lane. The
beta graphical lane starts from the proven squashfs package spine above.
