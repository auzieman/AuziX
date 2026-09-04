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

Visual validation corrected two false positives from the file-only smoke test:

1. Desktop files existed, but the fresh `auzix` profile had no Efreet cache and
   the session did not run `efreetd`; the visible application menu was empty.
   A live Efreet run populated the complete desktop, utility, MIME, and icon
   caches. The session generator and HDD staging now default the already
   existing Efreet prestart hook on.
2. The Terminology desktop entry targeted
   `/System/Tools/launch-auzix-terminal`, but `apk info -L terminology` proved
   that the emitted package contained the desktop entry and binary while
   omitting that package-owned launcher. The alpha finalizer now closes the old
   package-wave gap, and validation requires both the launcher and its desktop
   mapping. The Terminology package builder already authors the launcher; its
   next APK emission must retain the entire staged package root.

After live launcher restoration, Terminology reached window/PTY creation but
`posix_openpt()` was denied. `/dev/ptmx` was a separate devtmpfs node with mode
0660 while `/dev/pts/ptmx` was the correct devpts node with mode 0666. Replacing
the public node with the conventional `pts/ptmx` symlink removed the PTY error
and launched Terminology. The boot generator and HDD staging now retain that
mapping, with validation gates preventing another file-only false pass.

The post-patch suite then passed all 16 original/runtime checks plus a real
Flatpak transaction. Flatpak initially failed Flathub setup with curl error 77.
Inspection showed its bundled `libcurl.so.4` was compiled for
`/etc/pki/tls/certs/ca-bundle.crt`; the CA package source already authors that
compatibility link, but the installed APK inventory did not retain it. Restoring
the package-owned PKI link made Flathub remote setup pass. A 183-byte local
`com.auzix.FlatpakSmoke` application was exported, installed with `--no-deps`,
queried successfully, and removed again. The validation gate now repeats that
local transaction without downloading a graphical runtime, while also requiring
the production Flathub remote.

Visual follow-up and a read-only comparison with the workable r9 HDD corrected
the remaining E diagnosis. r9 shipped no prebuilt files under the user's
`.e/e/config`; r29 injected default, standard, and profile EET state. The
applications themselves launched from E's file manager, proving this was not a
general application/dependency failure. HDD staging now retains packaged
desktop/startup entries and branded assets but leaves the per-user E config
directory empty for the current Enlightenment runtime to initialize.

Terminology also exposed one finite adjacent-package omission. Trixie's
`terminology` depends on `terminology-data`; `Default.eet` is owned by that data
package. The r29 image contained the executable and two themes but no
colorschemes. `terminology-data` is now explicit in the E/workstation group,
and both pre-HDD and alpha-final gates require its default colorscheme plus the
package-owned terminal launcher.
