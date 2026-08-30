# AUZiX small-moon live ISO smoke — 2026-08-22

Scope: recover the last-known-good live ISO pattern after the failed proof-root ISO experiment. This ISO intentionally stays small: terminals, Midori, installer, Enlightenment, network/display spine, and SSH service assets. It is not the broad workstation/proof package root.

## Artifact

- Run id: `small-moon-20260822T161551Z`
- ISO: `/var/lib/auzix-build/published/auzix-small-moon-small-moon-20260822T161551Z.iso`
- Size: `763M`
- SHA256 sidecar verified on lab-build, PVE, and ESXi.

## Post-build loop mount / dirdiff gate

Report: `/var/lib/auzix-build/small-moon-audit/small-moon-postbuild-dirdiff.txt`

Result: `Summary failures=0`

Comparison against Aug 16 known-good ISO root:

- GOOD files/packages: `6324 files`, `34 packages`, `1.5G` extracted root.
- NEW files/packages: `6324 files`, `34 packages`, `1.8G` extracted root.
- EFL/E alignment preserved:
  - `/Programs/EFL/current -> /Programs/EFL/0.25.4-2`
  - `/Programs/Enlightenment/current -> /Programs/Enlightenment/0.25.4-2`
- Critical live surfaces present:
  - Terminology current link
  - Midori current link
  - AuzixInstaller and AuzixInstallerEfl current links
  - `/Services/ssh/run`
  - `/System/Settings/ssh/sshd_config`
  - CA bundle under `/System/Compatibility/etc/ssl/certs/ca-certificates.crt`
  - `/System/Settings/auzix-paths.sh`
- Broad proof-root markers absent:
  - LibreOfficeWriter
  - GnomeControlCenter
  - GCC14
  - Calligra
  - VLC
  - FirefoxEsr

## Deployment smoke

- PVE VMID135 attached and booted from the ISO:
  - `ide2: local:iso/auzix-small-moon-small-moon-20260822T161551Z.iso`
  - boot order `ide2;scsi0;net0`
- ESXi VM `auzix-esxi-workstation-media-01` attached and booted from:
  - `[datastore1] auzix-isos/auzix-small-moon-small-moon-20260822T161551Z.iso`
- ESXi serial evidence:
  - DHCP on `eth0`: `10.20.0.113/24`
  - runtime mounts started
  - rescue consoles started
  - live user home repaired
  - udev started
  - hardware detection ran
  - dbus started
  - network started
  - display handoff started
- Operator visual confirmation: desktop is visible.

## Known follow-up

SSH remains the old Aug 16 live-service warning, not a new regression from the small-moon rebuild.

Evidence:

- ISO contains OpenSSH binaries, host keys, `/Services/ssh/run`, and config.
- Writable chroot repro can run `sshd` successfully on alternate port `2222`:
  - `Server listening on 0.0.0.0 port 2222.`
- ESXi live boot still reports/behaves as port 22 not listening/refused.
- Prior note `notes/esxi-current-live-boot-smoke-2026-08-16.md` already records this exact follow-up and says the next source fix should include failing service log tails on serial.

Next source change should improve StartSequence service observability: if a declared service is absent from the process summary or TCP probe fails, print the tail of `/System/Logs/<service>.log` to serial/tty1. That should make the SSH failure deterministic without console paste games.

## CA-fixed rerun

After operator confirmed the first small-moon ISO reached the desktop but still
showed the browser CA problem, the thin assembler gained an explicit
`AUZIX_STAGE_BROWSER_TRUST=1` delta.

That delta re-runs only the checked-in CA and Midori trust package steps:

- `scripts/build-auzix-ca-certificates-package.sh`
- `scripts/build-auzix-midori-package.sh`

It does not re-run the broad live-tools provisioner and does not pull in the
proof/workstation package universe.

CA-fixed artifact:

- Run id: `small-moon-ca-20260822T163447Z`
- ISO: `/var/lib/auzix-build/published/auzix-small-moon-ca-small-moon-ca-20260822T163447Z.iso`
- Size: `764M`
- SHA256: `d2a99eb3adf73891ebd703d9328c49b4124db2845ea16fabc868be558321d5c3`

