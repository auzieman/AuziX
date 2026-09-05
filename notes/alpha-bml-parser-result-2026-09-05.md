# AX-012 / task65 — parser BML measured result

Source dcbcdda180fbab93fc258a517d4ea448d3611e2f.
BKC e23d352f-3aaf-4f52-992d-48936ab15836 ended 21:46:31 UTC with aggregate
review failure, not a crash. Output:
`/var/lib/auzix-build/package-proof/AX-012-dcbcdda180fb`.

74 tests pass both locally and inside the existing Trixie builder (network
disabled, read-only source/root, isolated tmpfs). Image identity retained in
trixie-builder-image.txt; output in trixie-tests.log.

36 previously held packages rerun, eight workers. XdgUserDirs newly verified;
35 still held. Findings reduced 186 → 181: four version-less rm_conffile
findings resolved with an executable backup-preserving migration, plus XMLCore
shell-syntax regression removed. XMLCore still has catalog-trigger and local
path findings and is not claimed fixed. Other retained holds persist unchanged.

Before/after per-package comparison: comparison.json. Original 509 successful
outputs and the full baseline were untouched, as were R10 and VM145. This gives
510 verified archive conversions across baseline plus retry, not a newly
assembled/installed 545-package release. No repository promotion or image build.

Learn: the two demonstrated parser defects were resolved without replacing
whole donor scripts. The remaining work is mostly the installation effects
reviewed in the two ten-package source notes; fixture success is not runtime
acceptance. Next bounded pass should address one shared activation mechanism
with explicit dependency ordering and real installation proof, not bypass the
remaining guards. AX-012 stays Blocked for candidate acceptance.
