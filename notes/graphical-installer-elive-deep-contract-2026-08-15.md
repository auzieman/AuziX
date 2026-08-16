# AUZiX graphical installer — Elive-deep contract — 2026-08-15

Goal: make the AUZiX installer feel like a real Enlightenment-native operating
system installer, not a shell script in a fancy coat.

## Inspiration notes

Elive is a useful reference because it treats the live session, installer,
customization, and Enlightenment experience as one integrated thing. Public
Elive material describes a Debian-based Enlightenment distro with a live mode,
own installer, persistence features, many advanced-user tools, and a focus on
being usable on low-resource systems. Older installer feedback also calls out
guided help, customized options, visible progress, and optional installation
progress information.

AUZiX should borrow the useful shape, not clone the implementation:

- live session first;
- guided installer;
- advanced options without overwhelming the default path;
- visible progress and logs;
- safe destructive gate;
- post-install package/profile intent;
- Enlightenment-native look and feel.

## Installer personality

The installer should be calm and explicit:

```text
Welcome -> Target -> User/Region -> Package Profile -> Review -> Preflight -> Install -> Receipt/Reboot
```

The operator should always know:

- what disk will be erased;
- what boot mode is selected;
- what account/region defaults will be recorded;
- what package profile will hydrate after base install;
- where logs/receipts live;
- how to recover through SSH/terminal if the GUI fails.

## Visual direction

North star: **if Mac were Linux, but dark-mode AUZiX**.

The installer should look crisp, dark, and intentional:

- dark charcoal/navy background;
- cool cyan/teal highlights for safe/ready states;
- amber for warnings and destructive-review gates;
- red only for true failures;
- high contrast text, no muddy gray-on-gray;
- large calm spacing, not a cramped science-fair control panel;
- optional mythic BlackKnight/Auzietek accent art:
  - shield;
  - crossed swords;
  - small Auzietek/BlackKnight wordmark;
  - subtle watermark/background mark rather than a giant splash logo.

Preferred asset contract:

```text
/System/Settings/installer/theme/
  installer-theme.json
  background-dark.png        optional
  mark-shield-swords.png     optional
  mark-auzietek.svg          optional
  mark-blackknight.svg       optional
  retro-boing-strip.png      optional retro/Amiga accent, not default
```

Fallback rule: if the art is missing, the installer still launches with the
dark palette and text-only header. Branding must never be a startup dependency.

Current local art staged into AUZiX:

- primary installer mark:
  - source: `/home/auzieman/Projects/auzietek/ChatGPT Image Aug 15, 2026, 03_04_47 PM.png`
  - staged: `installer/theme/assets/mark-shield-swords.png`
  - mood: Auzietek shield, blue circuitry, knight helm; good default for the
    BlackKnight-dark installer.
- optional retro accent:
  - source: `/home/auzieman/Projects/auzietek/ami.auztek/src/themes/boing-ball_resized_2048x100.png`
  - staged: `installer/theme/assets/retro-boing-strip.png`
  - mood: Amiga/boing; keep for optional retro flavor, not the primary
    installer identity.

Suggested header:

```text
BLACKKNIGHT // AUZiX DEPLOYMENT CONTROL
```

Suggested friendlier subtitle:

```text
Build your AUZiX machine. Base first, extras after.
```

The theme should feel cinematic, but operational. This is an installer, not a
poster.

## Current EFL enhancement

`installer/efl/auzix-installer-efl.c` now reflects the current installer spine:

- package checkboxes create first-boot package intent;
- package intent no longer blocks base install;
- package labels use AUZiX package-style names instead of `Debian.*` where known;
- the confirmation text states that base install happens first and package
  hydration consumes the queue later;
- added `RUN PREFLIGHT`, which calls:

  ```sh
  sudo -n /System/Tools/auzix-existing-installer-preflight TARGET
  ```

  and writes:

  ```text
  /System/Logs/installer/preflight.log
  ```

## Next UI refactor

The current single-scroll form is acceptable as a live proof, but the real next
pass should become wizard-like:

1. welcome/status page
   - network/SSH indicator
   - repo indicator
   - storage-tool indicator
   - “advanced details” toggle
2. target/storage page
   - discovered disks list, not manual `/dev/sda` typing only
   - clear erase warning
   - whole disk default;
   - simple user-install profile: `/Home`, `/Work`, and `/Programs` may become
     mountpoints;
   - custom percentages/sizes as advanced, not a science-fair partition editor
3. identity/region page
   - user
   - hostname
   - locale/timezone/keyboard
4. package profile page
   - Base install
   - Desktop
   - Workstation/demo
   - Container host
   - Developer tools
   - custom package list as advanced
5. review page
   - render the JSON plan in human form
   - validate plan
   - run preflight
6. install page
   - progress pulse
   - log tail/details
   - install receipt path
7. finish page
   - reboot/eject instructions
   - exact next boot mode
   - package hydration status or queue path

## Hard rules

- The EFL frontend never performs destructive disk actions directly.
- The Lua backend remains the execution gate.
- TUI/SSH must remain valid if the GUI breaks.
- Every GUI option must map to JSON plan fields or an explicit future field.
- Any package option shown in the GUI must be either:
  - installable now, or
  - visibly marked as queued/intent.
- Storage choices should be human profiles first:
  - simple one-root install;
  - user install with `/Home`, `/Work`, `/Programs`;
  - custom percentages/sizes only when requested.
- No duplicate fake menu entries.
- No broad live repair scripts to make a broken run look good.

## ESXi proof gate

For the currently running ESXi GUI ISO, success means:

- GUI opens;
- mouse and keyboard work in the remote console path;
- installer opens visibly;
- `RUN PREFLIGHT` runs and reports/logs clearly;
- `VALIDATE PLAN` writes an unconfirmed plan;
- selected package intent appears in that plan;
- destructive install still requires final confirmation;
- failed checks leave readable logs rather than a frozen mystery spinner.
