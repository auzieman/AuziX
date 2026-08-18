# AUZiX native rebase discovery counts — 2026-08-18

Discovery was run on the R730/lab-build Docker context in a disposable
`auzix/trixie-builder:lab` container. This was metadata/dry-run only; no target
packages were compiled.

## Rule confirmed

This is a Slackware/Debian-style current-head build resolution pass:

1. pick the Trixie/current-head lane;
2. resolve package/dependency candidates;
3. dedupe/consolidate substrate providers;
4. emit a build lock;
5. commit and tag that lock;
6. build from the tag with zero drift.

AUZiX changes paths, package metadata, and runtime policy. It does not let leaf
apps build private alternate OS substrates.

## Discovery output

Ignored runtime artifact:

```text
out/rebase/lab-discovery-20260818/
```

Suggested git tag from the planner:

```text
auzix-alpha-base-lab-discovery-20260818
```

## Counts

```text
requested roots:                         344
base targets:                             31
extended targets:                         28
planned roots before dependency expand:  403
direct dependency edges:                2441
unique direct dependency names:          899
selected simulated closure:             1386
substrate provider slots:                 47
substrate provider slots resolved:        45
apt simulation status:                    ok
```

Important: dependency edges are not build counts. Repeated requests for `libc6`,
`libgtk`, `libeina`, `libssl`, etc. collapse into one selected provider for the
base/substrate lane. If a second provider candidate appears, it is a conflict
to resolve before build, not another copy to build.

The two unresolved substrate slots are intentional review items rather than
random missing packages:

- `AuzixServiceRuntime` is AUZiX-owned.
- `EFL` is an aggregate/source-family marker; the concrete runtime providers
  resolve through packages such as `libeina1t64`, `libevas1`, `libedje1`,
  `libefreet1a`, and `libelementary1`.

## Heavy root dry-run counts

```text
gnome-control-center    232
calligra                329
gimp                    113
libreoffice             110
libreoffice-writer       75
libreoffice-calc         84
libreoffice-impress      80
libreoffice-draw         77
ephoto                   81
cups                     47
cargo                    38
build-essential          32
flatpak                  28
clang                    27
pluma                    26
firefox-esr               6
geany                     2
htop                      1
```

This confirms that the intuitive “hard hitters” are stack representatives:
GNOME Control Center, LibreOffice, Calligra, GIMP, CUPS, Flatpak, Cargo/Clang,
and EFL apps cover most of the workstation plumbing.

## Desktop-entry homework

`scripts/extract-debian-desktop-guidebook.sh` was added so AUZiX can read
Debian `.desktop` metadata instead of inventing launchers.

Smoke extraction on lab-build showed:

```text
LibreOffice Writer -> Exec=libreoffice --writer %U, Categories=Office;WordProcessor;
LibreOffice Calc   -> Exec=libreoffice --calc %U, Categories=Office;Spreadsheet;
Geany              -> Exec=geany %F, Categories=GTK;Development;IDE;TextEditor;
Pluma              -> Exec=pluma %U, Categories=GTK;Utility;TextEditor;
GIMP               -> Exec=gimp-3.0 %U, Categories=Graphics;2DGraphics;RasterGraphics;GTK;
Firefox ESR        -> Exec=/usr/lib/firefox-esr/firefox-esr %u, Categories=Network;WebBrowser;
Htop               -> Exec=htop, Terminal=true, Categories=System;Monitor;ConsoleOnly;
```

AUZiX launcher rule:

```text
read donor .desktop -> preserve labels/categories/MIME/icons
-> rewrite Exec/TryExec to AUZiX wrapper
-> hide donor entry until front-door validates
-> refresh efreet/menu caches
-> promote only after launch-clean/menu-clean
```

## Next gate

Before compiling:

1. commit this substrate rebase/discovery boundary;
2. tag the commit;
3. run discovery/build from that tag on lab-build;
4. build only BusyBox/base/toolchain first;
5. create acid/base AUZiX native container;
6. build apps inside AUZiX native container.
