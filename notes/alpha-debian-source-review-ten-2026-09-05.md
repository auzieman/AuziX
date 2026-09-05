# AX-012 — ten held packages against exact Debian packaging sources

Requested review only; no package, factory, image or VM repairs performed.
Method: read matching-version Debian source packaging archives directly from
deb.debian.org in memory; compare their debian/ scripts, rules and manifests
with retained binary control originals, rendered hooks and payload headers from
full run 47c4d380-2c51-4af3-86a2-3f9871308159. Nine source packages cover ten
binary packages (D-Bus supplies two). No apt installation or compilation.
Source archive hashes below identify fetched bytes; this review did not verify
Debian source signatures. Original package input hashes were verified by the run.

## Findings and bounded adaptations

1. **DBus 1.16.2-2 — real install effect, not just service boilerplate.**
   debian/dbus.postinst assigns the launch helper root:messagebus mode 4754 via
   dpkg-statoverride; triggers reload configuration, explicitly avoiding a system
   bus restart on upgrade. Retained payload helper is root:root 0755. That is a
   concrete install-time delta that archive extraction alone cannot supply.
   Adapt owner/mode while respecting local overrides, after account creation;
   map service activation and reload semantics without restarting the live bus.
   Do not blindly enable setuid without matching ownership and helper-path checks.
   Source dbus.install and dbus.triggers also reviewed.

2. **DBusSystemBusCommon 1.16.2-2 — generic service account.**
   Source postinst uses systemd-sysusers dbus.conf, otherwise adduser --system
   --group messagebus; DPKG_ROOT guards the destination root. The sysusers asset
   is present in our payload. AuziX already seeds messagebus in the HDD builder
   and several bootstrap scripts (stage-auzix-alpha-hdd-root.sh:335 onward).
   Reconcile this existing logic with a generic package-owned service-account
   operation; do not create a new hard-coded UID policy or mistake it for the
   deployment user auzix. Fresh package installation must not require HDD seeding.

3. **Flatpak 1.16.6-1~deb13u2 — retained setup assets need activation.**
   Source postinst creates _flatpak and runs remote-list --system to initialize
   the system repository. Source install manifest includes Xsession/profile
   exports, sysusers/tmpfiles, D-Bus services and policy, Polkit assets and helper
   executables. Our payload contains 20flatpak, sysusers.d/flatpak.conf and
   tmpfiles.d/flatpak.conf. Generated control scripts add tmpfiles/migration
   handling. Adapt those generic effects and activate export paths in the
   session; merely installing /usr/bin/flatpak is insufficient. Flathub and demo
   apps remain image provisioning, not Debian package defaults. Existing
   activate-auzix-basic-config.sh:401 contains bootstrap work to reconcile.

4. **X11Common 1:7.7+24+deb13u1 — known boot setup, already shipped.**
   Source x11-common.init creates BOTH .X11-unix and .ICE-unix under /tmp,
   root:root 01777, with symlink/type checks. Source postinst's debconf action
   is db_purge (old question cleanup), not a requirement to invent configuration.
   Binary debhelper inserts service activation. The init script, Xsession and
   its fragments are all present in our payload. Historical add-auzix-live-tools
   repairs create/chmod .X11-unix; compare and consolidate the complete socket
   setup into the existing boot owner. Do not rewrite E startup to solve this.

5. **XdgUserDirs 0.18-2 — specific factory matcher defect.**
   debian/maintscript contains rm_conffile for the old
   /etc/X11/Xsession.d/60xdg-user-dirs-update WITHOUT a prior-version argument.
   Generated binary hooks retain that valid form in four stages. Our
   RM_CONFFILE_LINE requires prior_version, so the already-path-mapped command
   falls through. Support the optional syntax; separately decide fresh-install
   no-op versus upgrade migration with user-modification preservation. Do not
   delete user directory preferences or replay a guessed version condition.

6. **Bubblewrap 0.12.0-1~deb13u1 — kernel policy, not absent executable.**
   Source ships 50-bubblewrap.conf enabling kernel.unprivileged_userns_clone
   for older Debian kernels; postinst applies that specific sysctl if available.
   Our payload contains the file and rendered hook preserves the conditional.
   This is a policy/activation review hold, not evidence bwrap needs rebuilding.
   Preserve the asset and apply appropriate target-kernel policy during VM boot;
   do not change a container host's sysctl from package validation or silently
   substitute setuid as a workaround. Validate an actual unprivileged sandbox.

7. **Appstream 1.0.5-1 — cache operation and legacy migration differ.**
   Source postinst refreshes OS metadata cache on triggers, forces initial cache
   refresh and separately cleans pre-0.15.2 app-info caches on upgrade. Triggers
   watch /usr/share/app-info/{icons,yaml,xml}. Our remaining flags are the trigger
   surface and dpkg version logic. Map cache registration to the actual published
   metadata paths; retain conditional historical cleanup separately. No reason
   found here for a compile or broader application dependency expansion.

