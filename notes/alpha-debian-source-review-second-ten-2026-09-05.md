# AX-012 — second ten Debian source comparisons, before BML

Review only, requested by operator; no factory/package/VM changes. Read matching
source packaging archives from Debian's pool in memory, retained binary control
scripts and payload headers from full run 47c4d380-2c51-4af3-86a2-3f9871308159,
and existing local intake code. Source SHA256 values identify downloaded bytes;
source signatures were not verified. Binary Bash +b9 maps to source 5.2.37-2,
and Polkitd's Source field is policykit-1, not polkit. These identities were read
from retained debian-control.txt, not guessed for final comparison.

## Ten additional holds

1. **Bluez 5.82-1.1.** Source bluez.preinst creates /var/lib/bluetooth mode700;
   postinst creates the bluetooth group if absent and reloads D-Bus. Its
   maintscript has both rm_conffile and mv_conffile historical migrations.
   bluez.install includes daemon, D-Bus policy/activation, udev rules and
   system/user service units; bluetooth.service is present in retained payload.
   Existing service/account operations apply, but migration histories and
   protected state-directory mode must not be discarded with Debian helpers.

2. **Polkitd 126-2 (policykit-1).** Source polkitd.postinst explicitly avoids
   automatic sysusers sequencing so that it can create the account, reload
   D-Bus, then restart/re-activate Polkit. It applies root:polkitd 0750 to local
   rules and root:root 4755 to polkit-agent-helper-1 while respecting admin
   permission overrides. The retained regular helper is 0755; two 0777 entries
   are symlinks, not writable regular helpers. Source also preserves modified
   PAM config during migration and documents non-systemd D-Bus activation.
   Requires ordered account → permissions/policy → bus reload → activation;
   not independent unordered hooks or a blanket setuid operation.

3. **Fprintd 1.94.5-2.** Source has no bespoke fprintd.postinst in the inspected
   packaging; the retained one consists of generated conffile migration and
   systemd activation blocks. Source fprintd.install and rules supply D-Bus,
   Polkit, executable and system service assets. fprintd.service is retained.
   Adapt the service intent from these assets; no bespoke daemon repair is
   indicated. Source enables PAM but libpam-fprintd is a separate package;
   do not conflate daemon acceptance with enrollment/PAM hardware validation.

4. **Bash 5.2.37-2+b9, source 5.2.37-2.** Source postinst only adds /bin/sh if
   missing and registers a builtins manpage alternative. Generated binary
   script adds conditional update-menus guarded by command availability and
   DPKG_ROOT. Our hold is mainly guards/menu update and /bin/sh, not the shell
   implementation. Keep AuziX's selected default shell and transitional link;
   classify documentation/legacy Debian menu operations explicitly rather than
   interpreting this as permission to replace a working shell or E menu tree.

5. **Gzip 1.13-1.** Source preinst/postinst primarily reconcile zutils dpkg
   diversions during Debian's /usr merge. This is a precise candidate for an
   inapplicable-on-fresh-AuziX disposition, not generalized path rewriting.
   Check prior AuziX zutils/provider collisions before omitting an upgrade
   effect. No missing executable or recompilation requirement demonstrated.

6. **LibreOfficeCommon 4:25.2.3-2+deb13u6.** Source common.maintscript uses
   symlink_to_dir for share/registry; common.preinst.in migrates older ucf
   registrations. common.postinst.in/triggers.in and shell-lib-extensions.sh
   define extension synchronization and optional lool systemplate work.
   Crucially: four AppArmor conffiles listed in retained metadata are absent
   from the archive. Local build-auzix-debian-intake-package.sh:512–513
   explicitly deletes RootFS/etc/apparmor.d for LibreOffice* after copying
   control metadata. This is a confirmed payload/metadata inconsistency.
   Restore/adapt the policies or explicitly document their exclusion with
   matching metadata; do not merely waive the missing-conffile check. Keep
   existing working Office runtime assembly and separate optional server work.

7. **Python313 3.13.5-2+deb13u4.** Source PVER.postinst.in queries the sibling
   libPVER-stdlib package, byte-compiles its .py files using the interpreter
   and py_compile.py, optionally optimized according to Debian config.
   PVER.prerm.in removes bytecode from that SAME sibling package. Retained
   hooks reproduce this, so a self-RootFS-only cleanup cannot correctly replace
   them. Need explicit related-package ownership resolution plus interpreter/
   compiler paths from the working split layout. This differs from the two
   library hooks fixed in the pilot; preserve that distinction in sub-config.

