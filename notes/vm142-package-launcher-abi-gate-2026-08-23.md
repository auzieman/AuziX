# VM142 package and launcher acceptance gate — 2026-08-23

## Outcome

VM142 is a Moon-derived compatibility control, not a valid acceptance target
for the locked Trixie package repository. Its active core is glibc 2.36. The
repository's Python 3.13 payload requires `GLIBC_2.38`; the strict rebase
container runs the same Glances payload successfully.

Do not install another glibc pocket or relink the running VM. Promote a bootable
root built from the locked glibc 2.41 release tree, then run launcher acceptance
there.

## Package-manager proof

- Glances resolved to a deterministic dependency-first plan.
- Five already installed packages disappeared from the resumed plan.
- The remaining 67 packages installed once each; no recursive repulls occurred.
- Removing the full installed-state rescan after every package changed the
  dependency wave from the former O(n^2) crawl to roughly one minute after
  prefetch.
- Leaf installs no longer run the root finalizer or linker refresh and did not
  kill the running X/Enlightenment session.
- The package transaction nevertheless should have failed before installation:
  presence of the active core glibc was mistaken for ABI compatibility.

## Contract changes

- Debian intake receipts now record each payload's maximum required GLIBC symbol
  floor as `source.required_glibc`.
- `auzix-pkg install/update` checks every planned package against the active core
  glibc and fails with `runtime-rebuild-required` before prefetch/install.
- Python shebang commands are invoked through the AUZiX Python wrapper instead
  of relying on `/usr/bin/python3`.
- Desktop entries are explicit receipt artifacts.
- Glances receives a canonical terminal desktop entry because Debian does not
  ship one.

## Desktop acceptance contract

For Pluma, Glances, and each LibreOffice module:

1. install against the locked release root;
2. confirm the receipt and exact command wrapper;
3. confirm one canonical `.desktop` entry in the correct category;
4. confirm its `Exec=` references the `/Programs/.../current/Commands/...`
   wrapper;
5. launch the desktop entry as UID 1000 inside the active E session;
6. observe a stable application process and clean loader/session logs;
7. reboot cleanly and repeat the launch;
8. only then make the entry visible and publish the package.

No root-only command probe, hidden duplicate entry, or hand-created VM launcher
counts as acceptance.
