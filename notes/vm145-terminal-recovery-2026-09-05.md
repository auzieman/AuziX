# VM145 reference recovery — September 5

Preserve the near-complete reference desktop; do not replace its startup
sequence while repairing the package-derived successor. Screenshots
`shot-2026-09-05_10-48-34.jpg` and `shot-2026-09-05_10-53-21.jpg` show the
required menu/desktop and browser/installer first-boot state.

VM145 original scsi0 was started without disk/config replacement. Its current
DHCP address is 192.168.1.58, not the recorded .57. Root SSH from R730 works;
serial through PVE works. The earlier SSH failure was an obsolete address.

Only persisted shell history found under /Users, /root and /Work was the
auzix .ash_history (Glances, Python, Flatpak, office and APK probes). Earlier
automated shell commands are not thereby recovered; Git and launch-probes
logs remain necessary evidence.

Live terminal failure: /dev/ptmx correctly linked to pts/ptmx, but its target
was 0660 root:root. Test as auzix confirmed not writable. Applied only
`chmod 0666 /dev/pts/ptmx`, the existing intended mode. Then launched the
existing /System/Tools/launch-auzix-terminal as auzix with DISPLAY=:0.
Terminology PID16084, child sh PID16094 and /dev/pts/0 owned by auzix appeared
and persisted. Operator keyboard/color/resize confirmation is pending.

Log: /Users/auzix/.cache/launch-probes/terminal-recovery-20260905.log.
Efreet emitted SO_REUSEPORT Operation not supported, but Terminology and its
shell remained alive. Do not infer a terminal crash from that warning alone.
StartSequence already sets ptmx mode after mdev; the later source of the
observed 0660 reset is not yet established. Current ServiceRuntime and terminal
session generators also contain permission fixes: verify their activation and
ordering before adding another competing repair.

Pending image is NOT yet proven equivalent. Reference container selects
Enlightenment0.27.1-1 with RootFS helpers; candidate selects0.25.4-2 without
enlightenment_system in inspected Programs/Libraries/System trees. Preserve
the valid HDD module guard; reconcile selected package contents first.
Terminology Default.eet is present in both images. User-specific EET profile
provisioning remains in image staging; do not assume every historical fix is
already packaged merely because a package name exists.
