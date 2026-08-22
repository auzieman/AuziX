# AUZiX Tiered Desktop Convergence

Goal: converge AUZiX vmid135 toward the known-good Trixie vmid132 desktop in
small, testable tiers.

This is deliberately not a giant “fix the desktop” bucket. Treat the workstation
like a website/CMS release chain: if a lower component is wrong, every higher
component can look broken. Fix and validate one tier at a time.

## Rule zero

For every tier, ask:

```text
What did Debian/dpkg do here?
What does AUZiX call that path/service/cache/user/group?
What tiny idempotent hook reproduces only that relevant behavior?
What probe proves it?
```

Do not guess from the symptom first. Farm the package evidence first, then map.

Default to repackaging, not recompiling. At this layer AUZiX is mostly applying
a path lens over the Debian package tree:

```text
payload tgz + metadata + lifecycle hooks + path matrix + probes
```

Only rebuild when the payload itself proves wrong.

## Tier 0: base filesystem and command floor

Scope:

- BusyBox/coreutils style front doors;
- shell, `cat`, `df`, `du`, `id`, `ps`, `env`, `ldd`/runtime inspection;
- proof-build forensic tools: `lsof`, `strace`, `file`, `readelf`/`objdump`,
  `strings`, `stat`, `find`, `jq`, `curl`, and real terminfo;
- `/Programs`, `/System`, `/Users`, `/Work`, compatibility aliases;
- package database readability.

Gate:

- boot reaches shell/SSH;
- basic commands work from AUZiX paths;
- package list/status can be queried;
- no menu or GUI work starts until this tier can explain itself.

If this tier fails, do not debug Enlightenment, Flatpak, or LibreOffice yet.

Proof builds are allowed to be larger than the base image. They must include
debug/forensic tooling early so failures can be inspected from inside AUZiX,
not only from the Debian builder. The shrink pass removes these tools later;
the proof pass keeps them.

Compatibility aliases are scaffolding, not the product. For proof builds,
record usage of `/bin`, `/sbin`, `/lib`, `/lib64`, `/usr`, `/var`, `/tmp`,
`/home`, `/root`, and `/opt`. Unless boot/login fails without them, run a
strict alias-gimp lane that disables or shadows the legacy root aliases and
then re-runs Tier 0 and Tier 1 probes. Any package that breaks must be
classified as:

- boot-essential alias dependency;
- runtime-wrapper path bug;
- missing AUZiX-native path export;
- upstream hardwire requiring an explicit compatibility contract.

Do not silently keep an alias because one app happened to need it.

## Tier 1: runtime ladder and libraries

Scope:

- package-local `Libraries`;
- declared dependency packages;
- `/System/Libraries`;
- explicit `/System/Compatibility` only where accepted;
- wrapper environment: `PATH`, `LD_LIBRARY_PATH`, `XDG_*`, package data dirs.
- substrate version boundaries: glibc/loader, libssl/OpenSSL, GLib/GIO,
  GTK/GNOME, EFL/Enlightenment/Efreet, Xorg/input/video, font/icon/MIME/cache
  tooling.

Gate:

- `ldd` or equivalent runtime scan passes for every front-door command;
- `strings` scan shows no unhandled hardwired legacy path that matters at
  runtime;
- wrapper invokes the real binary and preserves argv behavior;
- failing apps are classified as missing package, missing lib, or bad path map.
- no leaf package is allowed to upgrade or shadow the active runtime substrate
  as a side effect. If a leaf package requires newer glibc, GTK/GNOME, Xorg,
  EFL, libssl, DBus/PAM/Polkit, or cache/tooling substrate, either hold/backtrack
  to a compatible package version or stop and schedule a runtime-layer rebuild.

If this tier fails, do not create a visible menu entry yet.

Substrate changes are not spot fixes. Rebuilding the base/runtime stratum first
and then rebuilding newer packages is valid; force-installing a newer substrate
component into a running live desktop is not.

## Tier 2: service and session substrate

Scope:

- DBus system/session bus;
- Polkit;
- PAM;
- LightDM;
- Xorg input/video;
- runtime dirs and users/groups;
- cgroups/proc/sys/dev where needed by Podman/desktop services.

Gate:

- LightDM accepts keyboard/mouse;
- login starts a stable session;
- system/session DBus probes pass;
- Polkit probes are classified;
- service starts are receipt-backed.

If this tier fails, desktop apps may be installed but should not be treated as
app failures yet.

## Tier 3: desktop shell and integration caches

Scope:

- EFL/Efreet;
- Enlightenment session wrapper;
- themes;
- icons;
- MIME/open-with;
- `.desktop` files;
- E menu cache;
- GSettings schemas where used by GTK/GNOME apps.

Gate:

- terminal/file manager launch from menu;
- no duplicate or broken visible menu entries;
- package intake may import donor `.desktop` files only as hidden/quarantined
  evidence until a package or profile publishes one canonical launcher;
- failed menu launches must include the exact Enlightenment log tail before any
  package rebuild or launcher rewrite is attempted;
- categories make sense: System, Internet, Office/Productivity, Graphics,
  Multimedia, Development, Utilities;
- hidden/pending apps stay hidden until their Tier 1 and front-door probes pass;
- Efreet and XDG cache refresh receipts exist.

If this tier fails, fix menu/cache/export logic before rebuilding applications.

## Tier 4: first application wave

Scope:

- terminal fallback;
- htop/glances/process tools;
- Leafpad/Geany/Pluma;
- AbiWord/Gnumeric;
- Midori or browser fallback;
- Ephoto;
- Podman demo containers.

Gate:

- each visible app has exactly one sensible menu entry;
- each entry launches;
- each command passes runtime ladder validation;
- over SSH, `Cannot open display` is a GUI front-door signal, not a library
  failure; use E launch logs for the real GUI result;
- each app has a receipt explaining `ready`, `missing-dep`, `hidden`, or
  `needs-rebuild`.

## Tier 5: heavy workstation applications

Scope:

- LibreOffice modules;
- GIMP/Inkscape;
- Flatpak browsers/editors;
- GNOME control center/system settings;
- future IDE/editor bundle.

Gate:

- CLI tools work where available;
- GUI launches from menu;
- sample files open;
- Flatpak system helper/portal/dbus/polkit state is valid;
- failures feed the package bake-in queue, not ad-hoc shell tweaks.

## Promotion rules

A fix is allowed to move upward only when lower tiers are green or explicitly
waived in the receipt.

A live-host fix graduates into a package when:

1. the Debian package evidence points to the same lifecycle action;
2. the AUZiX path mapping is explicit;
3. the hook is idempotent;
4. the validation probe is stable;
5. the package receipt can explain the result.

## Anti-patterns

- Rebuilding a heavy package because a menu cache is stale.
- Adding visible menu entries for commands that fail `ldd`.
- Replaying raw Debian maintainer scripts instead of translating their relevant
  lines.
- Changing root compatibility aliases as a casual spot fix.
- Treating vmid135 symptoms as truth without comparing vmid132 and package
  lifecycle evidence.
