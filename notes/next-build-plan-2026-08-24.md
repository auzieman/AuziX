# Next AUZiX build plan — pinned 2026-08-24

The next AUZiX build does not begin by compiling or recursively importing
packages. It begins with one metadata-only discovery run governed by
`packages/trixie-base-discovery.contract.json`.

Debian Trixie is one coherent upstream base. AUZiX selects one immutable Trixie
snapshot, preserves Debian's source packages, patches, build rules, dependency
decisions, and lifecycle intent, then translates the result into the AUZiX
filesystem and package model.

The discovery run must report the complete finite source/build/runtime closure,
one version/provider for every component, strongly connected build groups, and
the substrate-first order before compilation begins. If Python, Enlightenment,
or any other package implies a different protected libc or base generation,
the proposed lock is invalid. A leaf package may never pull a new base beneath
the rest of the system.

After human review, the lock is committed and tagged. Only then may BKC run the
base build. Discovering a new dependency during that build is a hard failure
and returns the work to discovery; it is not permission to fetch recursively.

The first session ends at the reviewed lock. No package build or image build is
part of that session.