Post-build CA gate:

- package count stayed at `34`;
- broad proof-root markers remained absent;
- Midori trust DB was seeded with `150` CA entries;
- Midori staged:
  - `distribution/policies.json` with enterprise roots enabled;
  - `defaults/pref/auzix-cert-policy.js`;
  - `/System/Settings/browser/midori-default-profile/user.js`;
  - `/System/Settings/browser/midori-default-profile/cert9.db`;
  - `libnssckbi.so`;
  - wrapper exports `NSS_DEFAULT_DB_TYPE=sql`;
  - wrapper forces `--profile "${HOME}/.midori"`.

Deployment:

- PVE VMID135 was hard-reset onto the CA-fixed ISO.
- ESXi VM `auzix-esxi-workstation-media-01` was hard-reset onto the CA-fixed ISO.
- ESXi serial reached DHCP and display handoff again.

Package-lane observation from the operator:

- LibreOfficeWriter install on the thin base kicked off a large dependency
  chain, which is expected for a minimal live base but should be handled in the
  workstation/repo lane, not the small live ISO lane.
- AbiWord was not visible in the repo during that test and should be added to
  the workstation package manifest/repo validation follow-up.

Alias/path observation:

- The current live ISO intentionally keeps classic aliases for boot/demo
  stability.
- Those aliases are not neutral; if `/usr`, `/etc`, `/var`, or `/lib64` exists,
  some upstream software will use it before AUZiX path exports or wrappers can
  redirect behavior.
- See `notes/legacy-alias-usage-contract-2026-08-22.md` for the strict-root
  testing rule.

## Package transaction guard — BusyBox survived, ELF substrate was mutable

After the CA-fixed small-moon ISO booted, live package testing showed a sharper
failure mode: BusyBox/core shell remained usable, but outer ELF tools such as
`sudo` and `auzix-pkg` began throwing the same glibc/loader-class error after a
leaf package attempt. The LibreOffice Writer cancel did not obviously poison the
runtime; the Glances attempt exposed it.

This matches the older X bootstrap symptom: AUZiX had local fixes for X/E boot,
but the package manager still allowed normal leaf transactions to extract over
runtime substrate paths. A stale or substrate package could therefore relink or
replace `/lib64`, `/usr`, `/System/Libraries`, or `/System/Compatibility/*/lib*`
from a live desktop session.

Patch direction applied to `scripts/build-auzix-package-tools-package.sh`:

- treat core/runtime/platform packages as protected substrate during normal
  `auzix-pkg install` transactions;
- record already-present substrate as satisfied instead of reinstalling it;
- block missing substrate dependencies in leaf installs with a clear error;
- refuse archives touching protected runtime paths unless the installer/base lane
  opts in with `AUZIX_ALLOW_SUBSTRATE_INSTALL=1`.

Rule: live/package-manager installs may add apps and app-private files, but they
must not move the OS floorboards. Base rebuilds and installer root construction
own substrate mutation.

## Transaction prefetch boundary

Follow-up correction: live installs should not crawl by fetching, extracting,
and discovering the next dependency one by one. That pattern is slow and makes
runtime mutation harder to reason about.

`auzix-pkg install` now performs a visible transaction preflight:

1. seed provided/installed state;
2. compute the plan with `INSTALL_PLAN package=<name> new_packages=<count>`;
3. prefetch and checksum all planned package archives into
   `/Work/Temp/auzix-pkg/archives`;
4. run the protected-path archive gate before extraction;
5. only then extract/install packages.

This is still not the full native-rebase dry-map resolver. The full build lane
should fetch/resolve the whole selected package set first, then build/extract in
ordered substrate/app phases. This patch gives live package installs a bounded
transaction edge so failures happen before the root is mutated.

### Pull-only package proof

Added `auzix-pkg pull PACKAGE` as a no-mutation transaction proof:

- computes the same dependency plan as install;
- emits `PULL_PLAN package=<name> new_packages=<count>`;
- downloads archives into `/Work/Temp/auzix-pkg/archives`;
- verifies checksums;
- applies the protected runtime path gate;
- stops before extraction.

