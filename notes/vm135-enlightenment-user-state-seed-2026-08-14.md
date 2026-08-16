# VM135 Enlightenment user-state seed note — 2026-08-14

## Finding

The fresh packing-fix ISO preserved package ownership/modes correctly enough for
Xorg and Enlightenment helpers to start, including setuid helpers. The remaining
VM135 pinwheel/module failure was not primarily archive chmod/chown damage.

The live user needed a valid Enlightenment/Elementary user state:

- `/Users/auzix/.e`
- `/Users/auzix/.elementary`

Copying the tiny known-good VM132 Trixie profile (`~/.e`, `~/.elementary`) to
VM135 and resetting ownership to `1000:1000` allowed the X/E process stack to
stay alive:

- `xinit`
- `Xorg`
- `enlightenment_start`
- `enlightenment`
- `enlightenment_system`
- `enlightenment_fm`

## Second finding

The copied profile can carry stale module configs. Example seen in the VM132
seed:

- `module.emix.cfg`
- `module.music_control.cfg`

The installed AUZiX/Trixie module directories expose `mixer` and
`music-control`, not `emix`. A seed/import step must prune module config files
whose module directory is absent from the target root. This prevents the
`module.so not found` dialog loop.

## Source changes

- `scripts/stage-auzix-user-defaults.sh`
  - now stages `.elementary/config`
  - prunes stale `module.*.cfg*` files when no matching target module exists
    (`_` to `-` is accepted for names like `music_control` / `music-control`)
- `scripts/add-auzix-live-tools.sh`
  - masks stale `emix` config in the VM-safe live startup path

## Rule going forward

For E desktop validation, do not hand-edit random config in-place first. Seed a
known-good `.e` and `.elementary` profile, sanitize against the installed module
tree, fix ownership, then restart the session and read E logs.
