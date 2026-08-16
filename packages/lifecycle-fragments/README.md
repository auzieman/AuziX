# AUZiX Lifecycle Fragment Collection

This directory is the checked-in home for reusable lifecycle knowledge that is
not yet baked into individual AUZiX packages.

Think of these files as the AUZiX equivalent of the relevant parts of Debian
maintainer scripts, triggers, service metadata, desktop integration, and runtime
setup logic — but split into small, stack-aware fragments instead of replaying a
full `dpkg-reconfigure` style sweep.

AUZiX package work should default to repackaging. A package is a payload archive
plus metadata; most desktop repair work is adding the missing expansion metadata
around an otherwise usable payload.

## Two tracks

### 1. Script fragment collection

Fragments in this area describe what an installed host should look like for a
stack such as the desktop session:

- DBus sockets, service files, and runtime dirs;
- Polkit policies and daemon state;
- LightDM, Xorg, PAM, and session handoff;
- EFL/Efreet/Enlightenment cache and menu state;
- PulseAudio or PipeWire session state;
- Flatpak helper, portal, Bubblewrap, and XDG integration.

These fragments feed:

```bash
auzix-pkg triage --stack desktop-session
auzix-pkg fix --stack desktop-session
```

This is the live-host line: collect, compare, reconcile only the drifted
surfaces, and write receipts.

### 2. Package bake-in path

When a fragment proves stable, it graduates into the package itself:

```text
/Programs/<Package>/<Version>/Package/lifecycle.json
/System/PackageDB/<Package>-<Version>.auzix.json
```

That baked metadata feeds:

```bash
auzix-pkg setup <package>
auzix-pkg setup --profile workstation
```

This is the first-install line: package extraction plus the package-local setup
hooks needed to make it usable without hand repair.

## Promotion rule

A fragment can be promoted into a package when all of these are true:

1. Debian/Trixie evidence identifies the same lifecycle surface.
2. The AUZiX path mapping is explicit.
3. The hook is idempotent.
4. The validation probe can prove the surface works.
5. The receipt can explain pass, fail, or skipped state.

If any of those are missing, keep it here as a fragment and mark it
`needs-fragment-evidence` or `needs-package-bake-in`.
