# AUZiX lab operator guardrails — 2026-08-14

These are hard rails for AUZiX lab work from the operator laptop.

## Network reachability

Read the compact routing cheat sheet before lab work:

`/home/auzieman/Projects/BlackKnightController/docs/codex-lab-routing-cheatsheet.md`

- Laptop/operator side directly reaches the `192.168.1.0/24` LAN.
- `10.20.0.0/24` is the private lab side behind ns1/IPFire/OpenStack paths.
- From the laptop, do **not** assume raw `10.20.0.x` is reachable.
- Use BKC, ns1, or the checked-in SSH/tunnel aliases from
  `BlackKnightController/ops/workstation-ssh/`.
- `10.20.x` commands are valid from ns1/BKC/lab-side runners, not as the
  default laptop shell path.

Useful known aliases from BKC:

```text
lab-ns1                  192.168.1.10
lab-edge                 192.168.1.15
lab-openstack            10.20.0.240 via lab-ns1
lab-ipfire               10.20.0.254 via lab-ns1
lab-build                10.20.0.233 via lab-openstack
lab-ai-worker            10.20.0.130 via lab-ns1
lab-bkc-ipfire-tunnel    localhost -> 10.20.0.232:5000
```

## Control-plane and build-master routing

- Server1/OpenStack BKC is the lab master/control plane.
- The Proxmox edge BKC is not the AUZiX lab home; do not drift back to it for
  normal AUZiX build/pipeline state.
- `lab-build` / `bkc-build-01.lab.auzietek.com` / `10.20.0.233` is the build
  master for AUZiX build staging, git clones, mounted source trees, and package
  build state.
- `lab-ai-worker` / R730 / `10.20.0.130` is the AI/Ollama and heavy Docker
  worker. It may run containers, validation, and AI review, but do not silently
  substitute it for `lab-build` when the task says build master.
- ns1 remains the shared source/publication/mirror surface:
  - source/reference mount examples: `/mnt/ns1/AuziX/src`;
  - build receipts: `/mnt/ns1/AuziX/build-receipts`;
  - repo publication: `/srv/http/auzix/repo`.
- If `lab-build` is unreachable, stop and report the infra gate. Do not
  compensate by routing the build through edge BKC or a laptop-local scratch
  path unless the operator explicitly changes the target.

Observed on 2026-08-14 from ns1:

```text
ipfire=up
openstack=up
lab-build=down
lab-ai-worker=up
```

This means the AI worker can be alive while the build master is still offline;
those are separate gates.

## VMID135 power behavior

ACPI shutdown/reset is not reliable enough to use as the normal control path
yet. For boot-order or ISO changes:

1. hard stop the VM;
2. wait until Proxmox reports `stopped`;
3. change ISO/boot order;
4. hard start the VM;
5. observe only; do not stack repair scripts into a half-booted guest.

Do not rely on `qm shutdown`, guest ACPI, or a live reboot when changing boot
media. That path repeatedly produced confusing partial states.

## Desktop rule

The desktop should be produced by package lifecycle semantics during install:

```text
package install -> lifecycle hooks -> caches/triggers -> session sees menu
```

Avoid late broad repair scripts. If a package needs a user, group, Polkit
policy, DBus service, MIME update, icon cache refresh, GSettings schema compile,
Efreet cache refresh, or alternatives entry, capture that in package metadata
and install-time lifecycle hooks.

## ISO build guardrails

Do not start a fresh ISO build from memory. Read these anchors first:

- `notes/auzix-known-good-live-desktop-vs-published-repo-2026-08-10.md`
- `notes/express-container-host-and-lean-iso-2026-08-09.md`
- `docs/tiny-netinstall-media.md`
- `docs/live-boot-contract.md`
- `packages/netinstall-reconstruction.profile.json`
- `packages/netinstall-chroot-package-transaction.contract.md`

Known-good anchors:

- Graphical/live desktop reference:
  - `artifacts/auzix/auzix-live-theme-app-candidate.iso`
  - known-good stack includes host `Xorg`, host `LightDM`, host `DBus`, host
    `Terminology`, `Enlightenment=0.25.4-2`, `Midori=11.8`, and the documented
    theme/wallpaper/desktop asset packages.
- Installer-spine reference:
  - `auzix-netinstall-express-r4-20260810T024318Z.iso`
  - documented SHA-256:
    `ad7027fa1fd4807781ba7a8875be1412c6f9dde6c569d4fe469d27162d79017a`
  - proven gates: manual GUI autostart, DHCP, SSH, installer validation,
    disk install, disk boot, repo refresh, and rootful Podman `info`.

Allowed next ISO delta:

1. preserve the r4 shell/network/SSH/install behavior;
2. add ext4/E2fsprogs tooling to the live installer spine;
3. stage `/System/Tools/auzix-existing-installer-preflight`;
4. refuse silent ext2 fallback in normal installs;
5. preserve explicit known-good desktop package identities when building a
   workstation profile.

Do **not** let friendly names such as `Xorg`, `LightDM`, `Enlightenment`,
`Terminology`, or `Curl` drift to newer native-repack packages in a filming or
baseline workstation profile unless that replacement has passed the same
known-good gates. Newer Debian-intake packages belong in a separate validation
lane until promoted.

Before any ISO build, write the build intent into the current outcome note:

```text
Intent:
  Base anchor:
  Minimal delta:
  Packages/profiles touched:
  Explicit non-goals:
  Rollback artifact:
```

After any ISO boot/install attempt, append the actual gate results:

```text
Outcome:
  ISO artifact:
  SHA-256:
  VM target:
  Booted BIOS/UEFI:
  DHCP:
  SSH:
  auzix-installer validate:
  ext4 preflight:
  disk install:
  ISO detached:
  disk boot:
  LightDM:
  keyboard:
  mouse:
  Enlightenment:
  terminal:
  menus:
  selected app launches:
  logs/screenshots:
  verdict:
```

Stop immediately if a gate fails. Do not pile on live repair scripts to make the
same run look better. Preserve logs, capture the failing package/lifecycle
surface, then decide whether to rebuild from the known-good anchor or patch a
single package/profile.
