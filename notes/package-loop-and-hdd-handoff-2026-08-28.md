# Package loop and HDD handoff — 2026-08-28

## Recentered design rule

Do not model AUZiX packaging, repository consolidation, release assembly, or
media creation as one monolithic JSON or shell operation. Each stage consumes
an explicit list and emits an immutable receipt. Whether the list contains five
packages or two thousand, the transaction loop is the same; only the list size
and bounded scheduling change.

```text
locked package list
  -> locate existing payload/build inputs
  -> apply package lifecycle metadata
  -> emit immutable package spool and receipt
  -> consolidate reviewed spools into a repository and receipt
  -> assemble an explicitly named release and receipt
  -> validate the release contract
  -> install the validated repository profile into a fresh root
  -> wrap that installed root as HDD/live media and validate boot
```

Payload build, package finalization, repository consolidation, release
publication, root installation, and media wrapping are separate phases.
Repackaging must not imply recompilation. A package such as LibreOffice is an
ordinary list entry, not a reason to create package-specific release assembly.

## Authority and receipt rules

- The frozen repository index is the dependency-closure authority for release
  packaging. Mutable build-root receipts are evidence from an earlier phase,
  not final repository truth.
- Logical release identity is an explicit input. It must never be inferred
  from a candidate or temporary directory name.
- Each downstream stage consumes the previous stage's receipt instead of
  rediscovering state from incidental directories.
- Release validation must prove index, manifest, hashes, package count,
  dependency closure, source/target identity, and receipt agreement together.
- HDD composition must install packages from the validated repository into a
  fresh target root. Copying or rsyncing a prepared/validation root is not an
  authorized substitute for the package transaction.
- The media writer owns only partitioning, filesystem creation, boot payload,
  bootloader installation, checksum, and boot smoke after root composition.

## Immediate HDD gate

The existing BKC HDD script that passes a validation root to
`build-auzix-live-disk-image.sh` and copies that tree into the image does not
meet this contract. The established package-profile installer loop in
`scripts/auzix-install-root-from-repo-profile.sh` is the intended composition
path. The HDD pipeline must invoke or factor that loop against the exact
validated release repository and profile, then pass its installed-root receipt
to the media wrapper. Do not launch HDD assembly from a copied validation root.

## Implemented package-profile HDD lane

The BKC pipeline is `pipelines/auzix-release-hdd-build-deploy`. Its bounded
`desktop-main.packages` profile has 28 requested roots. The frozen composite
selection resolves to 640 packages and 1,252,279,304 compressed archive bytes
with no missing dependency edges or archives. Source provenance is r5 release
606, composite proof 28, native strict repository 5, and corrected LibreOffice
Writer spool 1. The complete catalog remains source authority; only this
resolved closure becomes the HDD transaction.

The build uses the old strict root only as a chroot execution seed. It does not
copy that seed into the target. The tagged installer source is mounted into the
seed, `AUZIX_INSTALL_COPY_SEED_RUNTIME=0` is mandatory, and `auzix-pkg` plus the
package-profile installer own target composition after scaffolding.

## Attempt ledger: preserve, diagnose, then advance

Do not overwrite or reuse a failed run directory. Each attempt has one run ID,
one source tag, logs, and a single diagnosed boundary before the next run.

| Run | Last proven boundary | Root cause / disposition |
| --- | --- | --- |
| r1 | installer invocation | Tagged installer lacked executable mode; invoke the script through BusyBox `sh`. |
| r2 | repository fetch | HTTP server was not readiness-gated; probe it before entering the installer. |
| r3 | repository parsing | Old seed `jq` crashed on the full catalog; the target transaction should consume a selected index. |
| r4 | selected index parsing | Old seed `jq` also crashed on the lean index; stage a host-matched, installer-scoped `jq`, never as target payload. |
| r5 | partitioning | Old seed `parted` crashed; the host media wrapper must own sparse-image partitioning and formatting. |
| r6 | prepared partition discovery | Installer converted `/dev/loop0` to `/dev/loop01`; loop devices require the `pN` partition suffix. |
| r7 | stage 5, strict-root scaffold | The loop suffix correction worked: partitions mounted and seed copying stayed disabled. The process then exited without a build receipt or fatal log line and left `/dev/loop0` attached. Preserve r7 for diagnosis; do not call it running or relaunch it unchanged. |

