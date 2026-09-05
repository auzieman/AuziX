# Alpha candidate: package inputs to image and boot

VM145 remains the protected workstation reference. No public promotion.

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
