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
