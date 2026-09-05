# Alpha release issue / fix ledger

Created September 5, 2026. This is the durable current work list. Read before
acting; add a timestamped action entry BEFORE mutations. Kanboard can mirror
these IDs, but no Kanboard tickets have been created by this entry.

## Action record template

- When / issue ID / status:
- Exact target and frozen source or image identity:
- Evidence (not hypothesis):
- What changes, why, and how (script/BKC run):
- Rollback / protected state:
- Acceptance test:
- After execution: actual result, logs, commit/artifact hashes, remaining work.

Existing observations below are retrospective and explicitly not evidence that
every prior live action was recorded before execution. From this checkpoint,
record first. No further VM or build mutation is authorized by this ledger alone.

## Reference evidence

- [VM145 reference](vm145-alpha-reference-2026-09-04.md): live repairs newer
  than base container; original scsi0 preserved. Current IP 192.168.1.58.
- [Terminal recovery](vm145-terminal-recovery-2026-09-05.md): live changes,
  probes and unresolved reboot persistence.
- [Desktop contract](desktop-launch-contract-2026-09-04.md): XDG/argv/UNO rules.
- [Build history](alpha-build-boot-handoff-2026-09-04.md): BKC runs and artifacts.
- Target screenshots: September 5 10:48:34 (menu/desktop), 10:53:21
  (browser and installer). These are not proof all launchers work.
- Candidate digest: `114085ed8fbcf78811200e52ace7ef05002bf0b4463162085148edf5a54d0657`.
  BKC `97c17981-e37a-4af8-b03a-038ebdfcbc0a` passed bounded container tests.
  HDD run `e2810cd1-9fe0-4aeb-9c63-f6d55c073b9d` failed staging; no disk deployed.

## AX-001 — Enlightenment payload selection [OPEN, blocks HDD]

Evidence: reference image current=0.27.1-1 with RootFS helpers; candidate
current=0.25.4-2 with Commands/Package only. enlightenment_system was absent
from candidate Programs/Libraries/System search. Definition declares 0.27.1-1.
The earlier diagnosis that the HDD overlay was inherently wrong was incorrect.
Fix owner: selection/intake/APK payload. Trace the actual selected input before
editing. Preserve the valid HDD module/ABI guard; do not fill with old ISO E.
Acceptance: intended version and complete owned modules, fresh-root checks,
then graphical boot. No startup rewrite or blanket package rebuild.

## AX-002 — PTY/device modes reset on boot [LIVE REPAIR, not closed]

Evidence: /dev/pts/ptmx and /dev/tty were 0660 root:root. auzix failed access;
xterm reported open ttydev Permission denied. Live chmod 0666 enabled shells.
StartSequence and ServiceRuntime already contain intended mode fixes.
Fix owner: determine later reset/activation order, not terminal package rebuild.
Acceptance: two boots retain accessible PTYs; input, resize, colors, terminal
modes, htop/Glances work from menu-launched terminals. Preserve device policy;
do not add another competing startup repair without identifying the writer.

## AX-003 — Terminfo discovery [SOURCE FIX, repackage pending]

Evidence: NcursesBase redirects into Libraries/Packages; xterm-256color exists.
Shared terminal launcher omitted that data path. ba246ae adds it and preserves
compatibility fallbacks. Explicit-path xterm probe retained sh on /dev/pts/4
after AX-002. Fix owner: terminal launcher/DesktopIntegration producer.
Acceptance: emitted APK contains fix; fresh image discovers definitions with
normal environment; colors/htop/Glances usable. Live keyboard proof pending.

## AX-004 — Efreet/menu/session reboot behavior [OPEN]

Evidence: reference menu populated; SO_REUSEPORT warning also appears while
Terminology stays alive. Warning alone is not crash proof. Preserve shared
XDG-first paths and known Efreet prestart hooks. Inspect actual session/cache
permissions before changing them. Acceptance: populated categories/icons,
working desktop/menu/dock launches after second boot, no E relaunch loop.

## AX-005 — EET, theme, wallpaper and first boot [PARTIAL, verify]

Default.eet exists in both containers. a48283f retains E profile/e.cfg staging
and PTY changes. Not all historical fixes are package-owned; user profile
provisioning belongs to image setup. Acceptance: Foggy Trees/theme, intended
profile, browser directly at beta/welcome site with no Midori setup wizard,
APK installer open alongside it. Do not import unrelated personal browser data.

## AX-006 — Fontconfig default configuration [OPEN]

Candidate emits Cannot load default config file while CLI gate passes.
Fix owner: configuration payload/publication path. Acceptance: valid font
configuration and correct rendered fonts/icons, not only binary presence.

## AX-007 — Sudo / image identities / test ordering [RUNTIME PASS, audit open]

Chroot and Docker --user probes preceded initialization and gave misleading
failures. Real initialized user probe exposed omitted /Libraries secure lookup;
6c88926 corrected it. Candidate login/sudo id/ls/APK passed.
Generic tools/PAM policy belong to packages; deployment user/home/groups and
user-specific sudoers belong to image/first boot. Reconcile existing
WorkstationUserPolicy and Sudo producer with that boundary. Tests must follow
provisioning. Deferral is not PASS; no need to recompile libc for lookup errors.

## AX-008 — Office/browser launchers [OPEN acceptance]

Retain c057e11 argv adaptation, UNO assembly/private library order. Verify
Writer, Calc, Draw, Impress and Midori individually from desktop/menu as auzix,
with usable persistent windows and correct arguments. --help is insufficient.

## AX-009 — Flatpak applications and exports [OPEN]

Reference contains persistent GNOME Calculator and Flathub, not merely a
temporary smoke app. Target: Firefox installed with working launcher; Zed
optional later. Verify trust, install, export/menu visibility, real launch and
reboot persistence. Do not count remote presence as application validation.

## AX-010 — Podman / zero and one [OPEN, VM gate]

After runtime/user/subordinate-ID/cgroup initialization, test podman ps and
actual containers as intended user in the VM. Include agreed zero/one flagship
containers. --version and package presence do not establish runtime operation.

## AX-011 — APK installer and disk install [OPEN]

Verify installer and package GUI APK/sudo/search behavior, repository trust,
target profiles and explicit safe target disk. Acceptance: blank test disk
install, bootloader, reboot installed disk, external SSH and desktop usability.
Do not overwrite reference disk. A visible installer is not installation proof.

## AX-012 — Factory / cache / false-positive gates [PARTIAL]

Index-digest cache invalidation and exact APK replacement now exist. One-off
candidate repairs/corrected spools still need fresh-run selection reconciliation.
Require source→APK→index→image provenance and selected-version/content checks
before HDD work. Replace misleading tests with checks at the correct initialized
boundary. Broader source import/path parameterization follows alpha recovery.

## Release acceptance

All required issues need fresh-image evidence, not just live repairs. Preserve
source/selected APK/index/image hashes, BKC receipts and test results. Verify
second boot and real disk installation. Two HDD outputs: netinstall and
workstation, through existing pipelines. Public promotion excludes lab keys
and test-only repository endpoints. Do not expand into architecture/layout
cleanup while recovering these features.

## Next action proposals (not executed)

1. AX-001: compare selected archive/APK with reference payload; read-only first.
2. AX-002: identify permission reset after known startup repair; read-only first.
3. AX-003: plan and record corrected package emission after producer audit.
Before each mutation, complete the action template above with exact targets,
rollback and acceptance; then record the actual outcome.