Recommended live ISO test order after rebooting clean media:

```sh
auzix-pkg refresh
auzix-pkg bootstrap-receipts /System/PackageDB
auzix-pkg bootstrap-runtime-substrate
auzix-pkg plan Glances
auzix-pkg pull Glances
# only if pull is clean:
auzix-pkg install Glances
```

If `pull` reports a protected substrate package or protected archive path, the
package/repo lane is wrong; do not install it live.

## 2026-08-22 pull-only correction and current lab targets

Correction: the first implementation made `pull` too strict. A pull-only
transaction is no-mutation; it should be allowed to fetch/checksum/cache archives
for inspection even when a later live `install` would refuse to mutate protected
substrate paths. The guard belongs on extraction/install, not on download.

Patch applied in `scripts/build-auzix-package-tools-package.sh`:

- `pull` exports `AUZIX_PULL_ONLY=1`;
- archive protected-path checks are skipped only for pull-only fetch;
- substrate package planning is allowed only for pull-only fetch;
- `install` still keeps the live substrate/path safety guard.

Current R730 Docker context view:

```sh
docker --context bkc-auzix-r730 ps
```

Active containers for this pass:

- `auzix-strict-rebase-shell`
  - image: `auzix/strict:rebase-52d2243d`
  - purpose: AUZiX-side validation shell.
- `auzix-finalize-repo-52d2243d`
  - image: `auzix/trixie-builder:lab`
  - purpose: builder/repo finalization lane.

Important correction: earlier proof output from `wonderful_mendel` was stale;
the live validation target for this pass is `auzix-strict-rebase-shell`.

Patched pull proof in `auzix-strict-rebase-shell`:

```text
PULL_PLAN package=L3afpad new_packages=13
PULL_DONE package=L3afpad archives_dir=/Work/Temp/auzix-pkg/archives
ARCHIVES_COUNT
13
```

Package cache paths:

- cache root: `/Work/Temp/auzix-pkg`;
- archive cache: `/Work/Temp/auzix-pkg/archives`;
- repo metadata cache: `/System/State/packages/repo-index.json`;
- installed-state DB: `/System/State/packages/installed.json`.

Fetched L3afpad proof archives included:

```text
L3afpad-0.8.18.1.11-4+b1.auzix.tar.gz
Libgtk3Bin-3.24.49-3.auzix.tar.gz
AtSpi2Core-2.56.2-1+deb13u1.auzix.tar.gz
Apt-3.0.3.auzix.tar.gz
DebconfI18n-1.5.91.auzix.tar.gz
```

PVE VMID135 currently runs from:

```text
local:iso/auzix-small-moon-pkgtool-only-r3.iso
```

VM config proof:

```text
135 Auzix-VM135 running
boot: order=ide2;scsi0;net0
ide2: local:iso/auzix-small-moon-pkgtool-only-r3.iso,media=cdrom
```

Reachability note:

- `192.168.1.198` responded as `auzix-live`;
- local SSH is blocked by changed known-host key at
  `/home/auzieman/.ssh/known_hosts:82`;
- ESXi live VM `10.20.0.113` currently refuses SSH from lab-build/jump.

Next VMID135 proof:

1. clear/update the known-host entry for `192.168.1.198`;
2. copy the patched `auzix-pkg` into
   `/Programs/AuzixPackageTools/current/Commands/auzix-pkg`;
3. run:

   ```sh
   auzix-pkg refresh
   auzix-pkg pull L3afpad
   ls -la /Work/Temp/auzix-pkg/archives
   ```

4. only after pull proof passes, test bounded install behavior.

## 2026-08-22 dpkg source reference

To stop slowly reinventing dpkg in nibbles, lab-build now has a local dpkg source
reference:

```text
/var/lib/auzix-build/dpkg-reference/dpkg-source-tree
```

Fetched on `lab-ai-worker` with `apt-get source dpkg`. Use this side by side
with `scripts/build-auzix-package-tools-package.sh` when implementing package
state, dependency planning, archive ownership, conffile/script semantics, and
transaction boundaries.

## auzix-pkg transaction semantics correction — 2026-08-22

