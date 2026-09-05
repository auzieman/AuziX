# AX-012/task65 — helper operation proof result

September 5, 2026 22:08 UTC. BKC b94d899d-a0bf-42c6-87f8-fad368dfd624
completed with source e509689d7d39d81dbd5cc22cc3692acf77ba9ede.
R730 output: /var/lib/auzix-build/package-proof/AX-012-source-e509689d7d39
Evidence: helper-permission-test.log; audit-summary.json retains the outstanding
normalization findings. No compilation or image changes.

Real filesystem component assertions passed inside the disposable Trixie builder:
missing account rejects without modifying payload; existing account permits
root:service-group 4754; replay retains exact ownership/mode; explicit override
preserves custom mode; unknown policy rejects; symlink target rejects.

Limits: this uses a harmless regular-file fixture and a test service account,
not an installed D-Bus APK. The caller supplies override disposition explicitly;
automatic discovery/translation of administrator override state is not implemented.
The permission script is not yet wired into the normalizer or emitted APK.
Therefore the failed-package count has NOT decreased. Do not promote this as
complete package repair. Task65 remains Blocked on lifecycle integration and
actual APK installation, service activation/reload and the other held packages.

Next bounded step: connect this operation to an effect-accounted D-Bus adapter,
including account-provider ordering and explicit override-state policy; adapt
the retained service/reload behavior without restarting D-Bus on upgrade. Then
repackage and exercise actual installation/replay in an AuziX validation root.
