# AUZiX legacy alias usage contract — 2026-08-22

The live ISO currently keeps classic top-level aliases:

- `/bin -> /System/Compatibility/bin`
- `/sbin -> /System/Compatibility/sbin`
- `/lib -> /System/Compatibility/lib`
- `/lib64 -> /System/Compatibility/lib64`
- `/usr -> /System/Compatibility/usr`
- `/etc -> /System/Settings`
- `/var -> /System/State`
- `/root -> /Users/root`
- `/opt -> /Programs`

These aliases are not neutral. If a classic path exists, upstream software can
jump to it before the AUZiX `PATH`, `LD_LIBRARY_PATH`, `XDG_*`, or app wrapper
contract has a chance to redirect behavior.

That means an alias can hide bugs in two directions:

1. A package may appear to work because `/usr`, `/etc`, `/var`, or `/lib64`
   accidentally satisfies an upstream hardwire.
2. A package may ignore AUZiX-native paths because the classic path exists and
   wins first.

## Current audit result

The small-moon CA ISO still actively relies on aliases:

- ELF interpreters request `/lib64/ld-linux-x86-64.so.2`.
- Xorg, EFL, Enlightenment, LightDM, PulseAudio, ALSA, DBus, fontconfig, and
  Midori still contain `/usr`, `/etc`, `/var`, or `/lib64` references.
- DBus and desktop startup still use `/etc/machine-id` and
  `/var/lib/dbus/machine-id` compatibility paths.
- CA trust is available through AUZiX-native settings, but consumers still probe
  Debian/Fedora-compatible paths such as `/etc/ssl` and `/etc/pki`.

Therefore the current live ISO should keep aliases for boot/demo stability.

## Strict-root testing rule

Strict-root work must be measured in two modes:

1. Alias-present observation:
   - boot or chroot with aliases intact;
   - use `lsof`, logs, wrapper traces, and string/readelf scans to identify
     which classic paths are actually used.
2. Alias-absent failure probe:
   - use a throwaway copied root or disposable VM;
   - remove only the top-level aliases from the copy;
   - run static checks and small command probes;
   - record the first real missing path or loader failure;
   - do not patch the live/demo root in place.

The output of strict-root probes should feed package build contracts and wrapper
contracts. It should not become one-off rescue shell surgery.

## Package rule

Packages should prefer AUZiX-native paths first. Compatibility aliases are
allowed as a transitional substrate, but package validation must distinguish:

- "works because the AUZiX path contract is correct";
- "works only because a classic alias exists."

The long-term goal is to move classic aliases into a post-install compatibility
profile or optional package layer. The live ISO can carry them until strict-root
validation proves a smaller set is safe.

## Leaf install must not replace root aliases

Follow-up from the VMID135 package-tool guard: runtime lookup policy and archive
extraction policy are separate. AUZiX may temporarily expose compatibility aliases
such as `/lib64`, `/usr`, `/etc`, `/var`, `/root`, and `/opt`, but normal app
package transactions must never replace those links/directories or their active
runtime substrate.

`auzix-pkg` leaf transactions now block archives containing top-level root alias
paths and protected runtime surfaces unless explicitly run as an installer/base
transaction with `AUZIX_ALLOW_SUBSTRATE_INSTALL=1`.

Rule: no package should replace an existing root alias, core link, or shared
library substrate as a side effect of installing an app. If that is required,
it is a base release update, not an app install.

## Runtime linker refresh for real substrate changes

If an installer/base transaction intentionally changes shared libraries, it must
refresh the runtime linker view as part of the transaction. Normal leaf installs
should not touch substrate paths at all. Base/substrate transactions may opt in
with `AUZIX_ALLOW_SUBSTRATE_INSTALL=1`, but after extraction and post-install
hooks they must run the AUZiX equivalent of `ldconfig` when available.

`auzix-pkg` now attempts `ldconfig` from AUZiX/compat locations after extraction
and again after post-install hooks. Missing `ldconfig` during an allowed substrate
transaction is a warning and a packaging gap to close, not something app packages
should work around by replacing links or copying core libs.

## Strict alias mode correction — 2026-08-22

New conclusion from the live ISO/package-install failure: root compatibility must be an alias policy, not persistent symlink churn performed by package installs or live finalizers.

Working rule:

- `/System/Compatibility/...` remains an AUZiX-owned compatibility namespace.
- Top-level legacy surfaces such as `/bin`, `/sbin`, `/lib`, `/lib64`, `/usr`, `/etc`, `/var`, `/home`, `/root`, and `/opt` must not be removed/relinked during normal package installation.
- `finalize-installed-root` defaults to `AUZIX_LINK_MODE=strict` and skips compatibility surface refresh unless explicitly launched with `AUZIX_LINK_MODE=compat`/`full` or booted with `auzix.links=compat`.
- `auzix-pkg` invokes the finalizer with strict link mode by default after package extraction.
- If a compatibility escape hatch is needed, it should be a deliberate boot/install profile and eventually an alias/mount policy, not package-owned `ln -sfn` repair.

RCA shape: live installs became unstable because link refresh could replace or detach paths that running X/E/DBus/libc consumers had already resolved. The strict fix is to avoid mutating those paths in the live root. Packages may install their own `/Programs/<Name>` payload and metadata; base/substrate transactions are the only lane allowed to modify global runtime surfaces.

