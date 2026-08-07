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
packages/base-ports.manifest.json      non-GUI through X11/EFL ports sequence
packages/extended-ports.manifest.json  filesystem and OCI host ports sequence
docker/source-workbench/Dockerfile     minimal bootable workbench container
scripts/source-workbench-boot.sh       manifest boot/plan entry point
scripts/build-source-workbench-native-container.sh phase 3 native container
scripts/generate-base-ports-plan.sh    base ports plan/report generator
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

## Phase 3 Native Workbench

The next gate builds a runnable container from the validated `AuZiXTarget` root:

```sh
make auzix-native-workbench
```

Generated outputs:

```text
out/source-workbench/native-container/context/Dockerfile
out/source-workbench/native-container/context/rootfs/
out/source-workbench/native-container/native-container-report.json
out/source-workbench/native-container/native-workbench-image.tar
out/source-workbench/native-container/native-workbench-rootfs.tar
```

Review it as a persistent container:

```sh
make auzix-native-workbench-review
docker exec -it auzix-native-workbench-review-1 bash
```

Run the background worker in plan-only mode:

```sh
make auzix-native-workbench-worker
docker logs -f auzix-native-workbench-worker-1
```

This is the first "AuZiX workbench builds the AuZiX workbench" shape. It is not
yet a pure `FROM scratch` system because the staged root does not own shell,
Lua, `jq`, certificates, or process tools yet. The Phase 3 image uses a tiny
Debian compatibility base to provide those review tools, then overlays the
validated AuZiX root at `/`.

The output is import-friendly:

```sh
docker load -i out/source-workbench/native-container/native-workbench-image.tar
docker import out/source-workbench/native-container/native-workbench-rootfs.tar auzix/native-workbench:imported
```

Those tarballs are suitable for NFS publication or BKC handoff.

The Phase 3 image also carries:

```text
/System/Build/Manifests/base-ports.manifest.json
/System/Build/Commands/auzix-base-ports-worker
```

The worker currently runs in `plan-only` mode and writes:

```text
out/source-workbench/base-ports-worker/base-ports-plan.txt
out/source-workbench/base-ports-worker/base-ports-worker-report.json
```

## Eating Debian

The bridge container is useful only if each Debian-provided tool becomes an
AuZiX-owned port. The source of truth for that sequence is:

```text
packages/base-ports.manifest.json
```

Generate the current plan without compiling:

```sh
make auzix-base-ports-plan
make auzix-extended-ports-plan
```

Generated outputs:

```text
out/source-workbench/base-ports/base-ports-plan.txt
out/source-workbench/base-ports/base-ports-report.json
```

The manifest intentionally runs from bootstrap runtime tools through X11/EFL
prerequisites:

```text
00-bootstrap-runtime  BusyBox, Lua, CA certs
01-source-fetch       Zlib, OpenSSL, Curl
02-build-toolchain    pkg-config, make, cmake, meson, ninja
03-core-libraries     ffi, pcre2, xml, image, font libraries
04-x11-base           xorgproto, xcb, libX11, Xorg server
05-efl-edge           GLib, D-Bus, Pixman, Cairo, EFL
```

The repository-only extended lane follows with full filesystem tools, then the
OCI substrate, Podman, and Docker. BusyBox `mkfs.ext2` and `mkfs.vfat` remain
recovery fallbacks; they are not the installed-host filesystem contract.

Run the extended planner in the native workbench with:

```sh
make auzix-extended-workbench-worker
```

The worker remains plan-only. Ollama may receive a bounded failure packet once
a phase runner exists, but it cannot publish packages or advance target state.

The first executable extended slice builds E2fsprogs and Dosfstools as honest
`first-pass-debian-repack` packages:

```sh
make auzix-extended-filesystem-build
```

It creates disposable ext4 and FAT images, checks both filesystems, and writes
`out/source-workbench/extended-ports/filesystem-tools.report.json`. A failed
slice writes a bounded packet below `extended-ports/failures/` and requests an
advisory-only contract adjustment from the configured Ollama worker.

Every target must install under `/Programs/<Name>/current` and promote shared
runtime libraries only into `/System/Libraries`. The report lists the tools
still inherited from Debian so each phase can shrink that list.

The promotion path is:

```text
Stage 2: validate AuZiXTarget layout and runtime policy
Stage 3: build/run a native-layout AuZiX container from that root
Stage 4: build base ports from the manifest into /Programs and /System/Libraries
Stage 5: remove inherited Debian tools and move toward scratch/chroot/ISO
```
