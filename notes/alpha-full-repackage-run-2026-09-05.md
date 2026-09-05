# AX-012 / task65 — full retained archive run

Source `376e00389e3257fb4bbc315af66c9e583091b9c3`; 72 local tests passed.
BKC `47c4d380-2c51-4af3-86a2-3f9871308159`, running at handoff.
R730 output `/var/lib/auzix-build/package-proof/AX-012-376e00389e32`.
Input checksum selection completed; conversion preflight passed for 545 records.
Eight workers observed processing packages beyond the initial pilot.

Early review holds include AcpiSupportBase, Apparmor, Appstream, Apt, Bash,
Bubblewrap, Bluez, DBus, DBusSystemBusCommon, DebianArchiveKeyring, Flatpak,
Fprintd, Gzip and LibcBin. These are unresolved lifecycle findings, not evidence
of missing compiled software. Full findings are retained in repository/review
and repository/records. Workers continue through remaining packages. Do not
suppress findings or restart the entire wave to fix individual exceptions.

AX-012 is Blocked for candidate acceptance pending donor-effect review; this
does not stop the running collection/conversion job. Next: read the completed
conversion-proof.json and group the exact failures before scoped remediation.
No public index, signing, image build or promotion performed. R10, successful
117-package candidate and VM145 remain intact.

Monitor:
```sh
ssh r730-ai-01 'tail -F /var/lib/auzix-build/package-proof/AX-012-376e00389e32/proof.log'
```
