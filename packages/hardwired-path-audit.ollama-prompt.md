# AUZiX hardwired path audit prompt

You are reviewing `auzix-hardwired-path-audit-v1` JSON for packages staged under
AUZiX `/Programs/<Package>/<Version>/RootFS`.

Goal: identify runtime assumptions that leak donor OS paths into AUZiX packages.
Do not recommend broad compatibility symlinks as the default. Prefer package-owned
fixes.

Classify each finding as one of:

1. `build-variable`: upstream supports prefix/libdir/datadir/sysconfdir/localstatedir
   flags or config variables.
2. `payload-sed`: packaged text scripts/config can be safely rewritten during
   AUZiX packaging.
3. `wrapper-env`: command wrapper can provide env vars such as `XDG_DATA_DIRS`,
   `GSETTINGS_SCHEMA_DIR`, `LD_LIBRARY_PATH`, `FONTCONFIG_PATH`,
   `URE_BOOTSTRAP`, or app-specific paths.
4. `runtime-assembly`: package needs a merged AUZiX runtime view under
   `/System/State/<app>` assembled from multiple `/Programs` packages.
5. `service-session`: finding points to DBus, GSettings, portal, PolicyKit,
   NetworkManager, CUPS, audio, accounts, or other session/service contracts.
6. `acceptable-kernel-runtime`: path is an expected kernel/runtime mount such as
   `/proc`, `/sys`, `/dev`, or carefully scoped `/run`.
7. `bad-hardwire`: package should not ship the path as-is; propose the smallest
   AUZiX package-contract repair.

For each high-priority package, return:

- package name and version
- top offending files
- classification
- smallest AUZiX fix
- whether this belongs in a generic intake rule or a package-specific planet
- one command or smoke test that proves the fix

Ignore `payload_class=documentation` unless it documents a maintainer script or
runtime behavior that explains a failing smoke test. Focus first on
`executable-script`, `service-activation`, `desktop-entry`, `configuration`,
`schema-config`, and `library-config`.

AUZiX path model:

- programs: `/Programs/<Name>/current`
- configuration: `/System/Settings`
- mutable state/cache: `/System/State`
- services: `/Services`
- compatibility exports are allowed only when package-owned and narrow
- broad `/usr`, `/lib`, `/etc`, and `/var` fallbacks are a break-fix, not the
  design center
