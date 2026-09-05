AX-001 — September 5, 2026 — retained-input reconciliation result

Build: release profile now explicitly selects and SHA-pins twelve retained
archives (eight r28-adjacent-clean2, four runtime-closure-r2). No compilation,
live patch or completed repository modification.

Measure: all twelve remote archive SHA256 checks passed. All64 local tests
passed and git diff --check passed. Source selection is corrected; these
archives have NOT yet been emitted/installed in a new candidate.

Learn: twelve rejected dependency identities were already built but omitted
from release selection. Three remain unresolved: EnlightenmentData,
Libasound2t64 and Libasound2Data. Searches of retained factory entry filenames
and donor identity fields did not locate those three; this does not prove
their binaries or donor packages are absent elsewhere.

Task54 remains Blocked on completing that closure and passing actual APK
installation. Next bounded work: resolve those three against existing donor
inputs, then emit/install the closure. Preserve the working reference VM.