## Next ISO rule: strict first boot

The next ISO should boot without top-level legacy links by default. Let it fail, collect the first missing path/symbol/log, and fix the AUZiX path contract or package wrapper. Do not pre-rescue the ISO with `/usr`, `/lib`, `/lib64`, `/bin`, or similar root links.

Implemented local source-side guard rails:

- `scaffold-auzix-strict-root.sh` defaults to `AUZIX_LINK_MODE=strict` and does not create root compatibility links unless explicitly run with `AUZIX_LINK_MODE=compat`/`full`.
- `build-auzix-boot-iso.sh` writes `auzix.links=strict` into GRUB entries.
- `validate-auzix-boot-iso.sh` fails publication if `auzix.links=strict` is missing.
- `activate-auzix-basic-config.sh` skips root alias creation unless the compatibility hatch is explicit.
- `finalize-installed-root` and package install paths default to strict finalizer mode.

Emergency hatch remains deliberate: boot or run with `auzix.links=compat` / `AUZIX_LINK_MODE=compat` when comparing against the old compatibility substrate. That hatch is diagnostic, not the default release behavior.

## Strict-first build findings

First R730 strict-first ISO attempt failed in useful places:

1. `E2fsprogs` validation used bare `truncate` and `/tmp`. In strict mode those are not guaranteed top-level aliases. Fixed the command-suite recipe to use `/Programs/BusyBox/current/Commands/busybox truncate` and `/Work/Temp`.
2. `PulseAudio` package script hardcoded `/usr/lib/pulse-16.1+dfsg1`. The Trixie builder currently carries a newer PulseAudio runtime directory, so `find` returned failure under `pipefail`. Fixed the package script to discover `/usr/lib/pulse-*` and iterate only existing staged directories.
3. `KernelModules` validation treated compressed kernel modules (`*.ko.xz`) and built-in kernel features as missing. Fixed the module packager so required gates accept `.ko`, `.ko.xz`, `.ko.zst`, `.ko.gz`, or a matching entry in `modules.builtin`, and so dependency recursion strips compression suffixes before deriving module names.
4. The access package was still creating root-level compatibility links after the strict scaffold. Fixed `build-auzix-access-package.sh` so `/bin`, `/sbin`, `/lib`, `/lib64`, `/usr`, `/etc`, `/var`, `/tmp`, `/opt`, `/home`, and `/root` are only created when `AUZIX_LINK_MODE=compat`/`full` is explicit. Strict is the default.
5. Strict access also exposed Bash/OpenSSH as host-interpreter binaries. The package now requires `patchelf`, patches copied command payloads to `/System/Libraries/Runtime/glibc/ld-linux-x86-64.so.2`, and leaves public commands as AUZiX loader wrappers. The builder image now includes `patchelf` as a first-class build tool.
6. `Parted` exposed a validation-environment bug rather than a bad staged binary. The AUZiX-staged `parted.real` runs when invoked with the AUZiX loader and host-prefixed staged library path, but it segfaults in an empty build chroot without live kernel/runtime filesystems. The command-suite builder now supports explicit host-prefixed smoke commands for that class of tool, and the `jq` boolean gate was fixed so `chroot_smoke: false` remains false instead of falling through to the default. `Parted` is patched to the AUZiX interpreter and validates without creating top-level legacy links.
7. The final strict audit found host-copied dynamic ELFs that still requested `/lib64/ld-linux-x86-64.so.2`. Added `normalize-auzix-elf-runtime.sh` as a build-level finalizer before repo packaging and before audit. It patches executable ELFs under `/Programs` and `/System/Tools` to the AUZiX core loader plus native runpath. The audit regex was also tightened so `/System/Compatibility/usr/...` is not mistaken for a top-level `/usr` relapse.
8. Installer audit was falsely failing after ELF normalization because the test harness still invoked package-local loader copies for Lua and jq. Those local loader invocations segfaulted, while the same binaries ran correctly through `/System/Libraries/Runtime/glibc/ld-linux-x86-64.so.2`. The installer self-test and strict audit now use the AUZiX core loader/library substrate. Result on the staged R730 root: `AuziX installer tests: PASS` and `Auzix strict root audit: PASS`.

SELinux note: SELinux libraries may appear as passive dependencies, but AUZiX alpha must not enable SELinux enforcement or assume `/etc/selinux`. Until a native policy story exists, any boot/runtime gate should treat active SELinux as disabled/permissive-only. This is especially important in strict-root mode because AUZiX pathing will not look like a stock SELinux-labelled distribution.

These are package/build-contract fixes, not reasons to restore root legacy links.

## r5 correction: runtime link gating includes `/opt` and `/root`

Follow-up from the strict handoff diff: the fresh strict scaffold was already
gated, but `StartSequence` still created `/opt -> /Programs` and
`/root -> /Users/root` unconditionally at runtime. That violated the same
contract even though the staged root looked clean.

Correction:

- `StartSequence` now parses `AUZIX_LINK_MODE` / `auzix.links=`.
- `/opt` and `/root` are created only for explicit compat/full link mode.
- Strict mode remains the default.

Lab-build smoke verified a fresh strict root plus live tools has no top-level
aliases after generation.
