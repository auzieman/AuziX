# AX-012 / task65 — eight-worker candidate result

Source commit: `1fe13b87b4ac3cbb49f399ea946a990d45ec9f53`.
BKC run: `5cfee208-a117-4620-b0df-b5595383de5d`, complete at
2026-09-05 21:15:59 UTC. Packaging stage active at 21:14:23 UTC (~96 seconds).

Result: 117/117 conversion/archive verification successful; 97 adapted, 20
without detected lifecycle scripts, zero review holds. Eight workers. No
compilation. Local suite: 71 tests passed, including real donor fixtures,
cleanup replay and ownership boundaries, unknown donor rejection, concurrent
isolated staging, aggregate results and existing-output refusal.

Candidate R730 directory:
`/var/lib/auzix-build/package-proof/AX-012-1fe13b87b4ac`

Proof: `repository/conversion-proof.json`, SHA256
`abb950a8a8cfed021e2062cd39fe69ce7c9674a049e00f99460c4d0ae673bba7`.
Log: `proof.log`; individual receipts: `repository/records`; APKs:
`repository/x86_64`. Candidate uses about 1.3 GiB; disk has ~77 GiB free.

Spot checks: both Python lifecycle receipts are ready and preserve donor
objects; minimal retains postinstall/postremove plus the adapted prerm.
Extracted stdlib Package/Scripts/before-remove from the adapted archive:
versioned /Programs/Libpython313Stdlib/3.13.5-2+deb13u4/RootFS scope, no dpkg
query, no adjacent package traversal, dist-packages pruned. Local replay tests
prove source/neighbor/symlink-target bytecode stays intact. APK archive integrity
checks passed for both, plus all remaining selected packages including Midori.

Preserved: R10 image/repository, VM145 reference disk, previous proof outputs.
No directory swap, shared repository index update, signing/publication, fresh
container install or HDD build/deployment occurred. Existing conversion output
is now rejected instead of recursively removed. No cleanup/deletion performed.

Task65 remains Validating, not Accepted: next is candidate repository assembly
and fresh installation/replay against the existing release chain, then its
runtime and graphical acceptance. The 117 selected archives are not the whole
559-package installed distribution; untouched base packages retain their prior
artifacts. Other ticket-specific image/provisioning gaps are still open.
