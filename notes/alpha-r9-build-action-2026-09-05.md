AX-001 / AX-003 / AX-007 / AX-012 — September 5 — fresh R9 build action

Before action: reconcile prior accepted source fixes into a fresh pipeline run,
not mutation of completed R8. VM145 is protected reference, current .58.
Existing notes identify EnlightenmentData as xsessions owner; retain donor
payload rather than invent a session launcher. Three remaining donor identities
will use existing Trixie binary intake in a bounded profile, reusing the r2
dependency spool. New intake ID: 20260905-alpha-e-closure-r1.

Also pin repaired TerminologyData and Passwd archives from package-proof spools;
otherwise a fresh build would select their older primary-spool copies. Current
native producers regenerate terminal integration (including terminfo fix
ba246ae) and Sudo (/Libraries fix6c88926). Preserve HDD startup guards and
reference-overlay logic. No startup rewrite or live VM replacement.

Execution: existing BKC container pipeline, bounded intake mode followed by a
fresh apk-alpha candidate20260905-alpha-bkc-r9 once inputs verify. Reserve
repository port18444 so the interactive netinstall repository18443 survives.
Rollback: retain completed R8 and original VM145 disk; new run directories are
isolated evidence. Acceptance: intake receipts, selected-input SHA checks,
actual package transaction and runtime tests, then HDD/boot gates separately.
No public promotion. Any failure gets a dated ticket comment and Blocked state.
