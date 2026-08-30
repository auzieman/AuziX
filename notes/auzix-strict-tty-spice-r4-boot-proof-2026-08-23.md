# AUZiX strict tty/SPICE r4 boot proof — 2026-08-23

## Artifact

- ISO: `/var/lib/auzix-build/runs/strict-tty-spice-r4-20260823T005327Z/src/artifacts/auzix/auzix-strict-tty-spice-r4.iso`
- Size: `780M`
- Link mode: `strict`

## Gates passed

- Strict root audit passed:
  - `/bin`, `/sbin`, `/lib`, `/lib64`, `/usr`, `/etc`, `/var`, `/tmp`, `/opt`, `/home`, `/root` absent.
  - AUZiX native roots present.
- ISO publication validator passed inside `auzix/builder:lab`.
- QEMU serial smoke passed:
  - `/init` ran.
  - rescue shell appeared on `ttyS0`.
  - DHCP obtained `eth0 ipv4=10.0.2.15/24`.
  - declared services stage ran.
  - display stage started.

## Important caveats

- SSH was intentionally not required for this strict proof. Rescue serial/tty is the required control rope.
- The build wrapper initially failed because `validate-auzix-boot-iso.sh` treated app launchers like Midori/XTerm as boot scripts. The validator was narrowed to init/service/rescue launch scripts.
- Package runtime audit still reports follow-up debt:
  - `AuzixPackageTools` still packages app-local core ABI libraries.
  - Several bridge/proof packages need stronger source/install receipt contracts.

## SPICE launcher

On lab-build/R730:

```sh
cd /home/auzieman/Projects/AuziX
./scripts/launch-auzix-strict-spice-qemu.sh
```

From a workstation, tunnel and connect:

```sh
ssh -L 5930:127.0.0.1:5930 lab-ai-worker
remote-viewer spice://127.0.0.1:5930
```

## r5 forward patch checkpoint — strict init/display handoff

Date: 2026-08-23

RCA from r4:

- The initramfs and `/System/Boot/StartSequence` path were not lost.
- r4 reached `/init`, serial rescue shell, DHCP, services, and display stage.
- The display handoff failed because generated boot scripts used
  `busybox su auzix -c ...`.
- In strict root, BusyBox `su` cannot assume classic `/etc/passwd`/NSS lookup.
  AUZiX has `/System/Settings/passwd`, but that is not enough for this early
  handoff.

Source-side correction:

- `scripts/add-auzix-live-tools.sh` now builds
  `/System/Tools/auzix-run-as-uid`.
- Display handoff now uses numeric uid/gid/groups:
  `1000:1000` plus `tty,input,video,audio` groups.
- The helper must be statically linked. Dynamic fallback is forbidden because
  it reintroduces `/lib64/ld-linux-x86-64.so.2` into the strict handoff.
- `scripts/scaffold-auzix-strict-root.sh` keeps top-level compatibility links
  behind explicit `AUZIX_LINK_MODE=compat/full`; strict mode creates none.
- `StartSequence` now parses `auzix.links=` and creates `/opt`/`/root`
  compatibility links only under the explicit compat hatch.

Lab-build smoke proof:

```text
top-level aliases after live tools:
stale su refs:
uid helper refs:
/tmp/auzix-strict-contract-smoke.bszy0g/AuzixRoot/System/Boot/StartSequence:834:  "${BB}" openvt -c 7 -s -- /System/Tools/auzix-run-as-uid 1000 1000 5,29,44,104 \
/tmp/auzix-strict-contract-smoke.bszy0g/AuzixRoot/System/Tools/start-gui-stage:75:"${BB}" openvt -c "${vt}" -s -- /System/Tools/auzix-run-as-uid 1000 1000 5,29,44,104 \
uid helper file:
.../System/Tools/auzix-run-as-uid: ELF 64-bit ... statically linked
not a dynamic executable
```

Progression rule:

- Do not rewrite the boot/init path while debugging desktop or package issues.
- Treat r4 init as proven.
- Treat r5 as one additive seam fix: numeric static handoff plus strict link
  gating.
- Build the next ISO from a fresh strict root; do not assemble from a dirty
  staged root that already contains compatibility aliases.

## r5 build and serial smoke proof

Run:

- `AUZIX_RUN_ID=strict-r5-20260823T0100Z`
- `AUZIX_ISO_NAME=auzix-strict-tty-spice-r5.iso`
- wrapper: `scripts/run-auzix-live-build-r730.sh`
- published ISO:
  `/var/lib/auzix-build/published/auzix-strict-tty-spice-r5.iso`
- sha256:
  `54bac0a384a74f22c31dac02e3e94fa2b840d4962d933fbad3d230f26854c7cb`

Pipeline gates:

- Fresh scaffold used `link_mode=strict`.
- Fresh scaffold created no top-level compatibility links.
- `Auzix installer tests: PASS`.
- Live installer demo surface staged.
- Package archive metadata audit:
  `archives=36 entries=2490 compared=2490 mismatches=0`.
- Strict root audit: `PASS`.
- ISO publication validator: `PASS`.

QEMU serial smoke:

```text
[StartSequence] stage: mounting runtime filesystems
[StartSequence] stage: starting rescue consoles
Auzix rescue shell on ttyS0. GUI continues on tty7.
[StartSequence] stage: repairing live user home
[StartSequence] stage: starting udev
[StartSequence] stage: staging live assets
[StartSequence] stage: detecting hardware
[StartSequence] stage: fixing session permissions
[StartSequence] stage: starting dbus
[StartSequence] stage: starting network
[StartSequence] network: eth0 state=up mac=52:54:00:12:34:56 ipv4=10.0.2.15/24
[StartSequence] stage: starting declared services
[StartSequence] stage: recording live diagnostic receipt
[StartSequence] stage: starting display
[StartSequence] stage: complete
PASS: qemu ISO boot smoke
```

Remaining follow-up:

- SSH was not listening in the serial smoke (`services: ssh tcp/22 not
  listening`). That is now a service-stage bug, not an init loss.
- Desktop/E visual proof still needs a SPICE/noVNC run. Do not conflate that
  with the init regression: the init sequence is back through display handoff.