Immutable r7 inputs are HDD ID `desktop-main-20260828-r7`, AUZiX source tag
`auzix-alpha-package-profile-hdd-20260828-r4` at commit `3993cd5`, and the
selection totals above.

## No-loop operator gate

Before another HDD attempt:

1. Read this ledger and the previous attempt's installer and launch logs.
2. Prove the prior process state, build receipt state, mounts, and loop devices;
   a stopped log is not a running build.
3. Explain the exact failing command or add enough error trapping to expose it.
4. Correct that boundary in committed source and add a preflight assertion when
   the condition is knowable before mutation.
5. Assign a new run ID and immutable source tag. Never live-edit an active run.
6. Run preflight once, launch once, and monitor process plus receipt—not tail
   activity alone.

The r7 loop attachment is failure evidence and cleanup debt. Resolve it safely
after confirming no process or mount owns it, before a later run claims the
same loop device.

## Quality checkpoint 1: bootstrap ownership review

Status: draft for operator review; do not launch another HDD attempt yet.

## HDD r9 runtime regression and fixed gate

`desktop-main-20260828-r9` populated the intended 642-package root, then the
HDD-only configure stage injected `ld-linux`, `libc`, and `libm` from the stale
`strict-r8-busybox-xorg-dns` work tree.  Those files did not match the runtime
already proven by the release containers.  BusyBox/static commands survived,
while `sshd`, Glances, htop/top, Xinit, Xorg, and Enlightenment failed in the
dynamic loader.

The HDD lane now accepts runtime only from the pinned validated pre-HDD release
and verifies the exact loader/libc/libm hashes before partitioning.  It also
publishes the runtime compatibility aliases, runs the shared Debian-style
RootFS activation before `finalize-installed-root`, and refuses a passing
configure receipt unless representative dynamic executables load and run.
Never restore a mutable historical work directory as an HDD runtime source.

The package installer runs from the builder/chroot seed and accepts an explicit
target root. Therefore the empty target does not need a copied desktop or a
complete runnable userspace before archive installation begins. Its legitimate
pre-package state is limited to the filesystem hierarchy, account/config
skeleton, mounted Root/Home/Work filesystems, and an empty package database.

The first target package must be the AUZiX-native `BusyBox 1.36.1` archive. It
is statically linked and owns `/Programs/BusyBox/1.36.1`,
`/Programs/BusyBox/current`, the compatibility commands, and its PackageDB
receipt. It can provide the target shell/tool spine without glibc.

The r7 selected repository instead chose Debian-repacked `Busybox
1-1.37.0-6+b8` because r5 repository precedence overwrote the native
case-insensitive `BusyBox` identity. That archive owns `/Programs/Busybox`
(lowercase second `b`) and does not provide the established
`/Programs/BusyBox/current/Commands` contract. This is a deterministic provider
selection defect, not an HDD execution failure. The next install plan must pin
the native AUZiX BusyBox provider before it can pass checkpoint 1.

`AuzixPackageTools 0.1` then supplies `auzix-pkg`, `jq`, and its private loader
libraries. Its current dependency chain pulls Curl and approximately thirty
network/TLS libraries before package tools, although archive downloads are
performed by the external installer seed. This order is valid but is not the
smallest bootstrap; it should remain frozen for the next proof rather than be
redesigned during HDD assembly.

The current repository has no `Libc6` archive. Canonical glibc loader/libc and
`libgcc_s` are presently supplied later by the established root-prep/runtime
compatibility repair. Until AUZiX publishes and validates an owning Libc6
package, that repair must be explicit and receipted with source hashes. It may
not carry desktop files, menus, applications, or an entire prepared root.

Checkpoint 1 passes only when the immutable install-plan generator proves:

