# AUZiX Package Lifecycle Contract

Purpose: make package integration explicit, repeatable, and queryable instead
of relying on partial Debian layout copies or one-off repair scripts.

The root inheritance contract lives in `packages/auzix-os.source.json`.  Treat
that file as the OS-level `.source`: packages inherit its canonical roots,
bootstrap environment, compatibility alias policy, archive preservation rules,
and lifecycle vocabulary before adding package-local paths or hooks.

AUZiX packages are payload archives plus metadata. In the common case the
payload is already good enough; the missing work is the expansion contract:

```text
payload tgz
  + package metadata
  + path/export matrix
  + lifecycle hooks
  + validation probes
  + receipts
```

Repackaging is therefore a first-class operation. It can update metadata,
wrappers, service exports, menu entries, cache hooks, users/groups, permissions,
and validation probes without recompiling the software.

AUZiX package lifecycle has two modes:

```text
setup
  first-time application of package lifecycle state after install/extract

fix
  idempotent reconcile of an already-installed package or stack
```

Both modes use the same package lifecycle declaration and the same path mapping
rules. `setup` is stricter about required inputs; `fix` is stricter about
reporting drift and avoiding destructive changes.

## Central package state contract

`auzix-pkg` owns package truth. Installers, first-boot hydration, GUI package
selection, and repair tools may build intent lists, but they must not become a
second package database.

The central installed-state file is:

```text
/System/State/packages/installed.json
```

For an alternate target root, the same path is used beneath that root:

```text
${TARGET_ROOT}/System/State/packages/installed.json
```

Installers may keep helper files such as transaction logs, selected package
lists, missing package lists, and human-readable breadcrumb files. Those helper
files are diagnostic artifacts only. Dependency decisions must be based on the
central installed-state file plus physical package evidence:

```text
/System/State/packages/installed.json
/System/PackageDB/*.auzix.json
/Programs/<Name>/current
base runtime provider probes
```

During a package transaction, the installer/package engine must use this loop:

```text
load central installed-state
resolve next dependency
extract package preserving ownership, modes, sticky bits, setuid bits
write/update central installed-state
reload central installed-state before resolving the next package
```

This mirrors the shape of `apt`, `dnf`, `yum`, and `pkgtools`: the package
manager owns central metadata and each package step commits visible state before
the next dependency decision. The AUZiX installer composes intent; `auzix-pkg`
commits package state.

The dependency-chain regression happened when the new resolver introduced an
install-wave memory list but did not fully close the loop back into central
state. Build-root generation for ISO and disk roots did not spiral because that
path already had a bounded rootfs assembly flow. The fix is not broad desktop
debugging; it is making every install path converge on the same central state
contract.

## Factory feedstock order

The AUZiX package factory is not bad; it must stop treating Debian/Trixie as the
first dependency source on every package. Trixie is reference/feedstock. The
active AUZiX base release and already-built AUZiX packages for that release are
the first dependency source.

Factory resolution order:

```text
active AUZiX base release
already-built AUZiX runtime/dev package artifacts for the same release lane
retained builder sysroot/dev substrate from dependency builds
Debian/Trixie metadata, binary packages, or source only when AUZiX lacks the
package or a deliberate base/runtime layer upgrade is in progress
```

Package profiles are dependency-ordered inputs, not throwaway package wishlists.
Do not sort them by default. If a profile lists base substrate, dependency
helpers, libraries, and applications in that order, the intake runner must keep
that order so dependents build against the retained builder tree instead of
falling through to fresh Trixie state.

## Runtime substrate version wall

Some packages are not ordinary leaf dependencies. They define the ABI and
session substrate that the running AUZiX environment is already using. Examples:

```text
glibc/loader/libm/NSS resolver
OpenSSL/libssl/libcrypto and CA trust
Xorg/input/video substrate
EFL/Enlightenment/Efreet
GTK/GNOME core libraries and data loaders
GLib/GIO/GSettings/DBus/PAM/Polkit
fontconfig/freetype/pango/cairo/gdk-pixbuf/icon/mime cache tooling
```

