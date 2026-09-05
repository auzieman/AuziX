# Alpha candidate: package inputs to image and boot

Current operator direction (September 5): VM143/144/145 are reusable test slots;
target VM145, preserving its previous disk for rollback. No public promotion.

Runtime intake run `a300b9b1-5a9a-44ce-9570-fe565fb80abc` completed.
Its spool retains 485 identities; this is not a 485-package install request.
The candidate combines the existing 62-package repaired profile with the
20 selected runtime identities. Primary repaired archives win duplicate
identities; unselected intake records supply dependency names only. The
existing factory verifies selected archive hashes before conversion.

Installer changes stage the existing generated installed-root contract in
the installer package, avoiding a source checkout/compiler at install time.
The existing GRUB producer emits the pinned R730 Trixie tools as an APK.
These changes still require a real install proof; staging is not that proof.

Candidate HTTPS repository uses loopback port 18443 and a run-specific
container removed on exit. The healthy `auzix-one-nginx` is not replaced.
This lab-only repository address is not a public release configuration.

Local checks: 60 unit tests, 71 package manifests, shell syntax and diff
whitespace checks pass. Next boundaries: APK assembly/container tests, HDD
root validation, separate VM boot, desktop/user tests, blank-disk install.
Do not infer any later boundary from an earlier passing receipt.

## Actual package boundary

Run `c82b6d0d-165c-42a1-893c-ea63744be74e` stopped with 81 passing
packages and Kmod donor-script review. The next attempt
`a6b021cc-eecf-4f39-ae44-21695777da74` exposed a mistaken declaration of
the postinst-generated modules file as an archived conffile.
`d9609e6` corrects that declaration. A controlled one-package diagnostic
on R730 passed the actual retained Kmod archive through the factory:
`/var/lib/auzix-build/package-proof/d9609e6-kmod/repository/conversion-proof.json`.
This direct diagnostic is reconciled as `scripts/prove-auzix-alpha-archive.sh`
and recorded in the next BKC run notes, not an alternate build workflow.

Candidate run `9b3540bd-d270-4e0c-9feb-c0e562d4c7b4` uses source
`d9609e671ac10f3ebbfea09eed53cb014f837fd0`, work ID
`20260904-alpha-bkc-r4`. Installer template staging and GRUB APK emission
also passed their focused R730 checks under `/var/lib/auzix-build/package-proof/`.
These are payload proofs, not disk-install proofs.

PVE VM146 was unused at inspection. VM145 remains untouched. PVE `local`
file storage had only about 700 MiB available; do not copy an 8 GiB raw image
there. Its `local-lvm` disk storage has ample space. Verify availability again
before deployment. Public release remains blocked on boot/install validation
and removal of lab-only repository configuration and authorized keys.

## r4 workstation transaction boundary

All 82 archive conversions passed (71 lifecycle, 11 static). Zero, Nginx and
netinstall built; netinstall's checks passed. Pre-HDD base installation stopped
because Sudo attempted to own the runtime's loader path. `e47902b` removes
core ABI files from the sudo producer. The corrected APK subsequently installed
with BaseLayout, BusyBox, ApkTools and RuntimeGlibc without an overwrite error.

The APK index identified six collapsed provider spellings and ten omitted
adjacent runtimes. Trixie APT simulation of the bounded runtime selection with
an empty status file and `--no-install-recommends` identified eight further
GI/typelib/font runtime dependencies. All 18 are explicit in the profile;
the existing base/DBus/service compatibility exception is not replaced by
blindly importing Debian's systemd, dpkg and base-files scaffolding.

The follow-up intake reuses the completed 485-entry spool. Before any further
container construction, the builder now requires an APK solver pass for the
full requested groups. A passing per-package conversion is not a solver pass.

## r6 actual installation and r7 native repair

Runtime intake follow-up `27e6c152-7df6-4ac5-84da-96074d66fcd2` passed;
499 spool entries, 14 newly ingested binaries, no source compilation.
r6 converted all 100 selected archives and indexed 595 packages without missing
provider warnings. The real APK solver selected 543 packages. Its empty database
must be initialized before simulation (`cb85f74`); simulation alone does not do it.

Consumer resume `424f771d-1a62-4c47-928c-36bc2326974b` installed through the
applications block but failed three packages: GRUB duplicated sudo's libpcre2
and libselinux; the imported core installer carried an EFL-owned frontend link;
Flatpak's hook attempted OSTree initialization without proc available.
`5ad6818` puts GRUB dependencies in its private Libraries with command wrappers,
leaves the frontend link to its owning package, and defers Flatpak remote setup
until runtime proc is available. It uses the actual package-owned CA bundle at
`/System/Settings/ssl/certs/ca-certificates.crt` and declares that dependency.

