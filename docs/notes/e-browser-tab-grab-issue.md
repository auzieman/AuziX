# AUZiX E browser tab/window-placement grab issue

Observed on the ESXi live desktop while testing Midori/Firefox-like browser flows:
E can appear to lock into a window placement / move / modal grab state, most often
when interacting with browser tabs or tab/window drag gestures. Keyboard input and
click focus may feel captured until the session is reset or the grab releases.

Working hypothesis:
- browser tab dragging and Xdnd can trigger active pointer grabs;
- AUZiX's current ESXi/Xorg/E safe-mode stack may miss a ButtonRelease or focus
  release path;
- E then remains in a move/place/modal state rather than returning input to the
  desktop normally.

Evidence to capture next time it happens:
- `/Users/auzix/.e-log.log`
- `/Users/auzix/.xsession-errors`
- `/System/Logs/display/start-e.log`
- `xinput list` and, if available, `xinput test-xi2 --root`
- `xev -event button -event motion -event keyboard`
- current E config values for `window_placement_policy`, focus policy, desklock,
  and any pointer/grab settings.

Likely AUZiX-side fixes to evaluate:
- ensure xinput/xev/xprop/xwininfo are present in the live/debug package set;
- compare ESXi Xorg input driver and vmware/vmmouse/libinput state against Trixie;
- default E to non-manual/smart placement and conservative focus policy;
- avoid stale copied E config that enables fragile placement behavior;
- add an emergency desktop shortcut/keybinding that runs `enlightenment_remote -restart`
  or cleanly restarts the session.
