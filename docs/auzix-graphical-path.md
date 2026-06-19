# Auzix Graphical Path

## Direction

The first native graphical target should be Enlightenment, not COSMIC.

COSMIC is compelling for a workstation-class Auzix personality, but it pulls a
larger modern desktop stack and should come after the boot, package, service,
and graphics substrate are stable. Enlightenment is a better first graphical
checkpoint because it is dramatic, historically aligned with lightweight
desktop experimentation, and built around EFL rather than a full GNOME/KDE
style stack.

The official Enlightenment project describes it as a window manager, compositor,
and minimal desktop for Linux/BSD-style systems. Its current release stream also
keeps EFL and Enlightenment as source-buildable components, which fits the
Auzix path-migration experiment.

## First GUI Stack

Target stack:

```text
/Stacks/graphical-enlightenment
```

Initial package order:

```text
EFL
Enlightenment
terminology or a smaller terminal fallback
light display manager or direct launch script
mesa/drm/input libraries as needed
```

Current upstream release targets checked on May 24, 2026:

```text
EFL 1.28.1
Enlightenment 0.27.1
Terminology 1.14.0
```

Native path intent:

```text
/Programs/EFL/<version>
/Programs/Enlightenment/<version>
/Programs/Terminology/<version>
/Services/display-manager
/Services/seat
/System/Settings/display
/System/State/display
/System/Logs/display
/Work/Builds/graphical
```

## Debian Control Baselines

VMID 132 is the current known-good graphical control system.

On May 25, 2026, a minimal Debian 13 install at `192.168.1.50` built and
installed from source:

```text
EFL 1.28.99
Enlightenment 0.27.99
```

Both were installed with Meson/Ninja into Debian's default `/usr/local` prefix.
The captured build logs and Meson introspection files are under:

```text
out/debian-control/efl
out/debian-control/enlightenment
```

Important baseline findings:

- EFL and Enlightenment build cleanly from source on a small Debian base once
  the development dependency set is present.
- The default EFL build selected the X11 engines and installed `ecore-x`,
  `software_x11`, and `gl_x11`.
- The default EFL build did not enable the Wayland/DRM compositor path:
  `ecore_wl2`, `ecore_drm2`, and related Wayland canvas pieces were disabled.
- EFL built `elput` with `evdev`, `logind`, and root fallback support, which
  means Auzix should either provide a normal enough seat/session/device
  contract or deliberately configure a different input path.
- Enlightenment built with `elput`, `ecore-x`, PAM, PulseAudio mixer support,
  udev device backend, NetworkManager/ConnMan modules, and its first-run wizard
  modules. ALSA was not detected in the control build.

That makes the present Auzix failure more likely to be a runtime contract issue
than a mystery in Enlightenment itself: device discovery, input permissions,
`/run`/`/var` state, user home ownership, DBus/session behavior, and the chosen
display backend need to match what EFL/Enlightenment actually built.

On May 26, 2026, the source install was removed and Debian's distribution
packages were installed instead:

```text
enlightenment 0.27.1-1
EFL libraries 1.28.1-1
```

The package-install logs, uninstall logs, dependency list, installed package
list, `ldd` output, and backend path inventory are under:

```text
out/debian-control/packages
```

The distribution package baseline is more useful for Auzix's first GUI package
shape than the plain source build:

- It installs both X11 and Wayland session files.
- The Wayland session runs `env E_WL_FORCE=drm E_COMP_ENGINE=gl
  /usr/bin/enlightenment_start`.
- `/usr/bin/enlightenment` links directly against `libecore_wl2`,
  `libefl_canvas_wl`, `libecore_drm2`, `libecore_x`, `libelput`, `libudev`,
  `libinput`, `libsystemd`, and `libdbus-1`.
- The EFL backend modules include `ecore_evas` engines for `drm`, `fb`,
  `wayland`, and `x`, plus Evas engines for `drm`, `gl_drm`, `wayland_egl`,
  `wayland_shm`, `gl_x11`, and `software_x11`.
- Installing just `enlightenment` on Debian pulled in 111 packages, including
  udisks2, PackageKit, xdg-desktop-portal, fprintd, BlueZ, GStreamer plugins,
  PipeWire libraries, filesystem helpers, and the EFL backend split packages.

For Auzix, this argues for staging the distro-package dependency shape first,
then trimming once the session is stable. The minimum useful graphical contract
is not only EFL plus the `enlightenment` binary; it also includes seat/input,
udev, DBus, systemd/logind-compatible behavior, Mesa/DRM/Wayland modules,
session files, helper binaries, and writable runtime state.

## First Boot Style

Do not make graphical boot the default immediately. The first GUI stage should
remain operator-controlled:

```sh
/System/Tools/start-e
```

That lets the shell-first ISO stay useful while we collect graphics, input,
seat, font, and library requirements. During VM bring-up, X11 is the default
operator path because Debian's packaged Wayland session can hang while the
DRM/seat contract is still incomplete.

`start-e` supports an explicit mode selector:

```sh
AUZIX_E_MODE=wayland /System/Tools/start-e
AUZIX_E_MODE=x11 /System/Tools/start-e
```

Wayland is the preferred native direction once DRM, input, and seat support are
available. X11 remains the early VM fallback because it is easier to diagnose
when the compositor path is incomplete.

The current live helper defaults to X11. `AUZIX_E_MODE=auto` also tries X11
before Wayland. Use explicit `AUZIX_E_MODE=wayland` only when testing the
DRM/Wayland path.

## Start Sequence

The strict installed root uses:

```text
/init
/System/Boot/StartSequence
```

This is intentionally closer to an Amiga-style startup sequence than a full
systemd adoption. The current sequence mounts runtime filesystems, starts
BusyBox DHCP, and runs executable `/Services/*/run` hooks. It keeps Auzix
single-user friendly while giving us a place to attach `seatd`, SSH, and later
a display-manager service.

Installed roots should not rely on this boot sequence to repair every persistent
permission problem. `auzix-install-disk` now runs
`/System/Tools/finalize-installed-root /Work/InstallTarget` after copying the
live root, and package extraction runs the same finalizer against `/` when it is
available. The finalizer owns persistent user-state and helper-mode invariants:
`/Users/auzix/.cache`, `.config`, `.local`, `.midori`, Enlightenment state,
`/Work/Temp`, `/dev/shm`, `/run/user/1000`, sudo, Xorg.wrap, and Enlightenment
privileged helpers.

## Asset Staging

Local Enlightenment backgrounds, themes, and selected config can be staged into
the strict root with:

```sh
make auzix-strict-e-assets
```

The files land under:

```text
/Programs/DesktopAssets/auzietek/Resources/display/assets
```

The package exports per-file links into E's inherited global catalogs:

```text
/System/Compatibility/usr/share/enlightenment/themes
/System/Compatibility/usr/share/enlightenment/data/backgrounds
```

Theme selection and desktop configuration remain per-user. The ISO builder
does not duplicate packaged assets under `live/assets`.

## COSMIC Later

COSMIC remains a good later target for a polished workstation edition:

```text
/Stacks/graphical-cosmic
```

It should follow after:

- apk/Auzix package wrapping is working
- OpenSSH access is boring
- containerd/BuildKit can build or import packages
- disk persistence is proven
- one smaller graphical stack has already mapped the display/input requirements
