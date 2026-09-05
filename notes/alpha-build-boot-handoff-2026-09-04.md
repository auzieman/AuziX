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