Current finding: the package repository metadata is not missing dependency data. It is over-expanded: many packages carry a flattened/transitive dependency closure in .depends[], while auzix-pkg had been treating .depends[] like immediate dependencies and recursively resolving it again. This produced dependency-loop behavior, repeated pulls, and false runtime conclusions.

Live VMID135 proof after patching AuzixPackageTools:

- Repo config: http://192.168.1.10/auzix/repo
- Repo index endpoint returns 200 OK; repo directory itself returns 403 because nginx directory listing is disabled.
- L3afpad plan now produces a finite transaction from current flattened .depends[] + target: 144 packages.
- Glances plan now produces a finite transaction from current flattened .depends[] + target: 280 packages, including Python3/Python313 components.
- Prior Glances partial install proved package-manager state failure: Glances installed without Python because resolver incorrectly reduced the closure to Glances + InitSystemHelpers. The wrapper then failed with /usr/bin/python3 missing.

Patch direction in scripts/build-auzix-package-tools-package.sh:

- Added update PACKAGE as an install alias for current repo rescue semantics.
- Added install-one PACKAGE as an explicit no-dependency install primitive.
- resolve_plan_json now treats current .depends[] as the already-resolved ordered dependency stack, appends the requested package, dedupes while preserving order, and subtracts installed/provided base state.
- /Programs/* only counts as provided if /Programs/<Name>/current exists. Stray directories are no longer enough to satisfy a dependency.

Required package-contract cleanup:

- Future repo metadata should split immediate dependencies from generated closure: depends[] for direct/immediate deps, resolved_depends[] or dependency_closure[] for flattened transaction output.
- auzix-pkg should consume a finite transaction artifact for pull/install/update, not recursively inspect package metadata during install.
- The base ISO/root must bootstrap installed/provided state for packages already included in the base, especially protected substrate libraries, so leaf installs do not try to mutate glibc/zlib/X/E/GTK substrate.

## 2026-08-22 late-night regression guard: do not replace known-good with strict until boot-proven

Operator rebooted VMID135 successfully from the working small-moon/current-live lineage. Treat that VM/ISO behavior as the demo anchor.

Rejected strict artifacts from the no-alias experiment:

- `auzix-strict-links-first-20260822T232214Z.iso`
- `auzix-strict-init-first-20260822T233712Z.iso`
- `auzix-strict-init-ssh-first-20260822T234219Z.iso`

Why rejected: the strict/no-top-level-alias lane removed `/bin`, `/usr`, `/lib`, `/lib64`, `/etc`, `/var`, `/tmp`, `/home`, `/root`, etc. while many generated AUZiX boot/display/service scripts still used `#!/System/Compatibility/bin/sh`. The Aug 16/17 working ISOs had compatibility aliases, so those shebangs were valid in that contract. Strict mode changed the boot contract without converting every boot-critical generated shell payload.

Observed failure evidence on ESXi serial for `auzix-strict-init-ssh-first-20260822T234219Z.iso`:

- DHCP reached `10.20.0.113/24`.
- `StartSequence` reached service start and GUI handoff.
- `sshd` process did not bind TCP/22.
- `/Services/ssh/run` had been fixed, but `/Programs/OpenSSH/host/Commands/sshd` was still a shell wrapper using `/System/Compatibility/bin/sh`.

Policy from this point forward:

1. The demo/live installer lane keeps the proven small-moon compatibility contract until its replacement has booted and passed SSH/X/E smoke on real VM targets.
2. Strict/no-alias is a separate experimental lane, not the default demo lane.
3. No ISO becomes current merely because it passed static archive/metadata checks. Promotion requires at minimum:
   - serial reaches DHCP;
   - `ssh tcp/22 listening` or service log tail explains failure;
   - X starts;
   - E reaches the desktop;
   - Midori CA smoke succeeds;
   - terminal launcher opens and accepts input.
4. If a strict artifact fails these gates, do not patch the live VM forward. Compare against the known-good ISO root and fix the generator/pipeline.


## ISO compare RCA — good VMID135/small-moon vs bad strict-init-ssh

Compared on lab-build under `/var/lib/auzix-build/iso-compare-20260822`:

- GOOD: `auzix-small-moon-ca-small-moon-ca-20260822T163447Z.iso`
- BAD: `auzix-strict-init-ssh-first-20260822T234219Z.iso`

Findings:

1. The good and bad `System/Boot/StartSequence` are nearly the same size and structure (`859` vs `861` lines). The bad ISO did not lose the whole init sequence; it reached DHCP/service/display handoff.
2. The visible boot-policy delta is GRUB: bad adds `auzix.links=strict`, good does not.
3. The top-level root delta is expected from that policy: good has compatibility aliases (`/bin`, `/usr`, `/lib`, `/lib64`, `/etc`, etc.); bad strict root omits them.
4. The actual regression vector is the access package command layout:
   - GOOD OpenSSH/Bash command paths are real ELF binaries:
     - `/Programs/OpenSSH/host/Commands/sshd` -> ELF, interpreter `/lib64/ld-linux-x86-64.so.2`
     - `/Programs/Bash/5.2-host/Commands/bash` -> ELF
   - BAD OpenSSH/Bash command paths are shell wrappers:
     - `/Programs/OpenSSH/host/Commands/sshd` -> `#!/System/Compatibility/bin/sh`
     - `/Programs/OpenSSH/host/Commands/ssh` -> `#!/System/Compatibility/bin/sh`
     - `/Programs/OpenSSH/host/Commands/ssh-keygen` -> `#!/System/Compatibility/bin/sh`
     - `/Programs/Bash/5.2-host/Commands/bash` -> `#!/System/Compatibility/bin/sh`
5. Therefore the failure was not "AUZiX cannot boot strict" and not "we need /usr forever". It was a package-builder regression: boot-critical commands were replaced with shell wrappers while strict mode removed the compatibility shell those wrappers require.

Narrow repair:

- Keep the known-good init/display/service sequence.
- Undo the access-package wrapper replacement for boot-critical commands.
- If strict mode needs AUZiX loader paths, patch the ELF binary in place at the public command path (`patchelf target`), do not move it to `.real` plus a shell wrapper.
- Add an ISO gate that rejects public boot-critical command paths if they are shell wrappers:
  - `/Programs/OpenSSH/host/Commands/sshd`
  - `/Programs/OpenSSH/host/Commands/ssh`
  - `/Programs/OpenSSH/host/Commands/ssh-keygen`
  - `/Programs/Bash/5.2-host/Commands/bash`

Do not promote another strict ISO over the VMID135/small-moon anchor until serial proves DHCP, SSH listen, X handoff, and E desktop.

## ISO init-script shakedown correction — 2026-08-22

Follow-up full root sweep corrected the RCA scope. The access-package wrapper
regression is real, but it is not the only strict-ISO mismatch.

Good small-moon/current-live contract:

- `initramfs/init`: `#!/System/Compatibility/bin/sh`
- live `/init`: `#!/System/Compatibility/bin/sh`
- `System/Boot/StartSequence`: `#!/System/Compatibility/bin/sh`
- `System/Boot`, `System/Tools`, and `Services` contain 29 scripts using
  `#!/System/Compatibility/bin/sh`.
- root has compatibility aliases:
  `/bin`, `/sbin`, `/usr`, `/lib`, `/lib64`, `/etc`, `/var`, `/tmp`, `/home`,
  `/root`, `/opt`.
- boot-critical access commands are real ELF files at their public paths.

Bad strict-init-ssh contract:

- `initramfs/init`: `#!/Programs/BusyBox/1.36.1/Commands/busybox sh`
- live `/init`: `#!/Programs/BusyBox/1.36.1/Commands/busybox sh`
- `System/Boot/StartSequence`: still `#!/System/Compatibility/bin/sh`
- `System/Boot`, `System/Tools`, and `Services` still contain 28 scripts using
  `#!/System/Compatibility/bin/sh`.
- root intentionally has no top-level compatibility aliases.
- boot-critical OpenSSH/Bash command paths were also changed from ELF files into
  shell wrappers using `/System/Compatibility/bin/sh`.

Conclusion: strict/no-alias mode was promoted before the whole live boot contract
was converted. The narrow access-package ELF fix is necessary, but not sufficient
for a strict ISO. Either keep the good compatibility contract for the demo/live
lane, or convert and gate every init/service/tool script plus command wrapper as
one explicit strict-lane migration.

## QEMU serial/desktop smoke harness — 2026-08-22

Added `scripts/smoke-auzix-iso-qemu.sh` as the fast lab-build runtime gate.
Default behavior is serial/headless with a 120 second ceiling. A good ISO should
reach `StartSequence`, DHCP, service start, SSH tcp/22 listening, and optionally
X/display handoff in roughly one to two minutes.

Known proof:

- `auzix-small-moon-ca-small-moon-ca-20260822T163447Z.iso` passed QEMU serial
  smoke with DHCP, SSH listening, and display handoff.
- `auzix-strict-init-ssh-first-20260822T234219Z.iso` failed QEMU serial smoke
  because SSH did not reach tcp/22 listening; serial also showed repeated
  `Invalid ELF header magic` and the `sshd.real` loader wrapper process.

The same harness can become an interactive desktop wind tunnel:

```sh
AUZIX_QEMU_SMOKE_TIMEOUT=900 \
AUZIX_QEMU_DISPLAY=vnc \
AUZIX_QEMU_VNC_DISPLAY=7 \
AUZIX_QEMU_REQUIRE_DISPLAY_HANDOFF=1 \
scripts/smoke-auzix-iso-qemu.sh /var/lib/auzix-build/published/<iso>
```

VNC display `:7` listens on TCP `5907`. SPICE mode is also available:

```sh
AUZIX_QEMU_SMOKE_TIMEOUT=900 \
AUZIX_QEMU_DISPLAY=spice \
AUZIX_QEMU_SPICE_PORT=5930 \
AUZIX_QEMU_VIDEO_DEVICE=qxl-vga \
scripts/smoke-auzix-iso-qemu.sh /var/lib/auzix-build/published/<iso>
```

Use this before ESXi/PVE promotion so browser console, VMRC, and noVNC quirks do
not masquerade as AUZiX boot failures.

## Strict live scope recenter — 2026-08-23

Operator correction: OpenSSH is not part of the strict live/root proof.  It may
become a `/Services/ssh` package later, but it must not be treated as a required
boot/display dependency for the small-moon ISO gate.  The immediate live-media
contract is:

- static BusyBox init/rescue primitives;
- Bash only where explicitly required by the current scripts;
- DHCP/DNS/CA;
- Xorg, LightDM or direct X handoff as selected by the lane;
- Enlightenment with packaged user defaults;
- Midori and the AUZiX installer surface.

Do not debug OpenSSH, host keys, or tcp/22 readiness while proving this lane.
That was one of the drift loops that made the image bigger and more fragile.
When OpenSSH returns, it should return as a deliberately jailed `/Services/ssh`
workload, not as base init furniture: separate service root/config/state/logs,
narrow runtime mounts, and explicit activation by package/service policy.  The
LAN lab can survive on BusyBox rescue primitives until that service package is
designed cleanly.

r8/r9 lesson:

- `normalize-auzix-elf-runtime.sh` originally scanned `/Programs` and
  `/System/Tools`, but not `/System/Compatibility`.  Xorg lives under
  `/System/Compatibility/usr/lib/xorg`, so its ELF interpreter escaped
  normalization and stayed `/lib64/ld-linux-x86-64.so.2`.
- `audit-auzix-strict-root.sh` must scan the same roots as the normalizer and
  fail strict builds on executable ELF interpreters pointing at top-level legacy
  paths.
- `build-auzix-strict-all.sh` must never mutate/package the staged root after
  the final normalize step.  r8 normalized successfully, then rebuilt
  e2fsprogs into the staged root and segfaulted.  Correct order is:

  1. scaffold root;
  2. install/package all payloads and package lifecycle state;
  3. add live boot/display tools;
  4. normalize once;
  5. build repo metadata;
  6. strict audit;
  7. assemble ISO;
  8. QEMU smoke.

Short version for future Codex: build artifacts first, normalize/audit last,
then stop touching the rootfs.  If a late package is needed, move it earlier in
the stage list; do not add a second mutation after normalization.
