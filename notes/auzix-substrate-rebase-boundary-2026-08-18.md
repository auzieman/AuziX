# AUZiX substrate rebase boundary — 2026-08-18

This is a hard architecture break, not a continuation of the prior workstation
patch loop.

## Why this boundary exists

The previous package factory shape allowed leaf/application packages to collect
their `ldd` closure into `/Programs/<App>/<Version>/Libraries` and then launch
through that local library set. That made some early demos launch quickly, but
it also allowed leaf apps to carry copies of core/runtime/platform libraries:

- glibc / loader / libgcc / libstdc++
- OpenSSL / NSS / CA-facing security runtime
- X11 / Mesa / input stack pieces
- GLib / GTK / font stack pieces
- EFL / Elementary / Enlightenment-facing pieces

That is not a safe distro model. Apps cannot replace the substrate without
systemic side effects. If a core/platform library changes, AUZiX needs a planned
base/substrate rebuild followed by dependent app validation, not app-local ABI
shadowing.

## New rule

AUZiX package builds now start from a negotiated base release:

1. assess requested package set and upstream versions;
2. choose one coherent base/runtime substrate;
3. build/install the substrate libraries and dev surfaces first;
4. keep headers, pkg-config, CMake files, GIR/typelibs, schemas, helpers, and
   other development surfaces in the builder;
5. build apps against that substrate;
6. package leaf apps with only app-private libraries/resources;
7. validate launchers and CLI tools against the same base;
8. publish only after runtime audit passes.

Debian/Trixie remains reference/feedstock. It is not a separate runtime universe
per app.

## Preserve

Keep these lessons and changes:

- `packages/auzix-base-release.alpha-0.0.1.json`
- `packages/base-release-lock.alpha-0.0.1.json`
- `scripts/auzix-library-policy.sh`
- app-local substrate audit in `scripts/audit-auzix-package-runtime.sh`
- preserved profile order in `scripts/run-auzix-trixie-intake.sh`
- EFL and Enlightenment version identities must remain separate
- `/System/Libraries` and `/System/Libraries/Runtime/glibc` must lead
  `LD_LIBRARY_PATH`
- `TERMINFO_DIRS` is canonical; do not export a single stale `TERMINFO`
- AUZiX Terminal and installer EFL frontend are separate canaries
- VMID132/Trixie is the guidebook for permissions, services, package scripts,
  desktop entries, and session behavior

## Quarantine / rebuild

Do not promote package archives produced by the old app-local closure model
unless they pass the new substrate audit.

Likely rebuild candidates include packages that previously bundled or launched
through local substrate copies:

- command-suite packages using app-local `ld-linux`
- Curl
- Midori
- AbiWord/Gnumeric office wrappers
- Terminology/EFL-facing live media packages if the ISO was built before the
  EFL identity/path fixes
- any package whose receipt or payload exposes substrate libraries from
  `/Programs/<LeafApp>/<Version>/Libraries`

## Immediate validation shape

Before a new public/semi-public ISO or repo push:

```text
manifest -> base lock -> substrate/dev build -> app build -> runtime audit
-> validation container -> VMID135/ESXi smoke -> publish
```

Passing checks must include:

- no app-local core/security/desktop substrate libraries;
- no app-local dynamic loader front door;
- package wrappers use base loader and base-first library path;
- installer EFL frontend opens;
- AUZiX Terminal/xterm rescue path opens;
- Midori/Firefox CA trust works;
- at least one GTK editor launches;
- LibreOffice Writer/Calc/Impress/Draw launch from explicit commands before
  menu promotion;
- E menu entries are emitted only for validated front doors.

This note is the line in the sand. Work after this point should not blend old
dirty package outputs into the new base-manifest model.
