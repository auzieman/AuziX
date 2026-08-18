# VM135 recenter after workstation regression

Date: 2026-08-09

VM135 is no longer a useful preserved demo state. Treat it as scratch.

## Current diagnosis

VM135 was rebuilt through a lean installer path and then hydrated with package
fragments. It is not equivalent to the prior themed/workstation AUZiX demo.

Observed contrast against VM132 Trixie reference:

| Area | VM132 working reference | VM135 current AUZiX scratch |
|---|---|---|
| init | `systemd` | BusyBox `sh` |
| rootfs | `ext4` | `ext2` |
| command surface | normal `/usr/bin` tools | giant AUZiX package PATH plus symlink bandages |
| desktop/session | Xorg + LightDM + E + Terminology profile | only partial packages installed |
| Podman | `podman0` active | binary present; demo state not restored |
| installed baseline | `busybox coreutils dbus e2fsprogs enlightenment iproute2 lightdm podman terminology xorg` | `BusyBox Coreutils DBus LightDM Podman` |

The regression was caused by treating extracted/installed packages as if they
formed an integrated workstation. They do not. AUZiX needs a profile contract.

## Useful changes from the messy run

These were committed and may be useful in the next clean pass:

- `DBus` native-name casing correction.
- Installed-dpkg bridge for installed Trixie packages with no downloadable
  archive source in the builder.
- `LibpamSystemd`, `LibpamRuntime`, and `SystemdSysv` published to the ns1
  package repo.
- `LightDM` repo artifact/index repaired from `DBUS` to `DBus`.
- LightDM wrapper proof on VM135: `lightdm 1.32.0` runs when using the Trixie
  `Libc6` loader and a fuller runtime-library ladder.
- E2fsprogs command-suite hook proved in the synced NS1 build path and exposes
  `mkfs.ext4`.

## Build-master warning

R730/lab-build is the active build master. NS1 is a mirror/publication surface,
not the default source-of-truth checkout.

`scripts/run-auzix-live-build-r730.sh` now defaults to:

```text
AUZIX_SOURCE_ROOT=/home/auzieman/Projects/AuziX
AUZIX_PUBLISH_DIR=/var/lib/auzix-build/published
AUZIX_RECEIPT_DIR=/var/lib/auzix-build/receipts
```

If NS1 is needed, set it explicitly as a mirror/publish target after the build
artifact validates. Do not push source snapshots into `/mnt/ns1/AuziX/src` as a
normal build step; NS1 can fill up and turn source sync into the failure mode.

Older notes may mention:

```text
/srv/auzix/AuziX/src
/mnt/ns1/AuziX/src
```

Treat those as historical paths unless a specific pipeline deliberately selects
them.

## Next run guardrail

Do not start with a new ISO loop.

1. Find the last known-good AUZiX demo ISO/receipt/screenshots.
2. Wipe/rebuild VM135 from that known-good baseline.
3. Snapshot immediately after terminal/E/Podman demo basics pass.
4. Define a real `AuzixWorkstationBase` profile using VM132 as reference.
5. Install/replay the profile as a unit.
6. Acceptance tests:
   - `ip addr`, `clear`, `df -h`;
   - E/Terminology open;
   - repo refresh;
   - `podman info`, `podman ps`;
   - AUZiX nginx/flask container demo page loads.
7. If terminal/session basics regress, rollback instead of layering fixes.
