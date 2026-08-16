# AUZiX build-root preservation note

The lab-build Docker source-contract run for GNOME Control Center is turning
`out/auzix-strict/AuzixRoot` into a valuable SDK/workstation package root.
Do not delete or recreate this tree between package builds unless explicitly
requested.

Current lessons folded into the package loop:

- Debian source Build-Depends are AUZiX package candidates, but virtual recipe
  markers such as `debhelper-compat`, `dh-sequence-*`, and GIR virtual aliases
  should be recorded/skipped, not treated as missing runtime libraries.
- Command-bearing packages must expose wrappers plus loader/library validation
  metadata early, before GUI/manual tests.
- AUZiX absolute `/Programs/.../current` symlinks are correct inside AUZiX;
  host-side audits must resolve them through the AUZIX_ROOT prefix.
- Build-tier packages such as dpkg-dev, gtk-doc-tools, gcc/cpp/binutils, and
  gobject-introspection should be tagged separately from workstation runtime
  packages.
- FPM should be used as the package emitter/stager once the source recipe,
  dependency queue, and AUZiX path knobs are known.
