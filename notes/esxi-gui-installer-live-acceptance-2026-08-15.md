# ESXi GUI installer live acceptance — 2026-08-15

Correction/current fact: this is not only a future ISO plan. A new AUZiX ISO is
already running on ESXi with a GUI. Treat the live guest as the current proof
surface.

## Immediate acceptance path

From the running ESXi GUI ISO, verify these before rebuilding or redesigning:

1. graphical session is alive;
2. keyboard and mouse work in the console path being used;
3. `Install AUZiX` launcher opens the safe installer frontend;
4. rescue terminal opens, preferably `xterm`;
5. browser opens, preferably Midori with NetSurf fallback;
6. file manager opens;
7. SSH works, or the failure is recorded as an explicit gate;
8. debug/internet tools are present:
   - `ip`
   - `curl`
   - `strace`
   - `file`
   - `df`
   - `du`
   - `less`
9. installer plan validates:

   ```sh
   /System/Tools/auzix-installer validate /System/Settings/installer/plans/workstation-demo.json
   ```

10. preflight proves ext4 before any destructive install:

    ```sh
    /System/Tools/auzix-existing-installer-preflight /dev/vda
    ```

## Graphical installer enhancement pass

The EFL frontend now matches the installer spine more closely:

- package checkboxes are first-boot package intent, not a blocker;
- selected packages are carried into the JSON plan;
- destructive install still requires a second confirmation;
- the installer text explicitly says base install happens first and hydration
  consumes the package queue later;
- labels avoid `Debian.*` naming where AUZiX package names exist.

The backend remains the trusted destructive gate. The graphical frontend only
writes an unconfirmed plan and asks the Lua validator/executor to cross the
gate.

## Build lane

The local operator shell may not have EFL headers (`Elementary.h`). Compile and
stage this frontend through the existing lab/R730 lane instead:

- `scripts/run-auzix-live-recovery-r730.sh`
- `scripts/run-auzix-live-assemble-r730.sh`
- `scripts/build-auzix-installer-efl-package.sh`

The graphical installer source is:

- `installer/efl/auzix-installer-efl.c`

The packaged launcher remains:

- `/System/Tools/launch-auzix-installer`

For this ESXi proof, the acceptance test is not merely “compiled”; it must open
visibly in the running GUI ISO, write an unconfirmed plan, and then invoke the
same guarded backend as the TUI.

## Do not drift

- Do not start by inventing another ISO.
- Do not stage large scratch work on the laptop.
- Do not hand-repair the live guest into an unrepeatable snowflake.
- If a launcher fails, read the E/session log and fold the missing lifecycle
  step back into the package/profile.

## Next promotion

If the running ESXi GUI ISO passes the live acceptance checks, then promote the
profile/pipeline work as the repeatable build contract:

- `packages/live-installer-demo.profile.json`
- `profiles/packages/auzix-live-installer-demo.packages`
- BKC pipeline `auzix-package-repo-stripped-iso`

The public Auzietek/IONOS shelf comes after lab blessing, not before.
