# VM135 desktop session repair — 2026-08-12

## What broke

VM135 had `/dev/input/event*` nodes and correct-looking groups, but udev did not tag
the devices with `ID_INPUT*`. Xorg/libinput therefore could not reliably auto-add
keyboard and mouse devices after reset.

The Trixie reference VM132 showed the expected state:

- `/usr/lib/udev/rules.d/60-input-id.rules`
- `/usr/lib/udev/hwdb.bin`
- `udevadm info --query=property --name=/dev/input/event*` includes `ID_INPUT*`
- Xorg log includes `config/udev: Adding input device ...` and `Using input driver 'libinput'`

VM135 was missing the input-id rule/helper surface.

## Fix applied

- Added modern `/usr/lib/udev` copying to `scripts/build-auzix-udev-package.sh`.
- Added `scripts/repair-auzix-desktop-session.sh` as the repeatable desktop contract repair.
- Deployed Trixie reference `60-input-id.rules` and `hwdb.bin` to VM135 for immediate recovery.
- Restarted udev and LightDM.
- Added the repair hook into VM135 `/System/Boot/StartSequence`.
- Patched `scripts/add-auzix-live-tools.sh` so generated boot media calls the same repair hook.

Current VM135 proof:

```text
xorg_input_mode=udev-libinput
udev_input_tags=true
Xorg: config/udev added QEMU USB Tablet, AT keyboard, VMware VMMouse
LightDM -> enlightenment_start -> enlightenment running
```

## Secondary package activation fix

`Procps` was installed but `ps` failed because `libproc2.so.0` was not exposed from
the installed package RootFS into the compatibility library ladder.

`scripts/activate-auzix-basic-config.sh` now exposes top-level library files from:

- `RootFS/usr/lib/x86_64-linux-gnu`
- `RootFS/lib/x86_64-linux-gnu`
- `RootFS/usr/lib`
- `RootFS/lib`

It skips duplicate `current/RootFS` aliases.

VM135 proof:

```text
ps from procps-ng 4.0.4
htop 3.4.1
```

## LibreOffice Impress fix

`loimpress` had an overly long generated `LD_LIBRARY_PATH`, appending four library
directories for every dependency in the LibreOffice closure. This caused:

```text
/usr/bin/loimpress: exec: ... ld-linux-x86-64.so.2: Argument list too long
```

`scripts/build-auzix-debian-intake-package.sh` now keeps the dependency closure for
fonts/share/settings discovery, but uses the activated compatibility library ladder
for loader paths.

VM135 proof:

```text
localc --version     -> LibreOffice 25.2.3.2
lowriter --version   -> LibreOffice 25.2.3.2
loimpress --version  -> LibreOffice 25.2.3.2
```

## Still open

- 2026-08-13 follow-up: `XTerm`, `Midori`, `NetSurf`, and `Geany` were present in
  the repository index but not consistently installed/exposed on VM135. Installing
  them with `auzix-pkg install <name>` and rerunning activation restored:
  `xterm`, `uxterm`, `midori`, `netsurf`, `netsurf-gtk`, and `geany`.
- `leafpad` is not the installed package name; VM135 has `L3afpad`. A compatibility
  alias `leafpad -> /Programs/L3afpad/current/Commands/l3afpad` is now part of
  activation.
- `Ephoto` install exposed an `auzix-pkg` dependency-cycle loop around EFL packages
  (`Libecore*`, `Libevas*`, `Libeeze1`, `Libelput1`). Several dependencies installed,
  but the Ephoto install wave was stopped before convergence. This needs a package
  manager cycle-handling fix before retrying.
- `enlightenment_remote -restart` failed because the user session DBus path is still
  incomplete: `dbus-launch terminated abnormally`.
- Full package activation is now marker-gated in the repair script, but package
  installation should invalidate `/System/State/packages/activation-basic.ok`.
- The Udev package should be rebuilt from the corrected script and republished to
  the AUZiX package repo; VM135 currently has the immediate repaired surface.
