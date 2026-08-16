# AUZiX ISO initial E boot contract — 2026-08-15

Scope: ESXi graphical live ISO first boot, after `vmwgfx` support was added.

## Live finding

The AUZiX guest was not kernel/X dead when the browser console showed the
Enlightenment spinner. From SSH:

- `Xorg`, `enlightenment_start`, and `enlightenment` were running.
- `/Users/auzix/.e-log.log` reached `MAIN LOOP AT LAST`.
- The blocking visual symptom matched a stale Enlightenment module request:
  `wizard/linux-gnu-x86_64-0.25.4/module.so` was requested but the module was
  intentionally absent/disabled.

## Root cause

The live boot logic masked unstable E modules, including `wizard`, but the
default E profile still referenced those modules in `e.cfg`. If E regenerates
or re-seeds user config from the system default profile, the stale module request
comes back even after user config cleanup.

## Contract

When AUZiX masks an Enlightenment module at ISO boot, it must also prune matching
module and gadcon-client entries from:

- `/Users/auzix/.e/e/config/standard/e.cfg`
- `/Users/auzix/.e/e/config/default/e.cfg`
- `/System/Compatibility/usr/share/enlightenment/data/config/standard/e.cfg`
- `/System/Compatibility/usr/share/enlightenment/data/config/default/e.cfg`
- legacy aliases under `/usr/share/enlightenment/data/config/...` while those
  compatibility paths remain active

This pruning must happen before `start-enlightenment-session` launches E.

For the live ISO lane, stale profile configs are disposable. If a seeded user
profile still references a masked/broken module such as `wizard`, AUZiX should
quarantine the profile configs and let Enlightenment seed clean state instead of
trying to rescue every stale generated `.cfg`.

## Patch applied

`scripts/add-auzix-live-tools.sh` now stages an `eet`-aware prune step in both:

- root-time live prep: `prune_enlightenment_masked_modules_root`
- user-session prep: `prune_enlightenment_masked_modules`

It also stages a stronger live-media cleanup:

- root-time live prep: `blast_stale_enlightenment_configs_root`
- user-session prep: `blast_stale_enlightenment_configs`

These preserve backups under `.e/backup/stale-config-blast-*`, remove stale
profile `.cfg` files that still mention `wizard`, and record the action in
`/System/State/desktop/enlightenment/blasted-stale-configs`.

The prune list matches the modules AUZiX marks VM-unsafe or absent for the live
desktop: `wizard`, `connman`, `bluez5`, `packagekit`, low-level Wayland modules,
power/backlight modules, and similar optional surfaces.

The script keeps `.pre-auzix-module-prune` backups and records touched configs
under `/System/State/desktop/enlightenment/pruned-module-configs`.

## Validation command

After boot:

```sh
ssh -J lab-ns1 root@10.20.0.113 \
  'ps w | grep -E "Xorg|enlightenment|start-e|xinit" | grep -v grep;
   grep -Ei "MODULE ERR|error loading|denied|failed" /Users/auzix/.e-log.log | tail -30;
   tail -20 /Users/auzix/.e-log.log'
```

Expected:

- E reaches `MAIN LOOP AT LAST`.
- No `wizard` module load error.

## Live validation

On the ESXi AUZiX live VM, blasting `/Users/auzix/.e/e/config/default` removed
the recurring `wizard` module error. After restarting E:

- `Xorg`, `enlightenment_start`, and `enlightenment` respawned.
- E reached `MAIN LOOP AT LAST`.
- Recent errors only showed missing optional profile config files
  (`e_comp.cfg`, `e_randr2.cfg`, `e_remember_restart.cfg`), not module-load
  failure.

## ESXi mouse/input rule

On ESXi, `VirtualPS/2 VMware VMMouse` exposes two event devices:

- one absolute device (`ABS=3`)
- one relative device (`REL=103`)

The browser console needs the absolute side as the X core pointer. The failed
boot picked the relative side (`event2`), which left keyboard alive but mouse
dead. Live repair changed `AuzixTablet` to `/dev/input/event1`; Xorg then logged
`Found absolute axes` and initialized the device as a touchscreen.

`scripts/add-auzix-live-tools.sh` now prefers absolute pointer events for QEMU
tablet / VMware VMMouse before falling back to relative pointer devices.
