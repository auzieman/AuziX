# Scoped release reconciliation — September 5

Planning deliverable, not a claim that the image is repaired. Supersedes the
idea of handling twelve unrelated application bugs. Scope is the installation
effects behind AX-001..012, with separate acceptance retained for each ticket.
No distro-wide rebuild, path redesign or new package manager.

## Shared evidence and correction

Debian intake already retains maintainer scripts, triggers, conffiles and
configuration metadata. Lifecycle mapping and FPM emission already exist.
Missing selection, incomplete mapping, competing publication and image-time
overrides must be distinguished; not every observed failure proves missing
intake. VM132 supplies upstream running behavior; a prepared Trixie container
can supply install-transaction effects. VM145 supplies proven AuziX adaptations.
Those comparisons remain to be captured where ticket plans explicitly say so.

Source findings in this pass:

- DesktopIntegration activate copies its generated menu over the menu path
  provided by EnlightenmentData, and rewrites user MIME defaults. Establish
  one intentional owner/preservation policy before changing either producer.
- HDD staging unconditionally copies session tools from the anchor, then
  reapplies committed user defaults. Compare both with recovered VM145 history
  and profile seed; do not assume current source session code wins.
- ServiceRuntime contains PTY fixes but its package lifecycle is empty and its
  validation checks only service-file presence. Boot activation needs tracing.
- The discovered generated fontconfig configuration belongs to the Office
  wrapper, not the global session. Corrected earlier overly broad description.
- WorkstationUserPolicy still performs deployment-user setup in a package hook.
  Preserve working order while planning its move into existing image setup.
- Flathub setup and building Docker zero/one do not prove that applications or
  Podman images are provisioned into the HDD. Existing provisioners need locating.

## Execution order, without extra scope

1. Finish reading the R10 package/install result; never restart it blindly.
2. Close package publication/mapping deltas together: AX-001/003/004/006/008.
3. Reconcile existing boot/user activation and profile assets: AX-002/005/007.
4. Wire only missing agreed provisioning: AX-009/010/011.
5. Use AX-012 effect accounting throughout, not as a separate factory rewrite.

Each changed package gets donor-effect evidence, emitted-hook/path inspection,
an actual install/replay check and its original acceptance check. Human desktop
acceptance is explicitly separate. Any repair is prepared, committed, executed
via BKC and reported in comments with relevant retained evidence. Direct SSH
is discovery only. These plans do not authorize destructive disk selection.

## Ticket-specific plans

- [AX-001 E](alpha-ticket-plans/AX-001-2026-09-05.md)
- [AX-002 PTYs](alpha-ticket-plans/AX-002-2026-09-05.md)
- [AX-003 terminal data](alpha-ticket-plans/AX-003-2026-09-05.md)
- [AX-004 menus/session](alpha-ticket-plans/AX-004-2026-09-05.md)
- [AX-005 profile/theme](alpha-ticket-plans/AX-005-2026-09-05.md)
- [AX-006 fonts](alpha-ticket-plans/AX-006-2026-09-05.md)
- [AX-007 accounts](alpha-ticket-plans/AX-007-2026-09-05.md)
- [AX-008 applications](alpha-ticket-plans/AX-008-2026-09-05.md)
- [AX-009 Flatpak](alpha-ticket-plans/AX-009-2026-09-05.md)
- [AX-010 Podman](alpha-ticket-plans/AX-010-2026-09-05.md)
- [AX-011 installer](alpha-ticket-plans/AX-011-2026-09-05.md)
- [AX-012 factory accounting](alpha-ticket-plans/AX-012-2026-09-05.md)
