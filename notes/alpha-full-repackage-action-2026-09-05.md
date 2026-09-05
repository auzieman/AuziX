# AX-012 / task65 — expand to retained release universe

User requests all roughly 400–500 packages, not only the pilot. Read-only R730
inventory finds 545 records in R10's retained index, and every archive filename
exists across its selected inputs and the three retained spools. Use exactly
these 545 records, not new intake or compilation. Preserve R10's record versions,
hashes and dependency/provider mappings; select all names in a new profile.

Prepare a separate input copy by matching each original SHA256 against retained
archives; fail before conversion on absent/mismatched content. Keep input-origin
manifest and source commit. Reuse the proven eight-worker conversion path into
a new commit-addressed output. The existing successful 117-package candidate,
R10 and VM145 remain untouched. No directory swaps or deletion.

Acceptance for this run is complete per-package accounting; unresolved donor
effects fail their packages, continue the others and fail aggregate validation.
No suppression, public promotion or image deployment. Observe initial workers,
hand off tail for a long run. Final repository assembly/indexing remains a
separate serial step after reviewing the full conversion result.
