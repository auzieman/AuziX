# Alpha HDD r28 Enlightenment runtime regression

VM143 booted the checksum-verified r28 HDD, brought up networking, SSH, Xorg,
udev input, and the graphical-session supervisor, but displayed a black screen.
This was not host startup contention.  Enlightenment repeatedly exited during
compositor initialization.

## Repeated known failures

The installed HDD had repeated two failures already documented and repaired on
VM135:

1. The secure-loader compatibility path retained the anchor's glibc 2.36
   `libc.so.6` and `libm.so.6`.  Current Trixie E/EFL requires GLIBC 2.38 or
   newer, while `/Libraries` correctly published Libc6 2.41.  The setuid
   `enlightenment_system` helper ignores `LD_LIBRARY_PATH`, so the main E
   wrapper could start but its helper could not.
2. HDD staging filled absent compatibility paths from the older graphical
   anchor before selecting executable EFL modules.  The result mixed
   Enlightenment 0.27/EFL 1.28 libraries with `v-1.26` Evas and Ecore_Evas
   modules.  After fixing glibc, E failed at software-X11 compositor creation.

## VM143 live proof

The live repair preserved the displaced files under:

```text
/System/Backups/20260901-r28-pre-libc241
/System/Backups/20260901-r28-pre-efl128
```

It then:

- promoted `/Libraries/ld-linux-x86-64.so.2`, `libc.so.6`, and `libm.so.6`
  through the secure compatibility paths;
- overlaid current package-owned Enlightenment/Evas/Ecore_Evas/Edje/
  Ecore_IMF/Elementary executable trees;
- removed stale `v-1.26` module directories and restored executable/setuid
  modes.

Proof after recovery:

```text
Compositor Init Done
MAIN LOOP AT LAST
```

Xorg and Enlightenment remained running.  The current package-owned
`enlightenment_system` helper also matched its compatibility copy by SHA-256.

## Media-builder correction

`scripts/stage-auzix-alpha-hdd-root.sh` now treats the anchor as an absent-only
hardware/boot spine, never as owner of the current EFL executable generation.
It overlays the installed current module providers, forces the matched Libc6
secure-runtime trio, and rejects an HDD root unless:

- secure loader/libc/libm resolve to `/Libraries`;
- the active privileged E helper matches the installed Enlightenment package;
- software-X11 and Ecore_Evas X modules are executable `v-1.28` modules;
- no `v-1.26` executable module directory remains.

This remains transitional HDD closure.  The long-term package contract is for
APK activation to own these compatibility surfaces directly, with the media
writer adding only kernel, boot, device, and filesystem state.
