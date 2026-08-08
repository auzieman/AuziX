# AUZiX package validation contract

An AUZiX package is not considered workstation-ready merely because it built,
unpacked, or emitted a receipt. A package graduates only after it passes a
container-installed "real duck" validation.

## Validation environment

Use an AUZiX validation root/container, not the Debian builder host, for the
final package check. The validator should install the package through
`auzix-pkg` or the same archive extraction/finalization path used on vmid135.

The validator records:

- package name, version, archive, sha256, receipt path;
- installed paths from the receipt;
- command wrappers and resolved target ELF payloads;
- desktop entries and menu `Exec=` targets;
- dependency, ABI, and hardwired-path evidence.

## Package query parity

AUZiX packages should be observable with the same kinds of questions Debian
answers through `dpkg`, `apt`, and package metadata. AUZiX may use different
path values, mount layouts, wrappers, or future bind/mount patterns, but the
rules are the same: every built or installed package must expose enough state
to explain how it should run.

At minimum, a package receipt/index entry must allow tools to query:

- installed state and version;
- source/origin package, suite, architecture, and upstream version when known;
- installed files and promoted/exported paths;
- command entry points and their wrapper/runtime target;
- dependency and recommendation surfaces;
- service, desktop, Polkit, group, and permission expectations;
- runtime environment values such as `PATH`, `LD_LIBRARY_PATH`,
  `XDG_DATA_DIRS`, `GSETTINGS_SCHEMA_DIR`, `GI_TYPELIB_PATH`, and package
  stack names;
- validation state such as `installable`, `link-clean`, `front-door-clean`,
  `menu-clean`, and `desktop-ready`.

The AUZiX equivalent of Debian package inspection should be able to answer:

- "What package owns this command or file?"
- "What source package did this come from?"
- "What files did this install?"
- "What runtime paths does this wrapper add?"
- "What groups, services, or Polkit actions does this app expect?"
- "Why is this package not desktop-ready?"

Different values are expected; missing answers are package-contract bugs.

## Required checks

## Runtime stack ladder

Packages should not rely on each individual app wrapper to manually rediscover
every dependency package. AUZiX needs a runtime stack ladder: each package can
declare the package layers it expects, and the generated launcher falls through
those layers in order when building `PATH`, `LD_LIBRARY_PATH`,
`XDG_DATA_DIRS`, schema paths, plugin paths, and other runtime search paths.

Initial ladder:

1. package-local `RootFS`;
2. declared dependency package `RootFS`/`Libraries`, in dependency order;
3. named shared stacks such as `gtk3`, `gtk4`, `gnome-runtime`, `qt6`,
   `kde-frameworks`, `libreoffice-runtime`, `office-filters`,
   `graphics-runtime`, `network-runtime`, and `debug-runtime`;
4. AUZiX system surfaces: `/System/Libraries`, `/System/Compatibility`, and
   `/System/Settings`.

The ladder must be visible in receipts so validation can answer: "this package
failed because its dependency is missing" versus "the dependency is installed
but not on the runtime path."

Examples from vmid135:

- `Galculator` installed after `Libquadmath0`, but still could not see
  `libquadmath.so.0`; that is a runtime ladder failure.
- `Baobab` needs the GTK4/GNOME runtime stack.
- `GnomeDiskUtility` needs storage/media libraries such as `libdvdread`.
- `LibreOffice` wants a LibreOffice runtime stack rather than per-command
  bespoke path hacks.

For each declared command:

1. `stat` the wrapper and resolved executable target.
2. `file` the wrapper and resolved executable target.
3. `readelf -l` and `readelf -d` each ELF target.
4. `ldd` each ELF target with the package wrapper/library environment.
5. Fail on:
   - `not found`;
   - required symbol/version errors such as `GLIBC_2.xx not found`;
   - legacy interpreter/RPATH/RUNPATH that is not explicitly accepted;
   - unresolved app-specific shared objects.
6. `strings` each wrapper/ELF/config payload for hardwired donor paths.
7. Run a bounded command smoke through the AUZiX front-door wrapper itself,
   such as `/Programs/App/current/Commands/app --version`, `--help`, or a
   package-declared smoke command. Do not accept a package as launch-clean when
   only the donor payload path works.

For each desktop package:

1. Require at least one `.desktop` entry unless the package is explicitly
   marked `terminal-only`, `service`, `library`, or `staging`.
2. Ensure `Name`, `Comment` or description, `Categories`, and `Exec` are
   sensible for Enlightenment menus.
3. Ensure `Exec` points to the owning AUZiX front-door command wrapper,
   normally `/Programs/App/current/Commands/app`, not a donor `/usr/bin` path
   and not only a compatibility alias.
4. Manually test at least one menu/front-door launch for promoted desktop
   applications. The proof command must exercise the wrapper-generated runtime
   ladder, not just `ldd` a discovered ELF.
5. Run a bounded GUI launch smoke under the active X/DBus environment when
   available. A package can be `installable` without this, but not
   `desktop-ready`.

## Reference desktop guidebook

Use `vmid132` (`trixie-smoke-132`, observed at `10.20.0.117`) as the
reference workstation when AUZiX desktop behavior is ambiguous. It is a
Debian/Trixie LightDM workstation with a working `auzieman` graphical login,
reasonable Enlightenment/MATE menus, and representative GUI applications such
as GIMP launching from the menu.

The desktop proof loop is:

1. Log in through LightDM.
2. Confirm the menu tree and app list are sensible.
3. Launch representative apps from the menu and from their command entry
   points.
4. Log out to the display manager.
5. Log back in and confirm the menu/app surface is equivalent.

AUZiX does not copy Debian paths blindly, but failures should be compared
against vmid132 for package ownership, dependencies, `.desktop` entries,
LightDM/session wiring, Polkit permissions, and user groups before inventing a
one-off AUZiX fix.

## Graduation states

- `built`: archive and receipt exist.
- `installable`: package installs through `auzix-pkg` with complete dependency
  closure.
- `link-clean`: command ELF targets pass `ldd`/`readelf` validation.
- `launch-clean`: bounded command smoke passes in an AUZiX root/container.
- `front-door-clean`: the exact user/menu-facing wrapper launches with the
  generated runtime ladder.
- `menu-clean`: desktop entry exists, points to the owning AUZiX wrapper, and
  remains visible after a LightDM logout/login cycle.
- `desktop-ready`: installable, link-clean, launch-clean, front-door-clean,
  and menu-clean.

Only `desktop-ready` packages should be included in default workstation or
desktop-proof package groups. Packages that are merely `built` or `installable`
may remain in the repo as experimental/staging, but the UI must label them as
such.

## Lessons from vmid135

The following failures must be caught before publication or before promotion to
desktop-ready:

- a profile names a Debian package with no candidate in the selected suite
  (for example, Trixie removed `policykit-1`; use the split `pkexec`,
  `polkitd`, and `libpolkit-*` packages instead);
- a package installs but `ldd` reports a missing library;
- a package installs but needs a newer GLIBC/GLib symbol than AUZiX provides;
- a wrapper calls a path that the base package does not actually ship;
- a `.desktop` file exists but launches a donor path;
- the package manager GUI can select a package but lacks privilege or dependency
  closure to install it.
