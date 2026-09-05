# AX-012 / task65 — measured parser BML

Before changes: full run holds 36/545; reviewed sources identify optional
rm_conffile version syntax and nested multiline purge parsing defects.
Use those exact retained fixtures. No service/security configuration rewrite.

Build: recognize version-less rm_conffile declarations under mapped Settings;
before install, move any obsolete regular file to a non-clobbering .auzix-bak
backup. Preserve content regardless of modification; refuse symlinks/conflicts.
Other lifecycle phases do not repeat the migration. Versioned migrations keep
their existing behavior in this bounded pass (their recorded-only handling
remains a separate review item). Fix purge block nesting for multiline if;
keep unknown/ambiguous constructs unchanged for syntax/review checks.

Measure: fixture tests for preserved files, replay, backup collision and symlink
rejection, plus XML donor versus rendered syntax. Run regression tests through
the existing auzix/trixie-builder image via committed BKC script, then rerun only
the 36 held inputs with eight workers. Preserve all 509 successful artifacts and
the full original result. Capture before/after findings and exit status even
when some reviews remain; no aggregate acceptance while holds exist.

Rollback: retained artifacts and source revert. No live repairs, indexing,
publication or VM deployment. This action authorizes only a new isolated
candidate directory. Trixie builder identity will be recorded with run output.
