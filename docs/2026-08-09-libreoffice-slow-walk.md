# 2026-08-09 LibreOffice slow walk

Goal: carry one problematic application, LibreOffice, all the way from a known
good Debian/Trixie desktop on vmid132 through AUZiX package generation,
repository publication, and vmid135 install/run proof.

Scope:

- Treat vmid132 (`trixie-smoke-132`) as the guidebook for installed package
  layout, launcher behavior, dependency closure, and runtime files.
- Treat vmid135 (`auzix-live`) as the proving ground.
- Use the AUZiX build container and published package repository rather than
  hand-editing vmid135, except for read-only inspection.
- Capture each failure as: Debian fact, AUZiX fact, hypothesis, change, and
  vmid135 proof.

## Baseline facts

- vmid132 has LibreOffice 25.2.3 installed and launches the desktop suite from
  Debian's normal `/usr/bin/*` wrappers into `/usr/lib/libreoffice/program`.
- Debian's visible launcher spine is:
  - `/usr/bin/libreoffice` and `/usr/bin/soffice` symlink to
    `/usr/lib/libreoffice/program/soffice`;
  - `/usr/bin/lowriter`, `/usr/bin/localc`, and peers are shell wrappers;
  - `/usr/lib/libreoffice/program/soffice` is a shell wrapper;
  - `/usr/lib/libreoffice/program/oosplash` and `soffice.bin` are ELF files
    from `libreoffice-core`.
- vmid135 currently has AUZiX LibreOffice package receipts for Writer, Calc,
  Impress, Math, Common, StyleColibre, URE, and UNO libs. `LibreOfficeCore`
  is visible in the repository but was not installed at baseline.

## Failure 1: generated LibreOffice wrappers quote BusyBox incorrectly

Debian fact:

- Debian wrapper scripts use ordinary shell command substitution and do not
  quote the executable name itself.

AUZiX fact:

- The generated AUZiX LibreOffice wrappers contained:
  `$(" ${BB}" basename "${item}")` logically, rendered as
  `$("...busybox" basename "...")` in the installed shell script.
- On vmid135, `BusyBox` itself exists and runs:
  `/Programs/BusyBox/current/Commands/busybox echo ok`.
- Running `loffice`, `lowriter`, or `localc` failed repeatedly with:
  `line 26: "/Programs/BusyBox/current/Commands/busybox": not found`.

Hypothesis:

- The wrapper is asking the shell to execute a command name containing literal
  quote characters. This prevents state assembly before LibreOffice even
  reaches `soffice`.

Change:

- Fix the Debian intake generator so LibreOffice wrappers emit
  `$("${BB}" basename "${item}")`, not `$(" ${BB}" ... )`.

Proof status:

- Rebuilt `libreoffice-common`, `libreoffice-core`, `libreoffice-writer`,
  and `libreoffice-calc` in the R730 build container.
- Published the rebuilt repository to ns1.
- Added `scripts/validate-auzix-libreoffice-spine.sh` and ran it in the
  `auzix-lo-validation` container.
- The rebuilt wrappers now pass the wrapper pattern check:
  `busybox-basename-ok`.

## Failure 2: LibreOffice dependency closure is now honest but incomplete

Debian fact:

- `libreoffice-core` is the arch-dependent engine package. It provides the
  real `oosplash` and `soffice.bin` ELF files and declares a large dependency
  closure.
- Writer and Calc are not self-contained applications; they sit on top of
  Common, Core, URE, UNO private libs, uiconfig packages, import/export filter
  libs, graphics/font/XML stacks, and desktop/X libraries.

AUZiX fact:

- After the dependency parser fix, rebuilt AUZiX receipts now expose the large
  LibreOffice closure instead of the previous sparse dependency list.
- `LibreOfficeWriter` now depends on `LibreOfficeCore`,
  `LibreOfficeUiconfigWriter`, UNO libs, ICU/XML/stdcpp/libc, and filter libs.
- `LibreOfficeCalc` now depends on `LibreOfficeCore`,
  `LibreOfficeUiconfigCalc`, `LibreOfficeBaseCore`, UNO libs, ICU/XML/stdcpp,
  Orcus, CoinMP, and other Calc/filter libs.
- `LibreOfficeCore` closure validation currently reports 49 missing native
  packages in the repository.

Validation evidence:

```text
root                 closure_count  missing_count
LibreOfficeCommon    5              1
LibreOfficeCore      99             49
LibreOfficeWriter    112            51
LibreOfficeCalc      110            53
```

Key missing packages include uiconfig/base-core packages and the runtime spine:
`LibreOfficeUiconfigCommon`, `LibreOfficeUiconfigWriter`,
`LibreOfficeUiconfigCalc`, `LibreOfficeBaseCore`, `Libicu76`, `Libxdmcp6`,
`Libjpeg62Turbo`, `Libtiff6`, `Libnss3`, `Libnspr4`, `Libhunspell170`,
`Libhyphen0`, `Libgstreamer100`, `LibgstreamerPluginsBase100`, `Libdbus13`,
`Libdconf1`, `Libcurl4t64`, `Libcmis066t64`, `LibcluceneCore1t64`,
`LibcluceneContribs1t64`, `LibboostLocale1830`, and `Libabsl20240722`.