1. AUZiX-native static BusyBox is the selected provider and first archive.
2. The target begins with no copied desktop/runtime tree.
3. Every pre-package target file is listed in the scaffold manifest.
4. Every post-package repair file is listed with its source hash and future
   package owner.
5. Desktop, session, menu, launcher, service, and application surfaces originate
   from packages plus named lifecycle/finalization hooks.

## Quality checkpoint 2: immutable install-plan proof

Status: generated twice with identical content hash; awaiting operator review
before a disposable-root transaction.

The standalone planner is
`pipelines/auzix-release-hdd-build-deploy/scripts/resolve-hdd-install-plan.py`
in BKC. It reads the frozen sources, resolves the profile, pins critical
providers, verifies every selected archive hash, rejects duplicate selected
identities and missing edges, and emits sequence numbers without installing
anything.

Current proof:

```text
format=auzix-hdd-install-plan-v1
plan_content_sha256=31a6dbf8a88976fbff0c16787d413e26aff15e6c6b1c0488e78e509f818e7bf6
roots=28
packages=642
archive_bytes=1253197666
sources=composite:29,native:5,r5:607,writer:1
external_provider=Libc6:compatibility-repair
dependency_cycle_edges=13
```

The count changed from 640 to 642 for correctness: the earlier resolver treated
`GCC14Base` and `LibgccS1` as external even though their corrected r5 archives
exist. They are now pinned to r5 and installed as packages. Only absent
`Libc6` remains external. Native static `BusyBox 1.36.1` is pinned at sequence
1; `AuzixPackageTools` is sequence 33 after its declared Curl/TLS closure;
`AuzixInstaller` is sequence 36. The corrected Writer spool is also pinned.

The Debian-derived graph has 13 back-edges across SSL, device mapper, EFL, and
LibreOffice dependency groups. The previous resolver silently broke recursive
visits. The new plan records every edge and declares the existing compatible
policy: deterministic dependency-first unpack with recursive re-entry skipped,
followed by closure-wide configure/finalize. These cycles must remain visible
in the receipt; they are not permission to discover packages during execution.

Running the planner twice produced the same content hash. No image, target
root, package spool, or repository was mutated during this checkpoint.

## Quality checkpoint 3A: repeatable sequential unpack

Status: passed twice; pause before compatibility repair and configure/finalize.

An initial 33-package bootstrap proof installed native static BusyBox through
`AuzixPackageTools` into an empty directory root. Both
`/Programs/BusyBox/current/Commands/busybox` and packaged private-runtime
`jq 1.7` executed successfully through `chroot`. This proves package composition
can start without the old seed's crashing `jq` and without copying a prepared
runtime or desktop.

The exact 642-package plan was then unpacked sequentially into two independent
roots. Every step verified its archive hash and required a matching PackageDB
receipt before advancing.

```text
proof_ids=checkpoint3-full-r1,checkpoint3-full-r2
install_plan_sha256=31a6dbf8a88976fbff0c16787d413e26aff15e6c6b1c0488e78e509f818e7bf6
unpacked_packages=642
final_package=FlatpakRuntimeSupport 0.1.0
root_apparent_size_each=2.7G
package_receipt_names=642
duplicate_receipt_names=0
content_manifest_sha256=0f0bbf4e008dcdde86a317cb431a83da84f0efc8e2e8d7d0cb0fdb13d2857571
```

Both roots have identical content manifests. Expected program surfaces exist
for BusyBox, package tools, Enlightenment, LibreOffice Writer/Calc/Impress,
AbiWord, Gnumeric, Clementine, Midori, Firefox ESR, Glances, Htop, and Flatpak.
Firefox's canonical package/path spelling is `FirefoxEsr`, not `FirefoxESR`;
the earlier probe's casing assumption was corrected rather than treated as a
missing application.

This checkpoint proves deterministic unpack only. It does not yet claim a
configured or bootable desktop. The next quality boundary is to inventory and
hash the minimal Libc6 compatibility repair, apply it to one disposable root,
run the existing root-prep/package finalization contract, validate desktop and
runtime surfaces, then replay that configure phase against the second root and
compare receipts/manifests.
