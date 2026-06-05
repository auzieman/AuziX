# Auzix First Login

## Purpose

Capture the first expected local login path for the x86_64/KVM image while the
desktop and filesystem work is still in flux.

## Current Login Defaults

The builder currently creates:

- user: `auzi`
- password: `auzi`
- root password: `root`

These are set in:

- [scripts/build-auzix-x86-image.sh](/home/auzieman/Projects/tabor-linux-forge/scripts/build-auzix-x86-image.sh:18)

They can be overridden at build time with:

```bash
AUZIX_USERNAME=myuser AUZIX_PASSWORD=mypass AUZIX_ROOT_PASSWORD=myrootpass make auzix-image
```

## Review Paths

Headless serial-console review:

```bash
make auzix-run
```

Graphical QEMU window review:

```bash
make auzix-gui
```

Equivalent direct command:

```bash
AUZIX_HEADLESS=0 ./scripts/run-auzix-kvm.sh
```

## Notes

- The current x86 image builder still boots to `multi-user.target` by default.
- GUI packages may be installed in the image, but the first review path should
  still assume shell-first debugging.
- Once logged in, the current helper command intended for quick inspection is:

```bash
/system/c/auzix-report
```
