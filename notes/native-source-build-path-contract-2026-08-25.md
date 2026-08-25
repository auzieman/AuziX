# Native source-build path contract

## Decision

The Debian binary-intake/repack lane is a temporary compatibility lane. It is
not proof of a native AUZiX build because it preserves upstream compiled-in
legacy paths such as `/usr`, `/lib`, `/etc`, and Debian multiarch locations.

The native factory must unpack the Debian source package, apply its declared
patch and preparation sequence, and configure and compile it inside a locked
AUZiX build sysroot. The sysroot contains exactly the selected AUZiX base
libraries and development surfaces. Host libraries and alternate core runtime
providers are forbidden.

## Required order

1. Resolve and lock one coherent Debian/Trixie source and dependency graph.
2. Build and install the base libraries and development headers into the AUZiX
   build sysroot in dependency order.
3. Unpack each source package and apply Debian's source preparation and patch
   lifecycle.
4. Configure it with AUZiX prefixes, sysroot, compiler, linker, and pkg-config
   paths. Legacy paths are compatibility exceptions, not defaults.
5. Compile and perform a staged install using the package's native build
   system and lifecycle.
6. Package the staged files while preserving ownership, modes, capabilities,
   links, and applicable pre/post-install intent.
7. Validate ELF interpreter, required symbols, resolved providers, embedded
   paths, CLI behavior, and normal-user desktop launch against the same locked
   base.

If configure cannot use the locked base, select a compatible source version or
perform an explicit base migration followed by ordered dependent rebuilds. Do
not silently use the Debian host, download a newer core library, or create an
application-private libc.

## Current bounded run

The `auzix-alpha-base-trixie-20260825-r3` delta is allowed to finish as a
compatibility/package-lifecycle validation run. Its output must not be labeled
as native source-built. Representative runtime checks may inform the native
factory, but wrapper-based legacy path accommodation is technical debt to be
removed by the source-build lane.
