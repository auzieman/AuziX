# Strict-root proof validation field notes — 2026-08-22

## Why this note exists

We previously validated an ISO that was effectively trashed. It had enough
shape to boot or show a desktop moment, but the proof was too shallow: it did
not prove the package root, launcher wrappers, permissions, terminfo, Python
runtime, library ladder, and user-mode behavior as one coherent AUZiX runtime.

That is now a release-lane failure, not an acceptable smoke-test miss.

## What the latest proof run taught us

The strict proof container and the tiny BusyBox container tell two different
stories and both matter:

- `auzix/service:zero-busybox` is the true base/zero reference. It is small and
  proves AUZiX can produce a clean container without top-level `/bin`, `/usr`,
  `/lib`, or `/lib64`.
- `auzix/strict:rebase-*` is a workstation/proof root. It is intentionally
  chunky because it contains a large `/Programs` tree and debug surface. It must
  not be mistaken for the base image.

The root compatibility paths in the proof container were symlinks, not mounts.
After moving aside `/bin`, `/sbin`, `/lib`, `/lib64`, `/usr`, `/var`, `/tmp`,
`/home`, `/root`, and `/opt`, several AUZiX-native commands still worked when
their wrappers honored AUZiX paths. That is the good news.

The bad news is exactly the validation gap:

- scripts and shebangs still assume `/usr/bin/...` in places;
- some commands assume `/tmp` instead of exported `TMPDIR`;
- curses tools fail unless terminfo paths are exported;
- Python apps need `PYTHONHOME`, `PYTHONPATH`, and `lib-dynload` declared by the
  package/runtime ladder;
- core runtime treated `libgcc-s1` as satisfied but did not always provide
  `libgcc_s.so.1` in `/System/Libraries`;
- `ldd`-style checks must inspect AUZiX wrappers and their `runtime_packages`,
  not only the final ELF path;
- root-only tests are insufficient because user-owned XDG/runtime state can
  still be wrong.

## Concrete examples from the run

### Glances

`Glances` existed, but the compatibility wrapper pointed at a donor path that
did not exist in AUZiX form. The real payload also had a donor shebang:

```text
#!/usr/bin/python3
```

Once the wrapper exported the Python runtime explicitly, `glances --version`
worked. This makes Glances a good Python-script package probe: it catches
shebang, `PYTHONHOME`, `PYTHONPATH`, terminfo, `USER`, `LOGNAME`, and `TMPDIR`
mistakes quickly.

### AbiWord

AbiWord first looked like a missing `libgoffice` failure, but that was partly a
bad validator: the temporary `ldd` did not yet read the wrapper's
`runtime_packages` ladder. After that was fixed, AbiWord advanced to a real
runtime miss: `libgcc_s.so.1`, then `libphonenumber.so.8`.

That distinction matters. A good validator must be able to say:

```text
dependency exists but wrapper ladder did not expose it
```

versus:

```text
dependency is genuinely absent from the closure
```

### Terminfo and terminal tools

`htop`, `nano`, `glances`, and related admin tools should not require an xterm
binary to exist. They require a valid terminal database and a sane `TERM`.

The AUZiX terminal contract now needs:

```text
TERM=xterm-256color when TERM is empty/dumb/linux
TERMINFO_DIRS includes NcursesBase, NcursesTerm, KittyTerminfo, and compatibility terminfo paths
```

This likely explains several previous "xterm-256color" and broken terminal
symptoms.

## Updated acceptance rule

Booting is not validation. A package archive is not validation. A pretty E
wallpaper is not validation.

A release lane must pass:

1. strict root shape audit;
2. package receipt/runtime audit;
3. root-alias-gimp runtime proof;
4. root and user command probes;
5. wrapper-aware `ldd`/loader checks;
6. terminfo/curses probe;
7. Python-script probe when Python packages are present;
8. package-manager install loop proof that does not reinstall satisfied core
   dependencies;
9. desktop/menu proof only after lower gates pass.

If any lower gate fails, do not build or publish the ISO as working media. Fix
the build contract or package contract, rerun the pipeline, and keep the failed
evidence.

## Follow-up fixes to fold into the factory

- Make `libgcc_s.so.1` part of the core runtime when `libgcc-s1` is considered
  satisfied by `/System/Libraries`.
- Promote the AUZiX-aware `ldd`/runtime-ladder probe into a real debug package.
- Generate wrappers that export `TERM`, `TERMINFO_DIRS`, `TMPDIR`, `USER`, and
  `LOGNAME` where appropriate.
- Add a Python runtime helper so Python-script packages do not rediscover
  `PYTHONHOME` one app at a time.
- Keep `base`, `base+debug`, `admin-observe`, `workstation-lite`,
  `workstation-full`, and `dev-toolchain` as separate profiles.
- Treat visible menu launchers as the last gate, not the first proof.
