# Source Workbench

The source workbench combines the useful parts of `Auzix.rethink` with the
current AuZiX package/receipt model.

The goal is to stop rebuilding working behavior in broad shell scripts. Build
from source normally, override paths deliberately, stage the result, validate
the result, then package it.

## Files

```text
packages/source-workbench.schema.json  manifest schema
packages/source-workbench.seed.json    first EFL/E/Terminology/NetSurf seed
packages/source-build.sources.json     earlier NetSurf-focused source catalog
docker/source-workbench/Dockerfile     minimal bootable workbench container
scripts/source-workbench-boot.sh       manifest boot/plan entry point
```

Generated paths should follow this shape:

```text
sources/workbench/<component>/          checked-in patches or local source notes
out/build/source-workbench/<component>/ unpacked upstream source and build tree
out/stage/source-workbench/<component>/ DESTDIR-style install root
out/packages/source-workbench/          package archives, receipts, ldd evidence
```

## Build Rules

Use the package's own build system first:

- `make`
- `meson` and `ninja`
- `cmake`
- `autotools`

Prefer build/install flags before source patches:

```text
PREFIX
DESTDIR
LIBDIR
SYSCONFDIR
LOCALSTATEDIR
PKG_CONFIG_PATH
LD_LIBRARY_PATH
```

Debian source metadata is useful for locating source packages, dependencies,
versions, and patches. Debian `debian/rules` is reference material unless a
component genuinely needs it.

## Validation

Every component should produce evidence before it is allowed into the ISO:

```text
build log
install manifest
receipt JSON
readelf/ldd output
declared compatibility exports
small CLI smoke check
```

For graphical packages, validate command presence and library closure before
trying a full desktop boot. Enlightenment's first-run, network-manager,
Bluetooth, PackageKit, and Wayland modules should stay disabled until their
backing services are package-owned.

## Ollama Worker

Ollama should receive only bounded failure packets:

```text
component manifest
build command
tail of build log
ldd/readelf failure evidence
current receipt, if any
```

The requested answer should be limited to:

```text
finding:
smallest build argument or patch:
validation command:
```

Do not ask the worker to redesign the distribution or rewrite the boot process.

## First Lane

The first practical lane should prove this order:

```text
EFL -> Enlightenment -> Terminology -> NetSurf
```

NetSurf is marked `ready` in the seed manifest because the manual proof already
showed that source-tree build plus `LD_LIBRARY_PATH`/prefix handling works. The
others remain `seed` until their source build contracts are proven.

## Bootable Workbench

The first runnable form is intentionally small. It does not compile the desktop
stack yet. It boots the workbench control plane, validates the manifest format,
creates the expected generated roots, emits a build plan, and stages the first
config-driven target root.

```sh
make auzix-source-workbench
```

Generated outputs:

```text
out/source-workbench/boot-summary.json
out/source-workbench/build-plan.txt
out/source-workbench/target-layout.txt
out/source-workbench/validation-report.json
out/source-workbench/AuZiXTarget/System/S/system-startup.json
out/source-workbench/AuZiXTarget/System/S/package-startup.json
out/source-workbench/AuZiXTarget/System/S/system-startup.lua
out/source-workbench/AuZiXTarget/System/Settings/runtime-paths.json
```

This gives BKC and the slow worker a stable entry point before the expensive
source builds are enabled.

The Stage 2 target root is intentionally data-first:

```text
System/S/system-startup.json      ordered system phases
System/S/package-startup.json     package-owned startup entries
System/S/system-startup.lua       small Lua sequencer entry point
System/Settings/runtime-paths.json shared library search/promotion policy
System/PackageDB/*.json           receipts for staged core components
```

Bash remains the container entry point only long enough to prepare and validate
the workbench. The target itself is shaped around JSON manifests and Lua
sequencing so future build, package, and boot stages can share the same control
model.

To keep the generated root open for inspection:

```sh
make auzix-source-workbench-review
docker exec -it auzix-source-workbench-review-1 bash
```

Inside the review container, inspect `/workspace/out/source-workbench` and the
generated target root at `/workspace/out/source-workbench/AuZiXTarget`.

The review container is the pre-ISO gate. It should validate manifest shape,
target layout, startup JSON presence, startup Lua syntax when `luac` is
available, and the runtime library policy before any ISO pipeline consumes the
root.

The Stage 2 library policy is deliberately simple: shared libraries are promoted
to `/System/Libraries`; package-private libraries stay under
`/Programs/<Name>/<Version>/Libraries`. Architecture split directories should
not be part of the normal runtime path for this workbench lane.