The C runtime has the strictest rule: an AUZiX root has exactly one active core
glibc. In normal package installs, `Libc6`, `LibgccS1`, and `GCC14Base`
dependencies are satisfied by `/System/Libraries/Runtime/glibc`. A package must
compile and validate against that core runtime. If it needs newer glibc symbols,
the answer is a planned core-runtime rebuild followed by rebuilding the package
set against the new core, not installing a package-scoped second glibc.

These packages form a versioned runtime stratum. A leaf package must not
silently install or shadow a newer substrate component into the running system
just because its Debian dependency list allows it. If multiple requested
packages require a newer `glibc`, `libssl`, GTK/GNOME, Xorg, EFL, or related
substrate than the active AUZiX runtime stratum, the resolver has only two safe
choices:

```text
1. select/hold an older compatible package version for the current stratum; or
2. stop the leaf install and require a planned base-runtime/desktop-runtime rebuild.
```

Substrate upgrades are release events. They must be built as a coherent runtime
layer first, then used to rebuild or validate newer leaf packages. They are not
per-app hotfixes and must not be applied by force-installing package libc,
GTK/EFL, or libssl over an active live root.

## Runtime linker lifecycle

Shared-library installs have a mandatory linker-cache stage. Debian packages
regularly express this through maintainer scripts and triggers such as
`ldconfig`; AUZiX must preserve that intent instead of hoping wrapper paths hide
it.

`auzix-pkg` refreshes the runtime linker after extraction/finalization/post
hooks, but the global cache is limited to the active runtime substrate:

```text
/System/Libraries
/System/Libraries/Runtime/glibc
/System/Compatibility/lib*
/System/Compatibility/usr/lib*
```

Package-local libraries under `/Programs/<Name>/current/RootFS` are not added to
the global loader cache. Those remain package-wrapper/runtime-ladder inputs.
This keeps leaf installs from making the running desktop accidentally load a
newer or incompatible libc, EFL, GTK, OpenSSL, or other substrate library.

If a leaf transaction would require changing the global linker substrate, the
transaction must fail closed and become a planned base/security/desktop runtime
layer rebuild.

The wrapper/runtime-ladder model may expose leaf package libraries such as GTK,
ncurses, OpenSSL, font, media, or editor support libraries, but those libraries
must themselves be built against the active AUZiX core. It must not mix
incompatible C-library or desktop-session generations. In particular:

- package-scoped or alternate `Libc6` is forbidden in a normal AUZiX root;
- `/System/Libraries/Runtime/glibc` is the only valid glibc/loader provider;
- `/System/Compatibility` may alias or expose the active core, but must not
  become a second libc provider;
- a package closure that needs newer substrate becomes a candidate runtime-layer
  rebuild, not an invisible desktop repair.

`auzix-pkg plan` should classify this case before extraction:

```text
leaf install within current substrate      -> allowed
leaf install needs missing leaf dep         -> allowed, install dep
leaf install wants newer substrate package  -> hold/backtrack or fail with runtime-rebuild-required
runtime rebuild transaction                 -> allowed only in explicit runtime mode
```

## Inputs

Lifecycle declarations are derived from Debian evidence:

```text
Debian source recipe
Debian binary maintainer scripts
triggers/conffiles
DBus/Polkit/systemd/XDG/schema/icon/MIME surfaces
AUZiX package receipt
```

The main translation is path-oriented:

```text
Debian package expectation
  -> AUZiX canonical path
  -> compatibility/export path when required
```

Examples:

```text
/etc       -> /System/Settings
/var/lib   -> /System/State
/var/cache -> /System/Cache
/var/log   -> /System/Logs
/usr/bin   -> /Programs/<Package>/current/Commands
/usr/lib   -> /Programs/<Package>/current/Libraries
/usr/share -> /Programs/<Package>/current/Shared
```

When compatibility aliases are needed, they must be explicit package/runtime
contracts, not accidental fallbacks.

The farming pipeline emits fragments:

