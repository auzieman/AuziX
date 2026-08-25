# AUZiX beta factory recenter — 2026-08-23

> Build authority: this note is a required input to the session bootstrap. A
> clean lab checkout must stop before discovery or compilation when it is
> absent.

AUZiX is close to a real beta, but the next lane must be boring and
package-lifecycle accurate.  The failed strict-path push was still useful: it
proved the system is near a deep custom OS spin, not merely a remixed desktop
install, but it also exposed that Codex must not mutate the distro substrate
without tighter release rails.

## What is real

- AUZiX already has a package factory, live ISO lineage, custom path model,
  tiny BusyBox/Nginx containers, package repository output, and BKC/lab-build
  orchestration.
- The current architecture can assemble and boot custom AUZiX roots.
- The r13 relaxed/no-normalize pass recovered the core live boot after the r8+
  ELF normalization regression:
  - BusyBox/init booted.
  - udev, dbus, and acpid ran.
  - DHCP/network came up.
  - Midori CA/HTTPS probe passed.
- VMID135 on the known-good small-moon ISO remains the graphical anchor.

## What failed

- Strict/no-legacy path work was allowed to merge with unrelated ELF interpreter
  normalization.
- The r8+ normalization lane rewrote dynamic interpreters to
  `/System/Libraries/Runtime/glibc/ld-linux-x86-64.so.2`; that produced the
  r12 loader segfault storm.
- Static ISO validation was too weak.  It did not catch GUI/runtime failures
  early enough.
- QEMU/SPICE is useful for serial/core smoke, but it is not yet a trusted
  graphical acceptance target for AUZiX E/X.
- A build that is "core boot OK" is not a publishable graphical ISO.

## Beta direction

Treat AUZiX as a remixed clone of Debian/Slackware at the lifecycle level, not
as an invented packaging ritual.

The public names and filesystem projection can be AUZiX-native:

- `/Programs`
- `/System`
- `/Services`
- `/Users`
- `/Work`

But the lifecycle truth should mirror proven distro behavior:

- dependency resolution from a locked Debian release universe;
- package pre/post install/remove semantics;
- ownership, modes, setuid/sticky bits preserved;
- users, groups, caches, menus, dbus state, CA state, font/icon state captured;
- central installed package state updated atomically;
- no alternate glibc/core ABI packages unless the whole base is intentionally
  rebuilt;
- no ELF interpreter rewriting in live/beta lanes until proven in an isolated
  micro target.

## Lane split

Use two lanes:

1. `compat-beta`
   - known-good graphical ISO lineage;
   - compatibility aliases allowed;
   - no ELF normalization;
   - publishable only after VMID135/PVE or real hypervisor GUI proof.

2. `strict-lab`
   - no-links/no-legacy research;
   - isolated container/rootfs proofs only;
   - cannot overwrite or replace the beta/demo lineage.

## Build-factory rule

No package enters the beta repo unless:

1. dependencies are resolved from a locked release manifest;
2. file ownership/modes/setuid/sticky bits are preserved;
3. upstream lifecycle scripts are captured or intentionally translated;
4. install/update modifies central package state atomically;
5. `readelf`/`ldd`/`strings` checks pass in a validation root;
6. GUI apps prove launcher and runtime from a normal user session;
7. build notes/receipts are written automatically to BKC/bkc-channel.

## Immediate next step

Revert publish work to the known-good small-moon/VMID135 graphical lineage and
add only the compatibility boot/path allowance.  Do not carry r8+ ELF
normalization into the beta lane.
