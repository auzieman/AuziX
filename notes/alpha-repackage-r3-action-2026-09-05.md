# AX-012 / task65 — next scoped candidate

Before implementation: prior pilot converted 115/117; Python minimal/stdlib
prerm hooks retain dpkg queries and shared legacy cleanup paths. VM145 Python
imports work, but both library lifecycle directories are empty. Preserve its
runtime layout; adapt only the two inspected donor removal hooks.

Capture exact retained donor fixtures. Recognize only reviewed script hashes
and matching package/stage; render cleanup limited to that version's owned
RootFS, deleting bytecode caches, not source, adjacent packages or dist-packages.
Unknown script revisions must remain review failures. Test removal, replay,
ownership boundaries and changed donor rejection.

R730 has 40 CPUs, ~29 GiB available memory, but only 78 GiB disk free. Use eight
packaging workers initially, unique package temporary roots and unique output
paths. Preserve input/output directories: reject existing conversion output,
never delete it. Aggregate results once workers finish; no concurrent indexing.
Run the same 117 inputs using the existing committed BKC proof lane into a new
commit-addressed directory. No compilation, no R10/VM145 changes, no directory
swap or public promotion before installation/boot review. Rollback: use retained
R10 and prior artifacts; revert only this commit if necessary.
