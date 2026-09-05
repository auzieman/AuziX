AX-001 / AX-003 / AX-007 / AX-012 — September5 — R9 launch preparation

Before changes: bounded intake71162696 completed; pin its three archives and
select them in the release profile. Explicitly request repaired Passwd too:
its mapping existed but packages[] omitted it. TerminologyData already selected.
Support producer enumeration is seven packages, matching its assertion;
initial manual count of eight was incorrect. Leave that working code alone.
Use port18444 for the fresh apk-alpha lane, preserving review repository18443.

Acceptance before launch: all reviewed records requested, remote hashes verify,
ALSA payload compared with VM145, unit/shell checks. Then BKC fresh R9 build;
keep VM145 and completed R8 immutable. Rollback via scoped commits and retained
previous artifacts. Build failure becomes a ticket comment, not a silent retry.
