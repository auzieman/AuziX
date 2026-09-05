AX-001 — September 5, 2026 — BML retained-input reconciliation

Before implementation: resume task54 in Work in progress. Read-only comparison
confirmed VM145 still selects Enlightenment0.27.1-1 and has /dev/tty and
/dev/pts/ptmx mode0666. Preserve that reference; no startup rewrite.

Twelve of the fifteen dependencies rejected by the isolated APK test have
retained archive records. Eight are in factory-delta/r28-adjacent-clean2/spool:
Libbluetooth3, Libexif12, Libasyncns0, Libflac14, Libogg0, Libmp3lame0,
Libmpg1230t64 and Libopus0. Four are in the selected runtime-closure-r2 spool:
Libpulse0, Libsndfile1, Libvorbis0a and Libvorbisenc2.

Build: pin these existing records in the release profile, checking archive bytes
against metadata SHA256; do not compile. Measure: selection tests and remote
hash verification. Learn: absent from the candidate is not absent from builds.
Remaining unresolved identities: EnlightenmentData, Libasound2t64, Libasound2Data.
Do not suppress their dependencies or declare the image ready.

Rollback: revert only profile additions. No completed repository, image or VM
changes. Package emission/install and fresh boot are still pending acceptance.
