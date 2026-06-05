# Auzix Override Surface

## Purpose

Document what the first x86_64 bootstrap actually hardcodes so we can decide:

1. what to override in the image builder now
2. what to keep as native Linux plumbing for now
3. what eventually requires source/package/toolchain patching

This is based on the current Debian `debootstrap`-driven first pass under:

- `out/auzix-build/rootfs`
- `scripts/build-auzix-x86-image.sh`

## What We Observed

The first pass successfully starts creating the `Auzix` personality:

- `/work`
- `/system`
- `/ram`

But the bootstrap still naturally emits a conventional Linux rootfs:

- `/etc`
- `/usr`
- `/lib`
- `/bin`
- `/sbin`
- `/var`
- `/dev`
- `/proc`
- `/sys`
- `/run`

That is not a surprise. It tells us where the override work really lives.

## Bucket 1: Native Linux Plumbing To Keep For Now

These should remain mounted and usable in their standard locations during early
bring-up, even if `Auzix` later presents higher-level equivalents:

- `/dev`
- `/proc`
- `/sys`
- `/run`

Why:

- kernel/userspace ABI expectations
- initramfs and boot tooling assumptions
- systemd/udev/runtime socket behavior
- broad upstream package expectations

Recommended stance:

- keep them real internally
- present `Auzix` views above them where useful
- do not start by trying to rename them out of existence

## Bucket 2: Builder-Level Overrides We Can Do Now

These are practical first-pass overrides in the image builder without patching
Debian itself.

### Directory skeleton

Already reasonable to create during build:

- `/system/c`
- `/system/libs`
- `/system/s`
- `/system/devs` or `/system/devices`
- `/system/prefs`
- `/system/apps`
- `/work`
- `/ram`

### User/session defaults

Can be influenced now:

- `PATH`
- `LD_LIBRARY_PATH`
- `TMPDIR`
- `XDG_CONFIG_HOME`
- `XDG_DATA_HOME`
- `XDG_CACHE_HOME`

### Mutable storage

Can be redirected now:

- `/home -> /work/home`
- `/tmp -> /ram/tmp`

Possible next overrides:

- `/var/log -> /work/log`
- `/var/cache -> /work/cache`
- selected app state into `/work/state`

## Bucket 3: Package-Manager And Base-Distro Hard Assumptions

These are the strongest immediate reasons the first pass still looks like normal
Debian.

### `/etc`

Observed examples:

- `etc/apt/sources.list`
- `etc/default/*`
- `etc/pam.d/*`
- `etc/systemd/*`
- `etc/ld.so.conf*`
- `etc/profile`
- `etc/skel/*`

Implication:

- Debian packages assume global config under `/etc`
- startup policy, PAM, linker config, package policy, and shell defaults all
  begin there

### `/var`

Observed examples:

- `var/lib/dpkg`
- `var/lib/apt`
- `var/lib/systemd`
- `var/cache/apt`
- `var/log/*`
- `var/tmp`
- `var/run`

Implication:

- package state, cache, logs, runtime state, and service bookkeeping are deeply
  tied to `/var`

### `/usr`, `/lib`, `/bin`, `/sbin`

Observed examples:

- `usr/lib/systemd/system/*`
- loader config pointing at architecture-specific lib paths
- standard command installation under merged-usr layout

Implication:

- this is not just cosmetic
- linker, package manager, and service layout all expect these locations

## Bucket 4: Areas Likely Requiring Package Patches

These are the places where env vars and builder scripts stop being enough.

### Package metadata and state

- `dpkg`
- `apt`
- `debconf`
- alternatives
- package logs and caches

### Runtime/service layout

- `systemd` unit search paths
- service defaults under `/etc/default`
- runtime files under `/run` and `/var`
- journaling/log paths

### Device policy

- `udev` rules
- `modprobe.d`
- module metadata and lookup
- firmware and helper search paths

### User-facing desktop stack

- D-Bus activation files
- XDG paths
- icon/theme locations
- browser/cache/download defaults
- file-manager mount and media presentation

## Bucket 5: Areas Likely Requiring Toolchain/Libc Patches

If the final goal is strict path obedience without FHS compatibility, these are
the deeper layers that eventually define the real contract.

- dynamic linker search defaults
- `ld.so.conf` policy
- `pkg-config` defaults
- GCC include/library search defaults
- binutils search defaults
- install prefixes baked into builds

This is where `/system/c` and `/system/libs` become real ABI, not just a shell
overlay.

## Bucket 6: Kernel And Early-Boot Touch Points

The kernel is not the first obstacle, but these areas matter once we move beyond
the current compatibility-first builder:

- module install/load paths
- initramfs contents and scripts
- firmware lookup paths
- bootloader expectations
- root handoff to init

`/sys` and `/dev` especially belong here as kernel-adjacent plumbing, not just
filesystem naming preferences.

## Recommended Sequence

1. Keep `/dev`, `/proc`, `/sys`, and `/run` native for now.
2. Strengthen builder-level overrides for `/home`, `/tmp`, and selected `/var`
   subtrees.
3. Define the `Auzix` equivalents of `/etc`, `/var`, `/usr`, and `/lib`
   explicitly before patching packages.
4. Patch package-manager and service paths next.
5. Only then start patching toolchain/libc defaults.

## Immediate Next Overrides Worth Trying

The first practical experiments after the current image build are:

- redirect `/var/log` to `/work/log`
- redirect `/var/cache` to `/work/cache`
- decide whether `/etc` maps to `/system/prefs`, `/system/s`, or a split model
- decide whether `Devices` means:
  - a view over `/dev` and `/sys`
  - or a broader hardware-policy domain under `/system/devices`

## Current Bottom Line

What the first pass proves is simple:

- `/work` is easy
- `/ram` is easy
- `/system` is easy as a new top-level tree
- `/etc`, `/var`, `/usr`, `/lib`, and service/package plumbing are the real
  distro fork surface
- `/dev`, `/proc`, `/sys`, and `/run` should be treated as native Linux
  infrastructure first, not as early rename targets
