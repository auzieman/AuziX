# AX-012 — scoped repackaging run, September 5

Changes committed: AuziX `28cad95`, `8244027`, `95a2b34`; BKC `952455c`.
68 local unit tests passed, including donor-script discovery without receipt
annotations, preservation by automatic library adapters, unresolved-effect
failure preservation, and donor provenance retention.

BKC runtime sync: `1903f598-fdcf-449c-8a2c-49dad13ea983` loaded the new lane.
First proof `bf59fcdb-70c5-48c0-acc6-93a429f2991d` failed before conversion
because the script assumed a Git checkout; recorded and corrected to consume
BKC's immutable source reference. Original output preserved.

Retry: `3d706109-5aad-404a-94bb-39b622b30fac`, source
`95a2b3497a3dc128102f42ac157e9f05faf93363`.
R730 output: `/var/lib/auzix-build/package-proof/AX-012-95a2b3497a3d`.
Pipeline consumes R10's existing selected profile (117 packages), archive inputs,
APK tool and factory image. No compile, image deployment, public repository
refresh or modification of R10. Source and factory identity retained in output.

Startup evidence: selected-profile preflight passed; conversion reached Midori
(53/117), with preceding Office Writer archive verification successful.
Libecore1 adapted archive retains original control files and donor provenance;
its lifecycle receipt explicitly maps the donor ldconfig trigger to AuziX
library publication and lists four owned/public outputs. This is not evidence
of a desktop launch. Direct APK tar inspection failed and APK manifest required
a database; neither diagnostic is claimed as content validation. Pipeline APK
integrity verification and adapted archive inspection are the actual evidence.

AX-012/task65 moved WIP → Blocked on first proof failure → Validating for retry;
API readbacks verified. All other ticket acceptance remains open. In particular,
explicit replacement adapters still need effect-by-effect review, and package
install/replay, fresh-image reboot and human desktop checks are not covered by
this conversion-only pass.

Monitor:
```sh
ssh r730-ai-01 'tail -F /var/lib/auzix-build/package-proof/AX-012-95a2b3497a3d/proof.log'
```

Closing evidence must use `repository/conversion-proof.json` and BKC run status,
not the last package line. Any review outcome keeps the candidate out of image
publication and needs an exact finding comment plus Blocked transition.
