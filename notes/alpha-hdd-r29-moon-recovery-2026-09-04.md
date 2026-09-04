# Alpha HDD r29 Moon recovery — 2026-09-04

## Scope

Continue from the mostly working VM143/r28 HDD lineage. Do not widen the
workstation package set or replace the proven userspace while closing its
runtime tail.

## Immutable inputs

- userspace image: `auzix/alpha:pre-hdd-final-20260901-r28`
- image id: `sha256:dd7c329eb1700a22511fc8c22e67281a72d5b01d80c0d351122b7ac85177ca53`
- boot anchor: `/mnt/ns1/AuziX/src/artifacts/auzix/auzix-live-theme-app-candidate.iso`
- anchor SHA-256: `dbc37d309059b70cc39e37b7a5e0be7d27dae770654bf3ccf7ddf7d142c25cb6`
- kernel: `6.1.0-48-amd64`

## Builder corrections

Host-side staging followed absolute AUZiX links such as
`/Programs/Libevas1/current` outside the staged root. The package was present;
the validation path was wrong. Commit `1ea3256` resolves `current` links inside
the output root. Commit `41dadb0` applies the same rule to `/Libraries` runtime
links. Commit `6a42183` completes the current EFL module overlay for Emotion and
Efreet and removes the remaining v1.26 module directories.

These are HDD image-builder fixes. They do not alter package payloads or add
application scope.

## Artifact

- run: `20260904-r29-moon-r4`
- image: `artifacts/auzix/auzix-alpha-20260904-r29-moon-r4.img`
- size: 8 GiB raw, approximately 3.1 GiB allocated before transfer
- build result: PASS, including core-runtime, ownership, installed-root,
  finalizer, and BIOS GRUB gates

The image is staged through ns1 for import into a new VM144. VM143 remains the
r28 control and must not be overwritten.

## Remaining exception owners

VM143 read-only smoke proved SSH configuration, adduser/Perl, Python imports,
AbiWord, Midori, Terminology, Flatpak executable, theme, wallpaper, and desktop
entries. Remaining defects must loop back to their owning inputs:

1. `su` aborts and its public path resolves through the current UtilLinux
   command surface. Repair belongs in UtilLinux package intake/activation and
   must be validated as an executable public command, not hotfixed in a VM.
2. `lowriter --help` aborts with a UNO `DeploymentException`. Repair belongs in
   the LibreOffice Writer/Common wrapper contract and its per-user
   `UserInstallation` state.
3. `flatpak remotes` is empty. Flathub seeding belongs in Flatpak/workstation
   lifecycle activation; the image builder may invoke the package-owned hook
   but must not manufacture an unrelated remote configuration.

Every accepted repair must be rebuilt through its package/intake owner, fed
back into the pre-HDD image, and retained by the HDD builder. Live VM changes
are diagnostic only.

## VM144 boot validation

The r29 artifact was imported without modifying VM143 and booted as VM144:

- VM: `Auzix-Alpha-R29-144`
- address: `192.168.1.175`
- APK database: 407 installed packages
- Xorg and Enlightenment: running
- `sshd -t`: PASS
- AbiWord, Midori, and Terminology CLI probes: PASS
- Enlightenment, Terminology, Midori, installer, LibreOffice Writer, AbiWord,
  and Flatpak program trees: present
- target desktop entries: present in both compatibility and public paths

The boot reproduced the three known package/lifecycle exceptions without
introducing a broad package-set regression: `su` aborts, Writer hangs during
its CLI probe, and Flatpak has no configured remotes.

One image-provisioning exception was also confirmed: sshd is healthy and the
machine has an address, but the fresh image contains no authorized-key state,
so an external root public-key login is denied. Key seeding belongs in the HDD
provisioning input/hook and must be tested from outside the VM. It must not be
left as an unrecorded serial-console hotfix.
