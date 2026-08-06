# AuziX Live Boot Contract

## Decision

AuziX live media follows the normal Linux live-ISO pattern. The identity of the
filesystem is AuziX; the boot mechanics are intentionally conventional.

```text
firmware -> GRUB -> kernel + small initramfs
                     |
                     +-> mount ISO read-only
                     +-> mount /live/auzix-root.squashfs read-only
                     +-> mount one tmpfs writable overlay
                     +-> switch_root to the merged AuziX root
                                      |
                                      +-> /init mounts runtime filesystems
                                      +-> StartSequence starts declared services
                                      +-> display manager / GUI is an explicit stage
```

The ISO must not expose the whole `AuzixRoot` tree as its operational root.
That makes mutations depend on accidental mount order and produces exactly the
permissions/state split seen in prior Midori, graphics, DNS, and profile work.

## Writable live state

The merged root is writable through **one** overlay. Runtime-owned paths are
then explicit contracts, not a collection of late boot repairs:

| Path | Owner/purpose | Live backing |
| --- | --- | --- |
| `/run` | processes, sockets, XDG runtime | tmpfs |
| `/tmp`, `/var/tmp` | temporary work | tmpfs |
| `/Users` | user profiles, browser state | overlay |
| `/Work` | user/operator workspace | overlay |
| `/System/State` | service/package runtime state | overlay |
| `/System/Logs` | bounded live diagnostics | overlay/tmpfs policy |
| `/Network/DNS` | DHCP receipt and resolver state | overlay/runtime link |

`/System/Settings` remains package-owned and effectively immutable during a
normal live boot. A service needing mutable configuration writes under
`/System/State/<service>` or the user profile—not into the ISO-origin settings
tree.

If the writable overlay cannot be mounted, boot must stop. A read-only bind
fallback can render a desktop, then fail later when Midori, DBus, or the
desktop first writes session state.

## Browser and graphics rules

- The desktop starts only after the writable-state contract and network receipt
  have passed.
- Midori owns its profile below `/Users/auzix`; its bundle/library closure,
  CA bundle, and GTK/X11 dependencies remain read-only package assets.
- DNS is published once through the live runtime resolver path; browser wrappers
  consume that path instead of each creating or copying resolver files.
- A serial/TTY shell remains available for evidence collection, but it is a
  diagnostic companion to the graphical boot—not a substitute for it.

## Operator access and desktop acceptance

SSH, serial/TTY, and the live diagnostic receipt start before the graphical
stage. They must remain available when a display component fails, but they are
not the primary user experience and must not delay a healthy desktop boot.

The live desktop acceptance target is comparable to a Debian, Ubuntu, or Elive
installer session:

- a pre-seeded, VM-safe Enlightenment profile (X11/software rendering, no GL,
  Bluetooth, or optional media modules);
- networking available from the desktop session;
- a clearly visible **Install AuziX** launcher that starts the existing
  installer flow;
- optional disk tooling such as GParted only after the base graphical
  installer path is proven.

The network module is intentionally part of the minimal profile. If it cannot
reach its service/runtime socket, the receipt must identify the path,
ownership, or DBus permission defect before broader desktop features are added.

## Recovery sequence

1. Preserve `auzix-strict-desktop-20260606-r3.iso` as the visual/runtime
   reference image.
2. Produce a normal SquashFS-plus-overlay beta using the exact current strict
   root and matching kernel/modules.
3. Prove boot, DHCP/DNS, and writable profile state on disposable VM135.
4. Run Midori's package-owned runtime audit and one HTTPS smoke request.
5. Only then bring the GUI launcher and installer paths back into the default
   media flow.

No bulk package rebuild is part of this recovery. Each failed contract becomes
a package or live-root receipt with a targeted test.