Focused R730 proof using r6 netinstall + APK-installed flatpak, ca-certificates,
gnupg and the corrected support script passed both boundaries: no-proc deferral,
then normal-proc `flatpak remotes` reported `flathub system`. An earlier smaller
proof without gnupg correctly failed its GPG engine; the workstation already
requests gnupg. No weakened TLS or signature checks were used.

r7 pipeline `a6fee89f-2da4-46f2-b49c-f7467ea2ed19`, source
`5ad6818875b03fe8e7cc47b5bd4314c3dc059eb7`, reuses the r6 archive outputs only
after checking factory sources, selected identities/dependencies and APK hashes.
Native packages are regenerated. Log:
`/var/lib/auzix-build/receipts/apk-alpha-20260904-alpha-bkc-r7.log`.
At kickoff there is still no new HDD or VM: do not mistake these proofs for boot
or installer validation. Existing VM145 and healthy service containers untouched.

### Connectivity interruption after kickoff

R730 (10.20.0.130) and BKC swarm manager (10.20.0.230) became unreachable
through ns1: SSH forwarding reports `No route to host`; ns1 itself is reachable,
with neighbor resolution INCOMPLETE/FAILED for those two hosts. PVE remains
reachable and confirms VM145 running and VM146 absent. r7's terminal status is
unknown, not passed. No HDD/boot trigger was sent. Commit b742173's notes push
failed due this interruption; implementation 5ad6818 and BKC 4e00b1d were already
pushed before the interruption. Resume by checking r7 and its existing log first,
not launching another run or replacing the known-good VM.

## September 5: bounded recovery in progress

R7 was marked interrupted after power-off. R8
`c0eb2688-f5c8-4116-842b-84860f56640d` reused the verified factory outputs and
installed 544 packages, then exposed a checksum call outside the target chroot.
Commit `39ffce3` fixes only those calls. Resume
`ae524ada-7649-40a6-8cb9-1f971ec83881` passed installation and no-op replay,
then stopped at the missing Terminology colorscheme publication.

The existing intake fix is `32e7aa2`, not new desktop logic. The selected old
TerminologyData archive contains Default.eet but lacks its compatibility links.
Re-intake of Trixie 1.14.0-1 on R730 with that existing script passed, producing
254 files and five compatibility links. Initial attempt lacked APT indexes;
running apt-get update in the disposable builder resolved that prerequisite.
No source compilation, X/E rewrites, or live VM changes were involved.
Corrected spool: `/var/lib/auzix-build/package-proof/terminology-r8/spool`.

Commit `a290e18` adds a bounded one-archive refresh that retains the old APK and
signed index, converts the corrected archive through the factory, and resigns
the candidate repository. BKC run `6b646a52-ea4f-45f1-9655-283124933a40` invokes
it and resumes R8 consumers. Its package conversion passed; image validation
remains pending. Prior evidence remains under R8 `repairs/TerminologyData`.

Commit `a282583` changes the boot helper to reuse slots 143–145 only when stopped,
allocate a new disk in a free SCSI slot, verify the streamed disk SHA256, then
change boot order. Existing disks stay attached for rollback; VM143/144 are not
targets for this run. PVE VM145 was stopped with scsi0=local-lvm:vm-145-disk-0.
The historical HDD helper deleted unused disks; do not invoke that deletion path.

The one-package APK install proof passed against R8 netinstall:
`/System/Compatibility/usr/share/terminology/colorschemes/Default.eet` is nonempty.
The first image resume nevertheless reused a cached old installed root: remote
repository changes were absent from Docker's cache inputs. `65ff83d` supplies the
signed index SHA256 as a build argument to both remote-APK consumer stages.
This is a consumer cache correction, not another package rebuild. BKC run
`c0555d38-6325-4d0d-a580-859d4a0cdf39` resumes with that correction; the package
transaction and replay again passed, final validation pending at this note.

