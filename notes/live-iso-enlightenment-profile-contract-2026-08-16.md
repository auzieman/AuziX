# Live ISO Enlightenment profile contract — 2026-08-16

The live ISO desktop must use AUZiX's packaged/repo Enlightenment profile as the
source of truth. Do not import the builder/operator's `$HOME/.e` by default.

Current contract:

- seed `/Users/auzix/.e/e/config/{standard,default}` from `assets/display/config`
  first;
- Foggy Trees is the intended default wallpaper and should remain selected in
  `standard/e.cfg`;
- the first-run `wizard` module config is removed, but the module payload stays
  packaged on the ISO;
- unstable/missing modules such as `bluez5`, `connman`, and low-level Wayland
  modules may have their profile references pruned, but their module directories
  must not be moved into `disabled-modules` on live media;
- installer and Midori browser launchers are part of the live desktop acceptance
  surface;
- importing host/user E state is opt-in only with both
  `AUZIX_IMPORT_HOST_E_DEFAULTS=1` and `AUZIX_DEFAULTS_HOME`.

This keeps the live ISO from drifting between “right theme, wrong wallpaper,”
first-run wizard prompts, and missing module payloads.

Media boundary:

- AUZiX has two installer media targets: the non-graphical tiny net installer
  and the lean graphical installer.
- Do not turn either target into a bloated general-purpose LiveCD.
- Desktop/workstation payloads such as Office, Flatpak apps, Podman demos,
  large theme packs, screenshots, media tools, and IDEs are installed from the
  AUZiX repository through package groups after the base install.
- The graphical ISO may be filmable, but it should stay installer-shaped:
  E/LightDM/X, installer, Midori/browser start pages, rescue terminal, file
  manager, network/SSH, and enough debug tooling to recover.
