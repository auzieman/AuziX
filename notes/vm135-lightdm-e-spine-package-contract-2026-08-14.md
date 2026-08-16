# VM135 LightDM/E spine package contract — 2026-08-14

Goal gate:

- post ISO install boots from disk;
- mouse and keyboard work under X11;
- LightDM starts;
- LightDM launches an Enlightenment session.

Do not promote application/menu work until this gate is green after hard boot.

## Trixie oracle

VM132 shows the working process chain:

```text
/usr/sbin/lightdm
/usr/lib/xorg/Xorg :0 ...
lightdm --session-child ...
/usr/lib/systemd/systemd --user
/usr/bin/dbus-daemon --session --address=systemd: ...
/usr/bin/enlightenment_start
/usr/bin/ssh-agent /usr/bin/enlightenment_start
/usr/bin/enlightenment
/usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_system
/usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_fm
```

Trixie package facts:

- `enlightenment` depends on `default-dbus-session-bus | dbus-session-bus`;
- `/usr/bin/enlightenment_start` is owned by `enlightenment`;
- `/usr/share/xsessions/enlightenment.desktop` is owned by `enlightenment-data`;
- `/etc/X11/Xsession.d/20dbus_xdg-runtime` is owned by `dbus-user-session`;
- `/etc/X11/Xsession.d/75dbus_dbus-launch` and `/usr/bin/dbus-launch` are owned by `dbus-x11`;
- `/run/user/1000` and `/run/user/1000/bus` are generated runtime state.

## AUZiX failure found

VM135 got LightDM and Xorg running, and Xorg detected keyboard/tablet/mouse through
udev/libinput. The failure was user session launch:

```text
Session pid=... Running command /System/Tools/lightdm-auzix-session /System/Tools/start-enlightenment-session
Session pid=... Exited with return value 127
/Programs/DBUSX11/current/RootFS/usr/bin/dbus-launch: symbol lookup error:
/System/Compatibility/usr/lib/x86_64-linux-gnu/libc.so.6: undefined symbol:
__tunable_is_initialized, version GLIBC_PRIVATE
```

This means the E package was allowed to pass without a valid DBus session bus
provider, despite Debian declaring that as a runtime dependency.

## Source corrections started

- `scripts/build-auzix-dbus-package.sh`
  - exports `dbus-launch` in both `/System/Compatibility/bin` and
    `/System/Compatibility/usr/bin`;
  - records `dbus-session-bus` as provided capability;
  - adds `dbus-daemon --version` and `dbus-launch --version` validation.

- `scripts/build-auzix-host-enlightenment-package.sh`
  - records DBus/session-bus dependency explicitly;
  - adds validation that a DBus session bus path exists before E is considered
    launchable.

- `scripts/stage-auzix-display-templates.sh`
  - creates `/System/Tools/lightdm-auzix-session`;
  - uses the AUZiX LightDM wrapper for autologin;
  - if no session bus exists, starts `dbus-daemon --session` at
    `/run/user/1000/bus` and writes session diagnostics to
    `/Users/auzix/.xsession-errors`, not the LightDM daemon log.

## Next run order

1. Rebuild DBus package from the corrected script.
2. Rebuild/publish Enlightenment package from the corrected script.
3. Install those on VM135.
4. Hard boot VM135 from disk.
5. Verify process chain and logs:
   - `lightdm`;
   - `Xorg`;
   - `dbus-daemon --session` or equivalent `/run/user/1000/bus`;
   - `enlightenment_start`;
   - `enlightenment`;
   - Xorg input lines for QEMU USB Tablet, AT keyboard, and VMMouse.

