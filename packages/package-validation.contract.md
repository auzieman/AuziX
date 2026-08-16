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

## Native source guidebook gate

Binary intake is not the first truth for a port. Before a package can graduate
past experimental/staging, the builder must prove the native Debian source
recipe is understood well enough to explain the AUZiX port.

For promoted packages, the source build/install contract is the package. A
package is not considered correctly built merely because a donor payload was
repacked. The normal path is:

```text
fetch source
inspect Debian source recipe
install/build dependency closure
configure with AUZiX path values
make/ninja/cmake/meson build
make install DESTDIR=<stage> or equivalent
capture staged manifest and checksums
wrap/export only what the staged install produced
run lifecycle hooks and validation probes
```

The builder must record the exact configure/build/install commands,
environment, build system, source revision, dependency closure, staged install
root, installed file manifest, checksums, and logs. If a package uses Autotools,
CMake, Meson, Cargo, Go, or a custom system, the receipt must name the command
equivalent of `configure`, `build`, and `install`.

Binary repack output is allowed only as a bridge artifact unless it references a
matching source-build receipt proving that the payload and lifecycle semantics
were already produced by the correct build/install contract. Bridge artifacts
must not replace source-built packages in workstation profiles by name.

For each Debian-sourced package, the build worker records a guidebook report
from the source package:

- `debian/control` build dependencies, binary package split, dependencies, and
  recommendations;
- `debian/rules`, `debian/*.mk`, and helper scripts for configure, make,
  install, package split, wrapper movement, and path decisions;
- `debian/*.install`, `*.links`, `*.dirs`, maintainer scripts, triggers,
  alternatives, AppArmor, Polkit, DBus, systemd, schemas, icons, MIME, desktop
  entries, and user/group expectations;
- `debian/tests/control` and related tests for literal probes we can mirror;
- upstream configure flags, feature toggles, and any hardwired donor paths that
  must be replaced by AUZiX paths or explicit compatibility contracts.

If the native source package cannot be fetched, configured, built, or tested in
the Debian/Trixie builder, the AUZiX package is not allowed to claim more than
`source-failed` or `planning`. A cached known-good native build/recipe report
may satisfy this gate for very large packages, but the report must name the
source revision, builder image, command, result, and reason any full rebuild was
skipped.

AUZiX does not copy Debian paths blindly. It does copy Debian's semantics:
package ownership, dependency closure, wrappers, state creation, service hooks,
desktop/menu behavior, and tests. When AUZiX intentionally changes a path, the
guidebook report must explain the matching AUZiX path and validation probe.

LibreOffice is the current reference failure. Debian's
`debian/scripts/gid2pkgdirs.sh` explicitly moves wrappers such as `localc` into
application packages while moving `.so`, `.bin`, `*.rdb`, `oosplash`, and other
runtime program payloads into `libreoffice-core`. AUZiX LibreOffice wrappers
must model that split before `ldd`/launch probes run; rediscovering
`libXinerama.so.1` and friends one failure at a time is a pipeline bug.

LibreOffice launcher acceptance is stricter than "a process stayed alive":

- launcher-created state belongs under user-owned XDG paths, not root-owned
  `/System/State` or `/System/Settings`;
- wrapper-generated `fundamentalrc` must use a relative
  `BRAND_BASE_DIR=${ORIGIN}/..` so the assembled AUZiX runtime cache is the
  bootstrap root;
- launchers should enter LibreOffice through its own `soffice`/module scripts
  rather than bypassing them with a direct `soffice.bin` loader exec;
- Impress and Draw use isolated `UserInstallation` profiles until the shared
  LibreOffice broker/profile routing is proven not to reopen the previous
  module;
- GUI proof requires visible module behavior or exact E/X logs, not merely
  `oosplash`/`soffice.bin` surviving.

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

## Literal application probes

Complex applications must declare at least one literal probe that exercises the
same code path a user cares about, not merely `--version`.

The probe should use the application's own non-interactive tools when they
exist. Examples:

- spreadsheet/editor suites: open a fixture document and convert/export it
  (`localc --headless --convert-to csv sample.ods`);
- word processors: open a fixture document and export text/PDF;
- image tools: open a fixture image and convert/export metadata or a thumbnail;
- media tools: inspect or transcode a tiny fixture;
- archive tools: create and extract a small archive;
- network/services: serve a local fixture and fetch it through the front door.

For command-line-first packages, the CLI probe is not optional. If the AUZiX
validation container/root cannot use the command for its normal purpose, the
package is not built in any useful sense. A package can have an archive and a
receipt while still being contract-failed.

Examples:

- GStreamer: inspect plugins and run a tiny `gst-launch` pipeline against a
  generated or fixture media stream;
- FFmpeg: inspect codecs/formats and transcode or probe a tiny media fixture;
- ImageMagick/graphics tools: identify and convert a tiny image fixture;
- compilers/interpreters: compile/run or interpret a tiny source fixture;
- archive/compression tools: create, list, and extract an archive fixture;
- database/kv tools: start or query a minimal local fixture when safe;
- service packages: start the service in a bounded container namespace and
  fetch/query the exposed local endpoint.

If the tool cannot run in the validation container because of missing devices,
kernel features, permissions, DBus, X11, audio, GPU, or network namespace
requirements, the package must record that as an explicit environment contract
and remain below `desktop-ready`/`service-ready` until the required host
capability is supplied and tested.

Each probe must record:

- the Debian/vmid132 guidebook command and output when available;
- the AUZiX front-door command and output;
- fixture paths and checksums;
- exported artifacts and content checks;
- whether failure is a missing package, missing runtime path, wrapper/state
  assembly bug, permission/group/polkit issue, DBus/X/session issue, or
  application-specific configuration issue.

LibreOffice taught the rule: `localc` was not considered launch-clean until it
could attempt the same headless ODS-to-CSV conversion that works on vmid132.
The first useful AUZiX failure was not "LibreOffice broken"; it was a precise
runtime-path failure after the wrapper reached `oosplash`.

Probe results must fold back into package receipts and the package repository
index so `auzix-pkg status`, BKC, ai_worker, and Kanboard can explain whether a
package is merely built, installable, launch-clean, or desktop-ready.

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

## Installer and package-manager frontend gate

The installer and package manager must always keep a boring, scriptable path.
The netboot/unattended profile defaults to SSH/TUI and must not require EFL,
GTK, LightDM, or a running user desktop session.

Graphical frontends such as `AuzixInstallerEfl` and
`AuzixPackageManagerEfl` are promoted only after a fresh installed AUZiX user
session proves:

- CLI installer/package-manager commands work first;
- the EFL frontend wrapper sets the required AUZiX runtime stack explicitly,
  including library, data, icon/theme, and XDG paths;
- the frontend writes cache/config/state only to user-owned or package-declared
  state directories;
- DBus/session/efreet failures are absent or cataloged as blocker evidence;
- the frontend opens visibly from a direct command and from the E menu;
- a failed GUI launch falls back to TUI or reports a precise failure without
  hanging the installer or desktop session.

Until those checks pass, EFL frontends remain post-install package-group work,
not tiny-netinstall acceptance criteria.

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
