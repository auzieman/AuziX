# VM135 netboot rescue/display spine — 2026-08-14

Current good-enough control-plane state after treating netboot as the rescue rail:

- VM135 is reachable over SSH at `192.168.1.198` as `root`.
- LightDM launches Xorg from `/System/Compatibility/bin/Xorg`.
- LightDM autologin starts `/System/Tools/lightdm-auzix-session`.
- The wrapper creates `/run/user/1000` and starts `dbus-daemon --session` on `unix:path=/run/user/1000/bus` if no bus exists.
- This avoids the broken `dbus-launch` path, which currently hits a `GLIBC_PRIVATE` symbol mismatch through `/Programs/DBUSX11`.
- Enlightenment reached `MAIN LOOP AT LAST` on VM135 after wrapper redeploy.

Validation receipt:

```text
processes: lightdm, Xorg, lightdm session-child, enlightenment
session bus: /run/user/1000/bus socket owned auzix:auzix
E log: ESTART ... MAIN LOOP AT LAST
```

If VM135 regresses, boot netboot/rescue, mount the installed disk, and verify this exact spine before touching apps:

1. `/System/Tools/lightdm-auzix-session` exists, is executable, and contains direct `dbus-daemon` session-bus creation.
2. `/System/Settings/lightdm/lightdm.conf` uses `autologin-session=enlightenment-auzix` and `session-wrapper=/System/Tools/lightdm-auzix-session`.
3. `/run/user/1000` is recreated as `auzix:auzix` with mode `0700` at display start.
4. `/tmp` and `/tmp/.X11-unix` are mode `1777`.
5. E logs reach `MAIN LOOP AT LAST` before moving on to menu/app cleanup.

Do not rerun broad desktop repair scripts until the above spine is checked.
