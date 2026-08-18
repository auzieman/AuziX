# AUZiX package-state and runtime-scope proof — 2026-08-17

## What broke vmid135

The live vmid135 session was contaminated by force-installing repo `Libc6` into `/`.
That proved the wrong thing: replacing or shadowing the live/root libc can destabilize SSH,
the desktop, and already-running processes. Do not fix GUI package runtime errors by
installing userland libc into the active root.

## Package-state loop proof

`auzix-pkg` must treat `/System/State/packages/installed.json` as the central live truth.
The ISO/disk builder may compose an install intent, but each package install must update
and reload central state before resolving the next package.

The receipt bootstrap path is the correct way to recover state for a prebuilt live root:

```sh
auzix-pkg bootstrap-receipts /System/PackageDB
```

On vmid135 live ISO this moved the installed-state count from `217` to `221`, then:

- `auzix-pkg plan Htop` returned `new_packages=0`
- `auzix-pkg install L3afpad` installed exactly the planned 62 packages
- after L3afpad installed, `auzix-pkg plan L3afpad` returned `new_packages=0`
- `auzix-pkg plan Geany` shrank to only 5 packages

That proves the dependency loop was package-state related, not a need to rebuild the
planet.

## Runtime-scope proof

L3afpad still failed after installation because the generated wrapper allowed old
`/System/Compatibility` libc/libm to win before the newer Trixie package runtime:

```text
libm.so.6: version `GLIBC_2.38' not found
libc.so.6: version `GLIBC_2.38' not found
```

A disposable local extraction of the full L3afpad closure proved the correct model:

- use the package-scoped loader from `Libc6`
- use package `RootFS` library directories first
- keep `/System/Compatibility` only as a late fallback
- never hijack the root/live libc

Successful proof loader shape:

```sh
/Programs/Libc6/current/RootFS/usr/lib64/ld-linux-x86-64.so.2 \
  --library-path "/Programs/L3afpad/current/RootFS/usr/lib/x86_64-linux-gnu:...dependency RootFS libs..." \
  /Programs/L3afpad/current/RootFS/usr/bin/l3afpad
```

`scripts/build-auzix-debian-intake-package.sh` was patched so generated wrappers prefer
`/Programs/Libc6/current/RootFS/.../ld-linux-x86-64.so.2` and place package/dependency
RootFS libraries before compatibility fallback paths.

## Next validation

1. Rebuild one small canary package on lab-build, preferably `l3afpad`.
2. Reset vmid135 to a clean live ISO.
3. Bootstrap receipts.
4. Install canary.
5. Confirm wrapper `--list` resolves `libc.so.6` and `libm.so.6` from
   `/Programs/Libc6/current/RootFS`, not `/System/Compatibility`.
6. Only then move to Geany/LibreOffice/Flatpak cleanup.