```text
out/package-slices/<slice>/auzix-fragments/<binary>.auzix-fragment.json
```

Those fragments should be normalized into package lifecycle metadata, either
inside the package receipt or beside it:

```text
/Programs/<Pkg>/<Version>/Package/lifecycle.json
/System/PackageDB/<Pkg>-<Version>.auzix.json
```

## Owned payloads vs generated install state

Do not confuse package-owned files with paths populated by installation scripts
or triggers.

Debian answers payload ownership with `dpkg-query -S /path`. If the path is
owned, AUZiX should map that package file into a receipt/export. If the path is
unowned but present on the reference host, treat it as generated install state
and trace the maintainer script or trigger that creates it.

Examples from the vmid132/Trixie desktop guidebook:

```text
/usr/share/xsessions/enlightenment.desktop      owned by enlightenment-data
/etc/X11/Xsession                               owned by x11-common
/etc/X11/Xsession.d/20dbus_xdg-runtime          owned by dbus-user-session
/etc/X11/Xsession.d/75dbus_dbus-launch          owned by dbus-x11
/usr/bin/update-desktop-database                owned by desktop-file-utils
/usr/bin/update-mime-database                   owned by shared-mime-info
/usr/bin/glib-compile-schemas                   owned by libglib2.0-bin
/usr/bin/gtk-update-icon-cache                  owned by gtk-update-icon-cache
/usr/bin/efreetd                                owned by libefreet-bin

/usr/share/applications/mimeinfo.cache          generated by desktop database refresh
/usr/share/mime/mime.cache                      generated by MIME database refresh
/usr/share/glib-2.0/schemas/gschemas.compiled   generated by schema compile
/usr/share/icons/hicolor/icon-theme.cache       generated by icon cache refresh
```

AUZiX receipts therefore need two different declarations:

```json
{
  "exports": [
    {
      "source": "RootFS/usr/share/xsessions/enlightenment.desktop",
      "target": "/System/Compatibility/usr/share/xsessions/enlightenment.desktop",
      "owner_source": "dpkg-query -S"
    }
  ],
  "generated_state": [
    {
      "path": "/System/Compatibility/usr/share/applications/mimeinfo.cache",
      "surface": "desktop_database",
      "producer_hook": "xdg.refresh-desktop-database",
      "source_semantics": "generated by package trigger, not payload-owned"
    }
  ]
}
```

Validation should fail differently for these cases:

- owned export missing: package extraction/export bug;
- generated state missing: lifecycle trigger/setup bug;
- generated state stale: transaction ordering or trigger coalescing bug.

## Lifecycle declaration shape

```json
{
  "format": "auzix-package-lifecycle-v1",
  "package": "Flatpak",
  "version": "1.16.6",
  "mode_support": ["setup", "fix", "status"],
  "depends": {
    "runtime": ["Libflatpak0", "Bubblewrap", "XdgDbusProxy"],
    "lifecycle": ["DBus", "Polkit", "XdgPortals"]
  },
  "path_map": {
    "/etc": "/System/Settings",
    "/var/lib": "/System/State",
    "/var/cache": "/System/Cache",
    "/var/log": "/System/Logs",
    "/usr/bin": "/Programs/<Package>/current/Commands",
    "/usr/share": "/Programs/<Package>/current/Shared"
  },
  "hooks": [
    {
      "id": "dbus.install-service",
      "surface": "dbus",
      "source": "RootFS/usr/share/dbus-1",
      "target": "/System/Settings/dbus-1",
      "mode": "copy-or-export",
      "idempotent": true
    },
    {
      "id": "desktop.refresh-menu",
      "surface": "desktop_database",
      "mode": "refresh",
      "idempotent": true
    }
  ],
  "validation": [
    {
      "id": "front-door-version",
      "command": "/Programs/Flatpak/current/Commands/flatpak --version",
      "timeout_seconds": 10
    }
  ]
}
```

## Hook vocabulary

Initial generic hooks:

