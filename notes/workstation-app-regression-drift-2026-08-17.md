# Workstation app regression drift — 2026-08-17

## Symptom

Apps that were previously proven or semi-proven on vmid135 are now absent from
menus or fail to launch:

- Terminology
- L3afpad / Leafpad alias
- Geany
- native LibreOffice modules

## What history shows

This is not one single app failure. It is a lane-mixing regression.

The known-good graphical ISO/profile used a lean, proven desktop substrate:

```text
Xorg=host
LightDM=host
DBus=host
PulseAudio=host
Terminology=host
Enlightenment=0.25.4-2
Midori=11.8
Curl=7.88.1-10+deb12u14
BusyBox=1.36.1
```

Later vmid135 demo state layered apps from the larger package repo and live
hotfixes:

- `L3afpad`/Leafpad alias was added by activation once the real L3afpad command existed.
- `Geany` was installed from repo and restored by rerunning activation.
- LibreOffice Writer/Calc/Impress had live wrapper fixes for runtime library
  ladder and module command routing.
- `desktop-first-wave-launchers.profile.json` captured the visible launcher
  targets, but not the exact package generation lane.

The current full repo contains newer Trixie intake substrate:

```text
Libc6=2.41-12+deb13u3
Zlib1g=1.3.1 trixie
Libglib200t64=2.84.x
Libgtk30t64=3.24.49
LibreOffice*=25.2.3
L3afpad=0.8.18.1.11
Geany=2.0
```

The current live ISO/runtime substrate is older/proven (`Libc6` observed as
2.36 through `/System/Libraries/Runtime/glibc`). Resolving workstation app names
against the full repo lets leaf apps pull toward a newer substrate than the ISO
is running.

## Drift point

The working state was not captured as one versioned repo/profile lane. It lived
as:

```text
lean known-good ISO
  + selected full-repo app installs
  + live wrapper hotfixes
  + desktop launcher/profile cleanup
```

Resetting or rebuilding the ISO without that complete lane loses the apps and
launchers. Installing them again from the full repo hits substrate drift.

## Correct recovery path

Do not continue live-fixing random launchers on vmid135.

Recover one named lane:

```text
workstation-demo-20260815
```

That lane must include:

1. exact base/runtime substrate identity;
2. exact app package identities;
3. wrapper fixes from the vmid135 notes;
4. desktop launcher profile;
5. activation/cache hooks;
6. validation probes for CLI and E launcher behavior.

Until that lane exists, `auzix-pkg` should either:

- hold/backtrack to app packages compatible with the active ISO substrate; or
- stop with `runtime-rebuild-required` and require a coherent runtime rebuild.

## Immediate next step

Find or reconstruct the last known vmid135/demo root state and extract:

```text
/System/PackageDB
/System/State/packages/installed.json
/Programs/*/current targets for L3afpad, Geany, LibreOffice*, Terminology
/System/Compatibility/usr/share/applications
/Users/auzix/.local/share/applications if used
```

Then turn that evidence into package-owned artifacts rather than live shell
patches.
