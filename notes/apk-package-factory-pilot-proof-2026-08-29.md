# APK package factory pilot proof — 2026-08-29

## Decision

AUZiX package and root assembly authority moves to the Python control plane,
small JSON package/profile/activation contracts, FPM package emission, and
apk-tools transaction state. Legacy scripts remain payload producers only.
They are not allowed to repair or mutate the assembled root behind APK.

## Proven on `r730-ai-01`

- Dedicated image: `auzix/package-factory:pilot-20260829`
- Image digest: `sha256:90ed93995d49c935a4f6a3afc8e2ef17572f86b50b5fb93432a433663b9da421`
- FPM: `1.17.0`
- APK bootstrap: Alpine v3.22 `apk-tools-static` `2.14.10-r0`
- Bootstrap SHA-256: `c86e3822764e5fe19f41ce2e13553e48cac1ea4e74f858338e8d44bf0b616b61`
- Proof result: FPM emitted `auzix-factory-proof_1.0.0_noarch.apk`; pinned
  `apk.static` installed it into an empty root; the installed payload matched;
  `apk info` returned `auzix-factory-proof`.

## Compatibility boundary

Do not upgrade the pilot to APK v3. FPM 1.17.0 packages omit the APK v2
`datahash` field that APK v3 requires. APK 2.14.10 accepts the package and warns
that packages without `datahash` will lose support in APK 3. Signing and
APKINDEX generation remain promotion blockers; the proof used an untrusted
local package intentionally.

## Current deterministic target

`python3 -m auzix compose-target base-netinstall-hdd` produces a headless plan
containing 20 AUZiX package definitions with no external providers. `LibgccS1`
is a first-class locked package, and every selected payload now has mapped
provenance. Base activation has a local fake-root proof and preserves the
known-good BusyBox `udhcpc` dotted-netmask behavior.

## Next gate

Implement one staging adapter that consumes a package definition and produces
a manifest-checked staging root. Run it first for the small runtime spine,
emit/index/sign those APKs, install the exact lock into an empty root, compare
APK state and files to the lock, then activate. Do not invoke the legacy HDD
assembler or write an HDD before those receipts pass.

## Real runtime-spine result

The next lab pass emitted and installed four real AUZiX packages from the r5
evidence image: `LibgccS1`, coherent `RuntimeGlibc`, `BusyBox`, and
`ApkTools`. APK installed all four into an empty root, `apk info` matched the
lock, all staged and installed file hashes matched, AUZiX symlinks survived,
and installed BusyBox executed. The structured evidence is
`packaging/proofs/runtime-spine-r730-20260829.json`.

The larger base loop did not launch. Its availability audit showed that the r5
image does not contain several package surfaces at their declared prefixes.
Those definitions must be corrected to concrete receipt versions or their
mapped producers must run first. This is a package-intake gate, not an HDD
assembler problem.

## Native archive-to-APK and Docker proof

The consolidated Trixie AUZiX archives now pass through one deterministic
adapter: frozen repository index and profile, checksum/tar preflight, FPM APK
emission, APK verification, architecture-partitioned repository, fresh-root
transaction, then activation. Debian intake retains its native binary-package
atoms (`htop`, `libncursesw6`, `libreoffice-writer`); only AUZiX-authored
packages retain the `auzix-*` namespace.

Thin-root Debian assumptions are explicit profile edges. Htop and Glances add
`ncurses-base`; Htop resolves as `htop -> libncursesw6, libtinfo6,
ncurses-base`. The Flatpak overlay pins `BusyBox -> auzix-busy-box` and must not
publish the older competing BusyBox provider.

Library relocation is package-generation work, not activation repair. A
library APK owns `/Libraries/Packages/<AUZiXName>`, a compatibility symlink at
`/Programs/<AUZiXName>`, and its public SONAME links directly under
`/Libraries`. Leaf-private application libraries remain private. The targeted
APK proof installed `libncursesw6`, `libtinfo6`, `ncurses-base`, and `htop`
into an empty root and proved package-owned library directories and SONAMEs.

The refreshed persistent proof is `auzix-netinstall-proof` on Docker context
`bkc-auzix-r730`. It began as an 11 MiB five-package bootstrap and installed
`htop glances flatpak` by public APK name from the mounted 129-package union.
Htop ran with a real TTY and `TERM=xterm-256color`; Glances 4.3.1, Flatpak
1.16.1, BusyBox top, and ps passed. The first 414-package graphical transaction
also resolved and installed completely, then correctly exposed the remaining
pre-existing library-surface defect: AbiWord could not find
`libfribidi.so.0`, and LibreOffice oosplash could not close its loader chain.
The package-owned SONAME transform was added in response; broad repositories
must be regenerated and installed into a fresh proof root before those app
front doors are promoted.

The Docker graphical overlay is deliberately split by existing artifact lane:
current consolidated Xorg/AbiWord/LibreOffice closure; five-package Flatpak
overlay from the earlier reviewed repository; and the known-good three-package
Enlightenment/Terminology/LightDM shell overlay. HDD assembly remains outside
this proof boundary.
