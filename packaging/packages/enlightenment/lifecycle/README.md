# Enlightenment lifecycle adaptation (AX-001)

Reviewed donor: Enlightenment 0.27.1-1, Moon r5 archive SHA256
967d98217ec4d2b64ca5dbe89b22866a95b1af1f8f1c2e46e9e245166e9da671.
The retained Debian postinst only registers enlightenment_start as the
x-window-manager alternative, priority 80, with a manpage slave. prerm removes
that registration on remove/upgrade/failed-upgrade.

AuziX's existing start-e helpers in scripts/add-auzix-live-tools.sh select
Enlightenment's command directly. There is no dpkg alternatives database to
maintain. These two scripts therefore have no applicable side effect here;
they must not run unadapted or select another window manager during upgrades.
This adapter does not change startup, launch arguments, user profiles or menus.

Keep sysactions.conf and system.conf as package configuration through the
existing configuration installer. Commands, modules and helpers remain in the
pinned package payload. Package installation and fresh graphical boot are
separate validation requirements.