8. **LibcBin 2.41-12+deb13u3 — NSS defaults and loader cache.**
   Source debhelper.in/libc-bin.postinst installs nsswitch.conf only when absent
   and invokes ldconfig in the target root. interest-await ldconfig is explained
   by upstream packaging as necessary for nonstandard library search paths.
   Our default payload exists; rendered code still has
   $DPKG_ROOT/usr/share/libc-bin/nsswitch.conf and ldconfig -r $DPKG_ROOT/.
   Reconcile existing AuziX NSS seeding and loader/publication policy; translating
   the destination alone is insufficient. Do not erase the cache effect merely
   because many libraries already publish links into /Libraries.

9. **Ntfs3g 1:2022.10.3-5+deb13u2 — image/initramfs integration.**
   Source debian/rules explicitly installs an initramfs hook and local-premount/
   local-bottom scripts; all three exist in our payload. The held trigger is
   activate-noawait update-initramfs. Route it to the actual image/initramfs
   builder when that integration is needed, not a running package-factory host.
   Source rules also document build flags and setuid installation; the trigger
   hold alone does not prove those build details are wrong. No mount test done.

10. **XMLCore 0.19 — confirmed syntax regression in our transformation.**
    Source postrm has an outer purge block and an inner if with then on its own
    line. Debian rules additionally invoke dh_installcatalogs and a bundled
    dh_installxmlcatalogs generator. Retained donor postrm passes sh -n; our
    rendered after-remove fails at line32 with an unmatched fi. Inspection of
    _prune_unreachable_purge_blocks shows nesting only increments for inline
    if ... then, so it stops at the inner fi. Fix the transformation with this
    exact fixture before considering XML cache/catalog/path flags resolved.

## Source identity (Debian pool archive links)

- [dbus 1.16.2-2](https://deb.debian.org/debian/pool/main/d/dbus/dbus_1.16.2-2.debian.tar.xz): f774fe3bd1ac24265e17c70999bfa26a92a15f2fb72e1fb8c64fa5d436fb9119
- [flatpak 1.16.6-1~deb13u2](https://deb.debian.org/debian/pool/main/f/flatpak/flatpak_1.16.6-1~deb13u2.debian.tar.xz): bac37dc8430afe688734263f7efecb8a9bfff6098011d24a1647b2f09c99d790
- [bubblewrap 0.12.0-1~deb13u1](https://deb.debian.org/debian/pool/main/b/bubblewrap/bubblewrap_0.12.0-1~deb13u1.debian.tar.xz): 7b54f121aebf5d4b38360ea728274c26fa471582bc3e6658379b679ecd8b5a2f
- [appstream 1.0.5-1](https://deb.debian.org/debian/pool/main/a/appstream/appstream_1.0.5-1.debian.tar.xz): d5bd321ae8203d59d803b2bf002ab2236904757bd9bae26e4a9baf94c5355d18
- [glibc 2.41-12+deb13u3](https://deb.debian.org/debian/pool/main/g/glibc/glibc_2.41-12+deb13u3.debian.tar.xz): de7d715bf7e559b78baebac4115122641842f65faf0a5080a55954877a55cebe
- [ntfs-3g 2022.10.3-5+deb13u2](https://deb.debian.org/debian/pool/main/n/ntfs-3g/ntfs-3g_2022.10.3-5+deb13u2.debian.tar.xz): 28d777aaac07b4e14e4cefae52227e9fa490f0ce28b2988913961158cac50b42
- [xorg 7.7+24+deb13u1](https://deb.debian.org/debian/pool/main/x/xorg/xorg_7.7+24+deb13u1.tar.xz): e08f0221d87683d1caa73fc07788c95aa81b2c86842ff1b55b6f24dfd378659a
- [xml-core 0.19](https://deb.debian.org/debian/pool/main/x/xml-core/xml-core_0.19.tar.xz): 7083d7d3fa7ad7b5da710f90df3045bab6544faa0a6da6c5501b9430c51670d4
- [xdg-user-dirs 0.18-2](https://deb.debian.org/debian/pool/main/x/xdg-user-dirs/xdg-user-dirs_0.18-2.debian.tar.xz): 910ffd004e4e64fcc3a3f51c46ed396ed48b7f9c831750e11411142053d9249b

## Review conclusion

The sample supports metadata/activation repair, not recompilation. Two concrete
normalizer defects are distinguished from real service/account/cache effects,
and from boot-time kernel/initramfs policy. Source assets often already survived
intake. Existing image repairs must be reconciled into the appropriate generic
package or boot owner. No live runtime acceptance is claimed and none of the
ten holds is marked fixed by this review.
