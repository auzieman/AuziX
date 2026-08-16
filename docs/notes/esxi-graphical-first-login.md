# ESXi graphical first-login notes

The ESXi live ISO reached X/E reliably with the themefix build. User testing showed
GL compositing can be enabled without an immediate crash, so the current blanket
software/GL masking policy is probably too conservative for the ESXi/vmwgfx path.

Remaining first-login rough edge:
- E's initial dialog / first-run state can appear on a blank screen-one layout,
  while the usable display is elsewhere or not clearly selected.
- This looks more like RandR / multi-output default selection than a full E crash.

Follow-up:
- keep conservative software mode as fallback;
- add ESXi/vmwgfx profile that allows GL compositing;
- seed a one-screen RandR/default profile for live ISO first boot;
- avoid forcing Terminology to use Enlightenment theme EDJ files.
