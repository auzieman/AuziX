# AX-012 — D-Bus source-to-intake trace result

BKC a65166d4-4c52-42d9-9458-362b0211f0dd completed the audit at
2026-09-05 21:58:47 UTC. Source commit 1586c2bec8e2524733e1514606d4240c5498fd8c.
Output `/var/lib/auzix-build/package-proof/AX-012-source-1586c2bec8e2` on R730.
Audit completion is NOT D-Bus installation acceptance; normalization remains
needs-review. No hooks were executed, no source compilation or fresh binary
intake download was performed, and no image/repository was changed.

Pulled dbus_1.16.2-2.dsc plus listed source components from Debian's pool and
verified component lengths/SHA256 against the descriptor. dpkg-source unpacked
the upstream tarball and Debian packaging and applied its two patches. It
warned that the inline descriptor signature could not be verified: no acceptable
signature found. Do not describe checksum validation as signature verification.
Downloads, download-sha256.json and dpkg-source.log are retained in output.

Trace:

1. `source/debian/rules:257–260` runs dh_installinit and dh_installsystemd with
   --no-stop-on-upgrade and --no-restart-after-upgrade for dbus.
2. `source/debian/dbus.postinst` contains the handwritten permission/reload
   logic and #DEBHELPER# insertion point. source-to-binary-postinst.diff shows
   that the retained binary control script replaces that marker with generated
   SysV/systemd START and daemon-reload blocks, not a forced restart. The rest
   of this postinst matches the source in the inspected diff.
3. Actual AuziX intake uses apt-get download, dpkg-deb -x and -e. It retains
   generated scripts as metadata and applies selected text/launcher rewrites;
   it neither executes debian/rules nor treats extracting a .deb as installing
   it. This audit reran normalization on the checksum-verified retained archive,
   not a recompile or new .deb intake execution.
4. The regular launch helper is still root:root 0755 in the retained payload.
   Source postinst requires root:messagebus 4754, respecting statoverride. That
   actual installation effect has not happened at payload extraction time.
5. Fresh normalization recognizes generated-service-scaffold and root guards,
   but its executable operation list contains only install-configuration for
   default/dbus and init.d/dbus. It leaves permissions, service helpers and
   triggers unresolved and correctly refuses package promotion.

Conclusion: source-to-binary helper expansion was NOT lost here. Recognition
has not become AuziX execution. Required mechanism: ordered service-account
provider (dbus-system-bus-common), protected helper ownership/mode, translated
service configuration/activation, and reload triggers that retain Debian's
explicit no-restart-on-upgrade policy. Use the already-retained instructions,
not a new generic restart script. Source and normalized files are kept so the
next repair can be tested against this precise example.
