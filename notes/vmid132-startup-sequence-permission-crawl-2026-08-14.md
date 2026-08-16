# VMID132 startup sequence and permission crawl — 2026-08-14

Purpose: stop guessing at the AUZiX desktop/session state. VMID132 is the
working Debian/Trixie guidebook; AUZiX should preserve the same package
semantics with AUZiX path values.

Captured evidence:

- `out/vmid132-startup-crawl/vmid132-startup-core.txt`
- `out/vmid132-startup-crawl/vmid132-maintainer-spine.txt`
- `out/vmid132-startup-crawl/vmid132-unit-x11-permissions.txt`
- `out/vmid132-startup-crawl/vmid132-package-xsession-state.txt`

## First-order findings

1. Trixie boots a service graph, not a desktop command.

   Default target is `graphical.target`. The display stack comes after
   `basic.target`, `multi-user.target`, DBus, logind, user-sessions,
   console setup, and related sockets/runtime directories.

2. LightDM package lifecycle creates required identity/state.

   `lightdm.postinst` does the real work:

   - creates group `lightdm`;
   - creates system user `lightdm`;
   - sets home to `/var/lib/lightdm`;
   - sets shell to `/bin/false`;
   - creates `/var/lib/lightdm`;
   - owns it as `lightdm:lightdm`;
   - sets mode `0750`;
   - reloads DBus;
   - links `display-manager.service` to the selected display manager.

   AUZiX equivalent must be package lifecycle metadata/hook behavior, not a
   generic desktop repair script.

3. LightDM greeter registration is an alternatives action.

   `lightdm-gtk-greeter.postinst` runs:

   - `update-alternatives --install /usr/share/xgreeters/lightdm-greeter.desktop ...`

   AUZiX needs an alternatives-equivalent lifecycle surface or a declared fixed
   mapping for `/System/Compatibility/usr/share/xgreeters/lightdm-greeter.desktop`.

4. DBus has trigger/reload/start semantics.

   Debian `dbus.postinst` handles triggered config reloads, updates init/systemd
   state, and starts/reloads the daemon where appropriate. AUZiX should capture
   this as DBus lifecycle, including:

   - system bus user/group `messagebus`;
   - `/run/dbus`;
   - `/var/lib/dbus`;
   - machine-id placement;
   - reload of DBus config after packages install system services/policies.

5. X session setup is a chain of sourced scripts.

   Relevant Trixie files include:

   - `/etc/X11/Xsession`
   - `/etc/X11/Xsession.options`
   - `/etc/X11/Xsession.d/20dbus_xdg-runtime`
   - `/etc/X11/Xsession.d/35x11-common_xhost-local`
   - `/etc/X11/Xsession.d/50x11-common_determine-startup`
   - `/etc/X11/Xsession.d/75dbus_dbus-launch`
   - `/etc/X11/Xsession.d/95dbus_update-activation-env`

   The important session behavior is:

   - if `XDG_RUNTIME_DIR=/run/user/<uid>` and `$XDG_RUNTIME_DIR/bus` exists,
     export `DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus`;
   - otherwise, if configured, launch a session bus with
     `dbus-launch --exit-with-session`;
   - propagate `DISPLAY`, `XAUTHORITY`, `XDG_CURRENT_DESKTOP`, and bus address
     into DBus activation/systemd-user environment;
   - choose startup through session manager/window manager alternatives when no
     explicit startup is passed.

6. Enlightenment depends on more than its binary.

   Debian package state shows Enlightenment depends on a session DBus provider,
   `enlightenment-data`, `libefreet-bin`, EFL module trees, PAM, PulseAudio,
   xkbcommon, and many EFL runtime libraries. Its module tree is extensive under
   `/usr/lib/x86_64-linux-gnu/enlightenment/modules`.

   AUZiX must expose equivalent module paths and Efreet/cache ownership through
   package runtime ladders and lifecycle hooks before menu/app launch is trusted.

7. Desktop caches are package-trigger surfaces.

   Trixie has concrete cache/state files:

   - `/usr/share/applications/mimeinfo.cache`
   - `/usr/share/mime/mime.cache`
   - `/usr/share/glib-2.0/schemas/gschemas.compiled`
   - `/usr/share/icons/hicolor/icon-theme.cache`

   AUZiX should not “repair menus” globally. Packages that add desktop files,
   MIME data, icons, schemas, DBus services, or Polkit policy must declare the
   matching trigger surfaces.

8. `dpkg-query -S` distinguishes payload ownership from generated state.

   Trixie key path owner check:

   ```text
   /etc/xdg/menus/mate-applications.menu              mate-menus
   /usr/share/xsessions/enlightenment.desktop         enlightenment-data
   /etc/X11/Xsession                                  x11-common
   /etc/X11/Xsession.d/20dbus_xdg-runtime             dbus-user-session
   /etc/X11/Xsession.d/75dbus_dbus-launch             dbus-x11
   /usr/bin/update-desktop-database                   desktop-file-utils
   /usr/bin/update-mime-database                      shared-mime-info
   /usr/bin/glib-compile-schemas                      libglib2.0-bin
   /usr/bin/gtk-update-icon-cache                     gtk-update-icon-cache
   /usr/bin/efreetd                                   libefreet-bin
   /usr/share/applications/mimeinfo.cache             generated/unowned
   /usr/share/mime/mime.cache                         generated/unowned
   /usr/share/glib-2.0/schemas/gschemas.compiled      generated/unowned
   /usr/share/icons/hicolor/icon-theme.cache          generated/unowned
   ```

   AUZiX must not search for generated cache files in payloads. It must run the
   equivalent package lifecycle trigger during install/setup and record the
   generated path as lifecycle output.

## AUZiX crawl order

Do this in strict tiers:

1. base mounts and root permissions;
2. users/groups/passwd/shadow/gshadow;
3. DBus system bus and machine-id;
4. system/user runtime dirs, especially `/run/user/<uid>`;
5. logind or AUZiX equivalent session contract;
6. PAM/session snippets needed by LightDM and E;
7. LightDM user/state/default display-manager/greeter mapping;
8. Xorg/input/udev device permissions;
9. Xsession environment chain;
10. Enlightenment/EFL/Efreet module and cache paths;
11. desktop cache triggers;
12. visible launchers, one proven app at a time.

No visible launcher should be promoted until its package receipt explains the
runtime ladder and its front-door probe succeeds.
