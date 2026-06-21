# AuZiX Build Flow Notes

This project should stay readable for humans and other AI agents. The working
rule is simple: Linux already provides source packages, build systems, linkers,
boot tools, and service conventions. AuZiX should remix those outputs into its
root contract instead of recreating the whole operating system in shell.

## Intended Flow

Use this mental model when adding or repairing packages:

```text
sources/<component>/        checked-in local sources, probes, or patch roots
out/build/<component>/      unpacked upstream source and build work
out/stage/<component>/      DESTDIR-style installed tree before packaging
out/packages/<component>/   AuZiX package archives and receipts
artifacts/auzix/            publishable ISO/repository artifacts
```

`out/` and `artifacts/` are generated and ignored. A source/build manifest
should describe how to reproduce them.

## Package Intake Contract

The preferred package path is:

1. Locate the source package or upstream tarball.
2. Apply only scoped patches under a package-specific patch directory.
3. Prefer normal build arguments first:
   `PREFIX`, `DESTDIR`, `LIBDIR`, `SYSCONFDIR`, `LOCALSTATEDIR`,
   `PKG_CONFIG_PATH`, `LD_LIBRARY_PATH`.
4. Build with the package's own build system: `make`, `meson`, `ninja`,
   `cmake`, or equivalent.
5. Stage into `out/stage/<component>`.
6. Generate the AuZiX receipt from staged files and validation evidence.
7. Promote only deliberate compatibility exports into `/System/Compatibility`.

Debian `debian/rules` is useful reference material, but it is not mandatory
once we are not producing `.deb` packages.

## Current Manifest Starting Point

The first source-build catalog is:

```text
packages/source-build.sources.json
```

That file captures the NetSurf lesson: build from the nested upstream tree,
override paths deliberately, record `ldd` evidence, and decide whether shared
libraries are package-owned, promoted to `/System/Libraries`, or declared as
dependencies.

## What Not To Do

Avoid adding more broad startup repair shell unless the package contract cannot
own the invariant.

Examples of package-owned invariants:

- command wrappers and environment variables
- user-writable profile/cache directories
- desktop entries and XDG data paths
- service start commands and required users/groups
- library search paths and bundled loader contracts

Boot scripts should mount core filesystems, start the minimum runtime, and hand
off to package-owned contracts. They should not become a second package manager.

## BKC Loop

BKC should run progressively more expensive gates:

```text
core root validation -> package/repository validation -> ISO build -> VM boot
```

Use `auzix-core-root-validation` before spending time on Proxmox when changing
core paths, users, permissions, package receipts, boot startup, browser profile
behavior, or graphical substrate packages.