- `path.export`
- `command.wrapper`
- `runtime-ladder.register`
- `dbus.install-service`
- `dbus.ensure-system-bus`
- `dbus.ensure-session-bus`
- `polkit.install-policy`
- `polkit.ensure-daemon`
- `service.translate-systemd`
- `service.enable`
- `service.start`
- `user.ensure`
- `group.ensure`
- `group.membership`
- `mode.ensure`
- `capability.ensure`
- `xdg.install-desktop-entry`
- `xdg.refresh-desktop-database`
- `xdg.refresh-mime-database`
- `xdg.refresh-icon-cache`
- `gsettings.compile-schemas`
- `efreet.refresh-cache`
- `flatpak.ensure-remote`
- `state.ensure-dir`
- `log.ensure-dir`
- `compat.alias`
- `validation.probe`

Hooks must be idempotent and receipt-backed. A hook that cannot be made safe
must report `requires-operator` instead of guessing.

## First install mode

`auzix-pkg setup <package>` should:

1. load package receipt and lifecycle declaration;
2. resolve runtime dependencies;
3. resolve lifecycle dependencies;
4. apply hooks in dependency order;
5. refresh caches/triggers after all packages in the transaction are staged;
6. run package validation probes;
7. write setup receipt.

First install can create missing users/groups, state dirs, runtime dirs, service
definitions, DBus policies, Polkit policies, wrappers, menu entries, and cache
indexes when declared by package lifecycle metadata.

The install operation is an expansion:

1. extract payload;
2. expose commands/libraries/shared data through the AUZiX path matrix;
3. apply lifecycle hooks;
4. refresh stack-level caches/triggers;
5. prove front doors and services with probes;
6. write receipts.

## Fix/reconcile mode

`auzix-pkg fix <package|stack>` should:

1. collect current host state;
2. compare it against lifecycle declarations;
3. classify drift;
4. apply only safe idempotent hooks;
5. refuse broad/destructive changes unless a policy flag allows them;
6. run validation probes;
7. write reconcile receipt.

Examples:

```bash
auzix-pkg status --stack desktop-session
auzix-pkg triage --stack desktop-session
auzix-pkg fix --stack desktop-session
auzix-pkg setup Flatpak
```

Fix mode is what vmid135 needs. It should not be hand-authored around today's
Efreet/Pulse/LightDM symptom. It should consume the same lifecycle metadata that
first install will use in the next ISO.

Fix mode should prefer repackaged metadata and fragment-driven reconcile before
any rebuild. Rebuild is reserved for payload defects such as hardwired paths or
linkage that cannot be corrected by wrappers, exports, or explicit compatibility
contracts.

## Lua engine role

Lua is a good fit for the lifecycle engine because it can be small, embedded,
and policy-driven.

Suggested split:

```text
auzix-pkg
  transaction planner, package metadata, download/install, receipt storage

lua lifecycle engine
  path mapping, hook execution, idempotent reconcile, status classification

shell helpers
  narrow host operations that Lua invokes through controlled wrappers
```

Lua should not encode app-specific hacks. It should encode AUZiX policies:

- how Debian lifecycle semantics map into AUZiX paths;
- which hooks are safe in `setup` and `fix`;
- how to record drift;
- how to build environment/runtime ladders;
- when to require operator approval.

## Dependency chain model

Lifecycle dependencies are separate from library dependencies.

Example desktop chain:

```text
DBus
  -> Polkit
  -> LightDM
  -> EFL / Efreet
  -> Enlightenment
  -> PulseAudio
  -> XDG Portals
  -> Flatpak
  -> desktop apps
```

If `Flatpak` is installed but `DBus` or `Polkit` lifecycle state is not
reconciled, `Flatpak` is not `desktop-ready` even when the binary runs.

## Receipt states

Packages should expose at least:

- `downloaded`
- `extracted`
- `setup-pending`
- `setup-complete`
- `fix-needed`
- `fix-complete`
- `validation-failed`
- `desktop-ready`
- `service-ready`

`auzix-pkg status` must be able to explain why a package is not ready.
