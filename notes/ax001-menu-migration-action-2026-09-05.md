AX-001/AX-004 — September5 — donor menu migration repair, before action

R9 donor scripts all contain the same mv_conffile from
/etc/xdg/menus/enlightenment-applications.menu to e-applications.menu for
pre0.21.2-2 Debian installations. Reference VM145 already has the new file at
/System/Settings/xdg/menus/e-applications.menu; /etc/xdg/menus is absent.
No E binary or session rewrite follows from this failure.

Use the existing per-package intake adapter mechanism. Preserve donor conffiles;
adapt old-to-new menu migration once before installation in System/Settings.
If both files differ, fail without changing either. If old alone exists, move
it to the new name, preserving user contents. Existing new-only installations
are no-ops. No dpkg version/database assumptions or removal-time migration.
Test each state, commit, then fresh BKC R10 (R9 lacks a composed repository so
the existing consumer-resume lane cannot resume it). Preserve failed R9 proof,
R8 and VM145. Conversion and real package install remain distinct acceptance.
