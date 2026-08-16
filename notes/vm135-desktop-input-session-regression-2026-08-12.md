# VM135 desktop input/session regression checkpoint - 2026-08-12

What regressed after the large userspace/Flatpak package wave:

- LightDM rebooted into greeter/unknown-session mode because package-generated templates still used
  `/System/Tools/lightdm-session-wrapper` and did not preserve the AUZiX autologin rescue path.
- Xorg relied on udev/logind auto-add for input devices, but the current AUZiX service layer does not yet
  provide a reliable udev/logind seat. Result: X painted/E started, but mouse and keyboard were dead.
- E had saved display/session state under `/Users/auzix/.e/e/config/standard/e_randr2.cfg` after a wide-mode
  test and could appear locked even when X was alive.
- Efreet can generate runaway temp logs if menu/indexing loops while the desktop package set is changing.

Durable source fixes made:

- `scripts/build-auzix-lightdm-package.sh`
  - LightDM templates now use `/System/Tools/lightdm-auzix-session`.
- `scripts/build-auzix-host-xorg-package.sh`
  - Generated `xorg.conf` now includes explicit evdev rescue devices:
    - keyboard `/dev/input/event0`
    - QEMU USB tablet `/dev/input/event3`
    - PS/2 mouse `/dev/input/event2`
  - This keeps VM input working while udev/logind integration matures.
- `scripts/build-auzix-access-package.sh` and `scripts/add-auzix-live-tools.sh`
  - `lightdm` is included in `input`, `video`, and `render` groups.

VM135 proof commands:

```sh
ssh root@192.168.1.198 '/Programs/BusyBox/current/Commands/busybox grep -Ei "AuzixKeyboard|AuzixPointer|AuzixMouse|evdev" /System/Logs/display/Xorg-lightdm.log | tail -80'
ssh root@192.168.1.198 '/Programs/BusyBox/current/Commands/busybox ps | /Programs/BusyBox/current/Commands/busybox grep -Ei "lightdm|Xorg|enlightenment" | /Programs/BusyBox/current/Commands/busybox grep -v grep'
ssh root@192.168.1.198 'DISPLAY=:0 XAUTHORITY=/run/lightdm/root/:0 /System/Compatibility/bin/xrandr --current | head -20'
```

Current VM135 rescue state:

- Xorg explicitly loads `evdev` and adds `AuzixKeyboard0`, `AuzixPointer0`, and `AuzixMouse0`.
- LightDM autologin uses `/System/Tools/lightdm-auzix-session`.
- Current display mode is `1920x1080`.
- Disk was safe after rescue, roughly 3.4G free.