That run passed the Terminology colorscheme check, then identified the absent
`/System/Tools/launch-auzix-terminal`. The launcher existed in the older host
Terminology producer, not the package-derived integration payload. `44dcdad`
stages that launcher in AuzixDesktopIntegration, using BusyBox/current and the
documented interactive shell contract. It does not alter X/E startup or libraries.
The package and old index are retained under `repairs/AuzixDesktopIntegration`.
BKC run `2ef083f8-f44a-4c30-8aee-c3c34dd1391b` refreshed that one native package
and resumed consumers. Producer baseline for this explicit repair is its source
snapshot `20260905-alpha-bkc-r8-resume-44dcdadf2b44-20260905T154907Z`, not the
original pre-repair snapshot. A later consumer resume must honor this recorded
baseline rather than silently comparing against a different package producer.

Implementation commits are pushed only to internal alpha branches. No public
publication, new HDD, or VM145 disk change has occurred as of this checkpoint.

## Account node and runtime-boundary proof

Terminal integration passed in the assembled image. The next stop was deluser's
absolute `/usr/sbin/userdel`: Passwd's payload/Commands existed, but the retained
archive omitted this compatibility link. Re-intake of the same Trixie
1:4.17.4-2 produced 332 files and 23 commands with the current publication logic.
Spool: `/var/lib/auzix-build/package-proof/passwd-r8/spool`; refreshed APK and
index rollback evidence: R8 `repairs/Passwd`.

Direct diagnostic image `auzix/diagnostic:r8-installed` was exported from the
already cached auzix-base stage; no factory rerun. Those diagnostics established
that Docker's /etc mount masks the image's directory alias. The entrypoint now
also publishes account configuration, sudoers and PAM aliases. `7944482` moves
final validation after the actual image ENV and entrypoint are installed.

The initial BKC account probe selected the old installed checksum with apk fix;
it now installs the exact corrected local APK. That revealed a distinct issue:
Shadow 4.17.4 intentionally opens account databases with O_NOFOLLOW, rejecting
the Docker shim's leaf symlink /etc/passwd. Upstream reference:
https://github.com/shadow-maint/shadow/blob/4.17.4/lib/commonio.c
Do not remove this security check or infer missing database contents.

`f89e478` exercises account writes inside /target before Docker's runtime /etc
shim; /etc there is a directory alias and account files are regular files in
/System/Settings. The final validator requires account_roundtrip=pass in the
transaction receipt. BKC run `248d8978-90e8-4ce1-b8b3-a3aea007d261` independently
passed this adduser/deluser roundtrip, then resumed image validation. Log suffix:
`apk-alpha-20260905-alpha-bkc-r8-resume-f89e4785f5d5.log` (plus `.account-proof`).
This is staged-root proof, not yet real-disk installation proof. Docker runtime
account writes through leaf symlinks remain a known limitation, not silently
declared fixed. Fontconfig emitted a missing-default-config warning; retain it
as a separate runtime observation for desktop verification.

## Netinstall runtime comparison, September 5

Sudo refresh run `f0fa0b97-6491-42b9-a2df-e70543b0c4d4` installed the new
APK but failed inside the cached staging chroot with a libc loader lookup error.
This does not establish an absent libc package or a failure in the running
image. Do not recompile libc based on this result. Sudo is not yet proven.

At the user's request, compare the actual netinstall runtime before further
package changes. `a04cbfb` aligns netinstall's environment and build validation
entrypoint with the installed-image contract and requests auzix-sudo. The BKC
`apk-alpha-netinstall` lane builds the existing Dockerfiles from an immutable
checkout and retains a uniquely named review container and loopback HTTPS
repository for interactive inspection. It does not promote an alpha, rebuild
pre-HDD, or change a VM disk. Existing netinstall proof containers are preserved.
Local checks: 62 unit tests passed; BKC wrapper shell syntax passed.

Release intent: validated zero/one/netinstall/pre-HDD packages and containers,
then two HDD outputs (netinstall and workstation), each requiring boot and disk
installation validation before publication through the existing pipelines.

Netinstall follow-up: `99dae33` delivers the existing Container/run keepalive
in zero and netinstall; first review built successfully but lacked that file.
BKC `b14e1186-154f-4c9c-8cf8-b8f15ea0f8be` retained the running container
`auzix-netinstall-review-99dae33621ab` and its dedicated repository. Runtime
validate-netinstall and root-invoked sudo passed (hostname resolution warning).
This is NOT yet a non-root sudo proof. The prior auzix-pre-hdd reference remains
untouched: libc there resolves through /Libraries/Packages/Libc6, not the absent
/System/Libraries/Runtime/glibc/libc.so.6 path. Do not confuse loader lookup
failure with a missing libc package. A startup TLS reset required only bounded
retry/resume of the same repository; certificate verification remains enabled.