Hypothesis:

- LibreOffice was close because the payload packages existed, but it was not
  actually installable/runnable because AUZiX did not yet build the full
  Debian-declared closure.
- vmid135 should not be used as the first full LibreOffice install target until
  the repository closure check is green for at least Common + Core + Writer or
  Common + Core + Calc.

ai_worker result:

- `auzix-lo-ai-worker` ran the existing AUZiX receipt review and produced
  `out/libreoffice-slow-walk/ai-worker/r730-trixie-20260808T163223Z.receipt-review.md`.
- The current general ai_worker gate reported `pass`, but it only reviewed the
  package-bot summary and did not consume the LibreOffice-specific closure
  validation. This is now a gap: ai_worker must ingest package-specific
  validation artifacts before it can call complex packages ready.

Next build slice:

- Build the first LibreOffice spine dependencies rather than blasting every
  missing leaf: uiconfig/common/writer/calc, base-core, ICU, XDMCP, JPEG/TIFF,
  and the most obvious Core runtime packages.

## Guidebook proof: vmid132 Calc CLI conversion

On vmid132 (`trixie-smoke-132`), the literal Calc validation test passes:

```text
localc --headless --convert-to csv --outdir /tmp/auzix-lo-proof /tmp/auzix-libreoffice-calc-proof.ods
```

Debian converted the sample spreadsheet and produced:

```text
AUZiX,LibreOffice Calc proof
Package rail,Kanboard + bkc-channel + ai_worker
```

AUZiX is not ready for a vmid135 hand-run until the validation root can perform
the same ODS-to-CSV conversion through the AUZiX LibreOffice wrapper/runtime
stack.

## Source guidebook gate

The AUZiX pipeline now treats Debian source as the recipe guidebook before a
port can graduate. LibreOffice source was fetched in the R730 builder and
inspected with:

```sh
scripts/inspect-debian-source-contract.sh libreoffice \
  /workspace/out/debian-source-study/libreoffice-guidebook
```

The guidebook report captured the important Debian packaging semantics:

- `debian/control` declares the native build dependency surface, including
  X11, GTK, GStreamer, Java/Python, import filters, font, XML, crypto, and
  office-suite libraries;
- `debian/rules` carries the configure feature matrix, including
  `--with-system-*`, GUI/no-GUI, Java/Python, CUPS, LDAP, NSS, database, test,
  and debug/release switches;
- `debian/tests/control` shows the real test ladder: bridge tests, UNO/PyUNO
  imports, uichecks, SDK examples, AppArmor syntax, and subsequent checks;
- `debian/scripts/gid2pkgdirs.sh` is the package-split truth for the current
  AUZiX wrapper bug.

The key split rule is explicit: Debian moves wrappers such as `localc`,
`lowriter`, `loimpress`, and `loffice` into the application/common packages,
then moves runtime program payloads from common into `libreoffice-core`:
shared libraries, `.bin` helpers, `*.rdb`, `javaldx`, `oosplash`,
`uri-encode`, `xpdfimport`, and related program assets.

AUZiX must model that semantic split. Calc/Writer wrappers cannot depend only
on their thin wrapper package; they must inherit the LibreOffice Core runtime
closure before `ldd` or headless conversion is considered meaningful. The
builder bug found here was a shallow `LibreOfficeCore` control-file lookup plus
single-line `Depends:` parsing, which meant Core's dependency ladder could be
silently omitted.

This is now written into the package validation contract as the "native source
guidebook gate": if the native Debian recipe cannot be fetched, configured,
built, or tested/cached in the builder, the AUZiX port cannot honestly graduate
beyond planning/source-failed.

## Runtime mount package gate

The `/proc` failure was not a LibreOffice packaging bug by itself. It was the
same runtime substrate issue already found during the vmid135 Podman work:
services and complex applications need proc, sysfs, devtmpfs/devpts, tmpfs
`/run` and `/dev/shm`, and cgroup2.

The existing `AuzixServiceRuntime` queue item was promoted from pseudo-package
to a real package. It now stages:

- `/Programs/AuzixServiceRuntime/current/Commands/ensure-runtime-mounts`
- `/Services/runtime-mounts/run`
- a package receipt describing the runtime mount contract

The LibreOffice validator now calls that package command inside the AUZiX root
when present. In an unprivileged Docker validation container, the result remains
`runtime-mounts-incomplete`; in a privileged validation container, the package
reports:

```text
AuzixServiceRuntime: runtime mounts ready at /
CHECK	runtime-mounts-ready
```

With runtime mounts available, Calc advances to the next true package closure
failure:

```text
/System/State/libreoffice/program/soffice.bin: error while loading shared libraries: libgpgmepp.so.6: cannot open shared object file: No such file or directory
```

That means the cgroup/proc/sys/dev/run class is now handled by a package and
container launch contract. The next LibreOffice work is the dependency ladder,
starting with packages already named in the closure report such as
`Libgpgmepp6t64`.
