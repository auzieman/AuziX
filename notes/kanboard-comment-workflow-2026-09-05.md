AX-012 — September 5, 2026 — ticket update workflow correction

Operator correction: progress belongs in comments, with attachments where
relevant. Earlier synchronization replaced descriptions with accumulating
ledger text; that was the wrong behavior.

The sync helper now preserves existing task descriptions and titles. Explicit
Markdown comment updates are content-deduplicated and read back through the API.
Scope and acceptance criteria belong in descriptions; results, decisions,
commits and pipeline runs belong in dated comments. Relevant screenshots,
sanitized log excerpts and receipts should be attached, not just mentioned by
an inaccessible host path.

Existing comments, attachments and historical description text are preserved.
This change does not move cards or mutate images. Attachment upload and a
deliberate cleanup of accumulated description history remain separate work;
no attachment migration is claimed by this correction.
