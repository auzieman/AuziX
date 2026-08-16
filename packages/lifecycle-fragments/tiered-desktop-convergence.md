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
- `/Programs`, `/System`, `/Users`, `/Work`, compatibility aliases;
- package database readability.

Gate:

- boot reaches shell/SSH;
- basic commands work from AUZiX paths;
- package list/status can be queried;
- no menu or GUI work starts until this tier can explain itself.

If this tier fails, do not debug Enlightenment, Flatpak, or LibreOffice yet.

## Tier 1: runtime ladder and libraries

Scope:

- package-local `Libraries`;
- declared dependency packages;
- `/System/Libraries`;
- explicit `/System/Compatibility` only where accepted;
- wrapper environment: `PATH`, `LD_LIBRARY_PATH`, `XDG_*`, package data dirs.

Gate:

- `ldd` or equivalent runtime scan passes for every front-door command;
- `strings` scan shows no unhandled hardwired legacy path that matters at
  runtime;
- wrapper invokes the real binary and preserves argv behavior;
- failing apps are classified as missing package, missing lib, or bad path map.

If this tier fails, do not create a visible menu entry yet.

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
