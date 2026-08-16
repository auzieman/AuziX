# AUZiX Custom Autoconf

`custom-autoconf` is the live-host repair lane.

It exists because a Debian-style full reconfigure is too broad for AUZiX. We
usually do not want to replay every package script. We want to compare the live
host against known-good evidence, then apply only the relevant setup/fix
fragments for the drifted surfaces.

It advances one tier at a time. The tier model is documented in
`packages/lifecycle-fragments/tiered-desktop-convergence.md`.

Do not show desktop menu entries for packages whose front-door/runtime probes
fail. Hidden-but-installed is better than visible-and-broken.

## Inputs

- known-good reference host: vmid132 / Trixie desktop;
- target host: vmid135 / AUZiX workstation;
- farmed Debian lifecycle fragments;
- AUZiX package receipts;
- AUZiX path policy.

## Output

One of three results for each surface:

- `already-good`
- `fixed-by-fragment`
- `needs-package-bake-in`

The first two make the live desktop better now. The third feeds the rebuild or
repackage queue so the fix becomes part of the package instead of becoming
another loose shell tweak.

## First filmable target

The desktop is considered `filmable` when:

1. LightDM accepts keyboard/mouse and starts Enlightenment.
2. Terminal, file manager, menus, themes, and open-with are stable after reboot.
3. LibreOffice Calc/Writer launch; Impress/Draw either launch or have a clear
   missing-package receipt.
4. Flatpak can install and run one browser or editor.
5. Podman can show a running AUZiX nginx or busybox-derived container.
6. The host can explain its package state with `auzix-pkg status` or a generated
   receipt.

## Working rhythm

1. Collect vmid132 evidence for the tier.
2. Collect vmid135 evidence for the same tier.
3. Extract the relevant Debian maintainer-script/source-package logic.
4. Map paths and service/cache behavior into AUZiX terms.
5. Apply the smallest safe hook.
6. Probe.
7. Promote to package lifecycle metadata only after the probe is stable.