8. **Librsvg2Common 2.60.0+dfsg-1.** Source postinst.in intentionally requests
   the gdk-pixbuf loader trigger after configuration: unpack-time discovery can
   be too early while dependencies are unavailable. Retained SVG loader .so
   exists. Map the loader destination and owner-trigger dependency/order;
   rerun loader discovery after dependencies become usable. This is relevant
   to image/icon handling but not proof of the live screenshot cause. Source
   rules themselves use -Dauto_features=enabled, so broad options alone do not
   establish an AuziX overbuild here.

9. **Timgm6mbSoundfont 1.3-5.** Source registers default-GM.sf2 and default-GM.sf3
   alternatives, both pointing to TimGM6mb.sf2 at priority20; prerm removes
   only this provider and tries empty-directory cleanup. Retained soundfont
   payload exists. Need provider-aware data aliases with removal/fallback
   ownership, not dropping update-alternatives or permanently forcing one
   global symlink. Shared with executable providers but not limited to binaries.

10. **SgmlBase 1.31+nmu1.** Source postinst migrates legacy catalogs, invokes
    update-catalog --update-super, and links the system catalog to generated
    state. Its triggers include a named update-sgmlcatalog event and SGML/XML
    paths. Existing holds include legacy/local paths and the trigger surface.
    Map configuration, generated state and local additions distinctly; preserve
    local catalogs while wiring a reusable catalog/cache operation. Not a
    reason to install all documentation or hard-code a replacement catalog.

## Source archives and hashes

- [bluez](https://deb.debian.org/debian/pool/main/b/bluez/bluez_5.82-1.1.debian.tar.xz): dd32f06a527859709055912ac8c8a0377030f7f34d7d6a9cc7f5938ed8bac659
- [policykit-1](https://deb.debian.org/debian/pool/main/p/policykit-1/policykit-1_126-2.debian.tar.xz): 5b2b8c2b1b2e757e71fd740028be0bb3cc4cf532f826a0a8c0ea7c0ea1d4cfcc
- [fprintd](https://deb.debian.org/debian/pool/main/f/fprintd/fprintd_1.94.5-2.debian.tar.xz): bd16c2d5d4ef27bd364c8268331564d6ffaac68248762e790f0c53976b20db0f
- [bash](https://deb.debian.org/debian/pool/main/b/bash/bash_5.2.37-2.debian.tar.xz): 42e03ef523258b61fa765b8c9719d7bf461f2a274260d07fbe45ca7e4627923a
- [gzip](https://deb.debian.org/debian/pool/main/g/gzip/gzip_1.13-1.debian.tar.xz): 29319b3f91d8e03d940d4d7c0f2a5fe5ec4f2ba4a0e621c9ef2682f2d0240dd2
- [libreoffice](https://deb.debian.org/debian/pool/main/libr/libreoffice/libreoffice_25.2.3-2+deb13u6.debian.tar.xz): b99aae9085fc5c846e69dd695e2514644f8dcbc7638c7989a7416d0dac19e12f
- [python3.13](https://deb.debian.org/debian/pool/main/p/python3.13/python3.13_3.13.5-2+deb13u4.debian.tar.xz): b5cc42821fb6a6f91b7a5ac1da5b313bb251288ca03f03d683b4c6ca453ece11
- [librsvg](https://deb.debian.org/debian/pool/main/libr/librsvg/librsvg_2.60.0+dfsg-1.debian.tar.xz): 58db12d59958016e3b114de74ebe137255da9a900593f0a9d5b3392709a7cbe7
- [timgm6mb-soundfont](https://deb.debian.org/debian/pool/main/t/timgm6mb-soundfont/timgm6mb-soundfont_1.3-5.debian.tar.xz): 993893c5b6265a3f7972a38d055d450d08873d097a2a2c41b010bd1858cc068c
- [sgml-base](https://deb.debian.org/debian/pool/main/s/sgml-base/sgml-base_1.31+nmu1.tar.xz): 288734750a822c7e5d8bf46136891ee6d60193376e8abe02e142287fd4bb8115

## Additional BML inputs — not implementation yet

- Ordered cross-package effects: account/policy/bus activation, sibling Python
  payloads, and loader caches after dependency configuration.
- Intentional payload exclusions must update metadata with an explicit reason.
- Provider selection includes data aliases and removal fallback, not just PATH.
- Distinguish generated debhelper behavior from handwritten source hooks and
  from genuinely inapplicable historical Debian migrations.

Twenty of the 36 held packages now have source reviews across the two notes.
No reviewed hold has been marked repaired; no build was started by this review.
