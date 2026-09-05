# AX-012 — isolated D-Bus source walk

Operator requests one failed package traced from Debian source. Target dbus
1.16.2-2, retained full-run input. Prepared BKC-only side audit: fetch .dsc and
its checksummed source components into new output, unpack using dpkg-source in
the existing Trixie builder, compare source rules/scripts with retained binary
controls and payload, and rerun current normalization on that retained input.
No compile, live install, package publication, current image modification or
factory behavior change. Source signature status must not be overstated.

Retain download hashes, extraction output, original/generated script diff,
normalizer findings and payload helper mode. Source versus binary intake is
explicit: this audit does not pretend the binary intake executes debian/rules.
Rollback: no promotion; keep isolated output. Fail on missing/mismatched inputs.
