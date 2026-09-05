# Alpha release issue / fix ledger

Current scoped plans: [September5 reconciliation](alpha-scoped-reconciliation-2026-09-05.md).
Read that index and ticket comments for current next actions; older action
entries below are historical, including superseded Planning-on-failure rules.

Created September 5, 2026. This is the durable current work list. Read before
acting; add a timestamped action entry BEFORE mutations. Kanboard can mirror
these IDs, but no Kanboard tickets have been created by this entry.

## Action record template

September 5 — AX-001/task54 and AX-012/task65, before action: operator
requires failed validation to enter a negative state, not Planning. Supersedes
earlier return-to-Planning instructions. Use existing Blocked column41 for
recoverable validation/dependency failures; retain precise reason and exit
criteria in comments. Change helper failure transition, move task54 to Blocked,
and comment on tasks54/65. Preserve descriptions, attachments and other cards.
Rollback: explicit recorded transition, not silent history edits. Acceptance:
API readback task54 in column41/top lane3, deduplicated explanatory comments.

Outcome: comments verified on tasks54/65; task54 confirmed in Blocked41/lane3.
Transition helper initially asserted on the API return despite the destination
being correct. Make transition retries idempotent and judge success by task
readback, not a move call's no-op return. No description or attachment changes.

September 5 — AX-012/task65 tracking correction, before action: user requires
updates as comments and relevant evidence as attachments, not description
rewrites. Change sync to preserve existing titles/descriptions and add explicit,
deduplicated comment-file updates with API readback. Record the correction on
task65. Preserve current descriptions, comments, screenshots and board state;
do not silently migrate/delete historical text. Rollback: scoped git revert;
new comment remains an honest audit record. Acceptance: repeated sync leaves
existing descriptions unchanged and repeated comment submission is a no-op.

Outcome: posted the workflow correction as a comment on task65; a second
identical submission verified exactly one matching comment. Full12-card sync
verified existing descriptions and titles unchanged. No cards moved, no
attachments changed. Historical description cleanup remains pending.

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

September 5 15:46 PDT — AX-012/task65 execution of already-recorded Debian
install observation (`notes/alpha-debian-install-trace-action-2026-09-05.md`).
Operator confirmed held packages do not fail on Debian; the defect is AuziX
intake/APK mapping. Prior source-audit runs (1586c2b, e509689) never executed
`trace-debian-dbus-install.sh`. Frozen source `fea2a20a36333dbd7bd80dcc19d45f42dbe4aac1`
already in r730 bare repo. Method: existing `apk-alpha-source-audit` worker
script on R730 (BKC FIP 10.20.0.232 answers; swarm mgr :5000 timed out; no
UI/API token from this session). Run ID `20260905-debian-install-trace`.
Output `/var/lib/auzix-build/package-proof/AX-012-source-fea2a20a3633`.
No mapping repair, package promotion, image, or VM145 change. Rollback:
dispose container (automatic --rm); delete only this new proof directory.
Acceptance: dpkg transaction for dbus=1.16.2-2, script trace, messagebus
account order, helper root:messagebus 4754, bus reply — or exact failure.

Outcome: observation passed. Proof
`/var/lib/auzix-build/package-proof/AX-012-source-fea2a20a3633`. Debian
installed dbus=1.16.2-2; messagebus then helper 4754; bus reply after an
explicit daemon start (socket was absent post-install). Same retained
archive still `needs-review` with helper 0755. Result note:
`notes/alpha-debian-install-trace-result-2026-09-05.md`. Mapping repair
not started. Task65 left Work in progress.

September 5 16:04 PDT — AX-012/task65, before action: VM145 is close enough
and stays diagnostic. No new HDD. Validate intake first. Pipelines exist
but the prove-factory gate is dishonest: `test-held-package-effects.py`
always exits 1, and conversion `completed-with-review` was treated as a
crash. Change: keep conversion/effects as evidence, write
`validation-boundary.json` (install untested, HDD locked), stop remapping
prove-factory/source-audit onto resume-containers, keep unit tests green.
No VM145, image, or HDD mutation. Any later lab run that alters the
environment goes through `bkc-cli` with a paper trail; no raw SSH
launches. Rollback: revert those scripts and this note. Acceptance: local
lifecycle units pass; prove-factory would exit 0 on completed conversion
even with remaining mapping families.

September 5 16:17 PDT — AX-012/task65, before action: operator agreed the
layer split is the repeatable history. Split `rewrite-paths.sed` (runtime
leftovers, including `/var/run`) from `rewrite-payload-paths.sed` (`/usr*`
Compatibility for debian-intake payload text). Lifecycle keeps unowned
`/usr/bin` as `unmapped-path`. Local `unittest discover` must be green.
No BKC, HDD, or VM145 in this step. Rollback: revert the split commit.
Acceptance: the three factory fixtures that failed on `95000cc` pass; D-Bus
`/var/run` still rewrites; owned RootFS still wins.

Outcome: `016a920` local `unittest discover` 81 OK. Runtime table no longer
rewrites unowned `/usr*`. Pushed to r730 `cursor-auzix`. No BKC this cut.

September 5 16:33 PDT — AX-012/task65, before action: recover the four
Debian protocol shapes in AuziX helpers and keep them on the APK hook
(`Package/Scripts` + FPM `--after-install`). Drop dead `in_sysroot`/
`DPKG_ROOT` after account import; treat `dpkg --compare-versions` as
upgrade protocol; `invoke-rc.d` restart as optional reload; `sysctl
--system` as a command trigger. Unnamed fixtures. No HDD or VM145.
Rollback: revert this intake commit. Acceptance: the four unpacked
scripts lose those leftover findings; hooks still attach to APK.


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

September 5 follow-up outcome: BKC7d0ceebd-f4e0-44e7-a3e8-983a1d7ea9e4,
source6c9d8cb, passed conversion and runtime entrypoint, then APK correctly
rejected missing dependencies. Exact list: enlightenment-data, libasound2t64,
libasound2-data, libbluetooth3, libexif12, libpulse0, libasyncns0, libsndfile1,
libflac14, libogg0, libmp3lame0, libmpg1230t64, libopus0, libvorbis0a,
libvorbisenc2. This is 15 identities (the live commentary's 16 was a miscount).
None have APK filenames in R8 repository/x86_64. The retained runtime-closure-r2
spool already has Libpulse0, Libsndfile1, Libvorbis0a and Libvorbisenc2 archives;
their payload hashes/dependency closure still need checking. Do not conclude
the rest require compilation. A broader read-only filename scan was stopped
after ~30 seconds without results; no files were altered by that scan.
Return task54 to Planning with this precise closure gap. Next bounded action:
locate the remaining donor/archive records from existing inventories, verify
their metadata, then emit only that closure and rerun exact APK installation.
Do not use --no-deps or count the emitted E APK as an installation success.
Install log: /var/lib/auzix-build/package-proof/AX-001-6c9d8cb209dd/install.log.
VM145, R8 image and its repository remain unchanged; no new HDD was built.

September 5 18:58 UTC: ce8d663 passed all64 local tests and actual Enlightenment
conversion in BKC48395464-4510-4bbd-a84d-8d1b9d88339f (zero review findings).
Install probe stopped BEFORE apk: normal image entrypoint initializes Flathub,
but the proof used --network none. This is a test prerequisite error, not an
Enlightenment failure. Before action: return task54 to Planning, remove only
that network isolation flag so the unchanged runtime entrypoint can initialize;
APK still uses /dev/null repositories and exact local artifact. Rerun isolated
proof, retaining previous logs. No Flatpak/startup behavior changes. Rollback:
restore flag; VM and completed candidate remain untouched.

September 5 18:55 UTC — task54 validation failed in BKC
`c600f1ea-bf10-42d5-8683-a6744b88953c`: archive conversion emitted an APK but
returned needs-review for Debian update-alternatives install/remove and its
x-window-manager/manpage paths. Install proof did not run. Original donor
postinst/prerm contain only that alternatives registration/removal. Existing
AuziX start-e helpers select enlightenment_start directly (add-auzix-live-tools.sh),
so Debian's default-window-manager selection is not the session startup owner.
Before action: return task54 to Planning; add an explicit Enlightenment intake
adapter preserving both conffiles and documenting the inapplicable alternatives
protocol, without rewriting startup or launchers. Test adapter/config retention,
then rerun the isolated package/install proof with a new source-specific output.
Extend the tracking helper with a Planning transition and readback. Rollback:
revert only these scoped source edits; preserve R8, VM145 and failed proof files.
Acceptance remains complete payload plus actual APK installation; graphical
acceptance is still separate. Proof evidence is under
`/var/lib/auzix-build/package-proof/AX-001-24f6eaf7e0c5/output`.

September5 validation action, before execution: BKC bounded proof will select
the pinned Moon archive using current helper, convert only Enlightenment with
the existing R8 factory, and install the resulting APK into an ephemeral copy
of R8. Output under /var/lib/auzix-build/package-proof/AX-001-<source SHA>;
refuse overwrite. Check version/current link, helper and module files. Preserve
R8 repository/image and VM145, no HDD build. Rollback is discard only the new
proof container (automatic --rm); retained files document failures. This is
package/install proof, not graphical acceptance. Ticket54 remains Validating.

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

September5 evidence update (documentation only): Kanboard task57 comment5
requires strict team Kanboard use because of repeated regressions. Attachments
1/2 are shot-2026-09-04_13-30-27.jpg and shot-2026-09-05_10-48-34.jpg.
Inspected local copies: September4 shows Calc execution-error dialog, Midori
setup wizard, rescue terminal without rendered htop UI, and a separate Glances
display; September5 shows populated category/Office menus and Foggy Trees.
These are partial-state references, not blanket success evidence. Cross-link
terminal behavior to AX-002/003, first-boot browser to AX-005, Calc to AX-008.
Do not replace user comment or attachments when syncing descriptions.

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

Held-package BKC failures are intake/APK mapping, not AuziX OS defects.
Debian installs those packages; the mapper leaves effects unmapped.

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

## September 5 — AX-001/AX-012 tracking and investigation action

Before action: create a private bkc-channel review packet linking this ledger,
requesting advisory-only ai-worker/Ollama review and Kanboard tracking. User
explicitly requested this integration. Method: existing channel outbox; later
dispatch through ai_worker workflow_relay upsert-ticket when its execution
endpoint is confirmed. No infrastructure or image authority delegated.
Rollback: remove only this new packet if superseded; retain original evidence.
Acceptance: packet exists; actual task IDs/worker receipt required before
claiming dispatch or review complete. No credentials in the packet.

Read-only finding: candidate selected-repo index has no Enlightenment record;
the retained layer contains enlightenment-0.97193867-r0.apk. The replacement
archive profiles omit Enlightenment. This narrows AX-001 to retained-base
selection, not a newly emitted wrong version. Correct source archive location
still needs identification. No E package or startup modifications made.

## September 5 — Kanboard sync action (planned before execution)

Target: VM138 Kanboard project3, AUZiX Package Factory. Create/update only
AX-001..AX-012 using stable references and this ledger's text. Place in Planning,
not Ready/Triggered, to avoid accidental execution. Method: JSON-RPC on the
guest via QEMU guest execution; read existing API credential locally without
printing it. No direct database writes. Leave old cards and columns untouched.
Rollback: new cards can be closed by recorded IDs; existing descriptions must
not be overwritten unless they carry our exact stable reference.
Acceptance: API readback shows twelve referenced cards; retain ID mapping here.
Old receipt pairs23/24,25/26,27/28,29/30 and legacy auzix-pkg card49 are review
candidates, not automatically deleted or moved. ai-worker/Ollama dispatch is
separate and must not be claimed from ticket creation alone.

Sync outcome: Kanboard JSON-RPC created and read back tasks54..65 in project3
Planning. Mapping AX-001=54, AX-002=55, AX-003=56, AX-004=57, AX-005=58,
AX-006=59, AX-007=60, AX-008=61, AX-009=62, AX-010=63, AX-011=64,
AX-012=65. Old cards were not moved/deleted. Initial multiline guest invocation
returned exit0 but no receipts and readback showed no cards; corrected transport
to preserve code arguments. Script now requires twelve API receipts, not host
SSH exit status. Advisory worker dispatch remains pending.

Agent lifecycle is now mandatory in AGENTS.md: selected issue/action record →
Work in progress → Validating → Done/Accepted only with acceptance evidence.
Failure returns to Planning; external blockers are explicit. Remote transitions
require readback and linked repository evidence. Current cards remain Planning;
next implementation pickup is AX-001/task54 after action plan is recorded.

## September 5 — Board column-order correction (before action)

User requested cleanup of project3's mixed workflow order. Stored order by ID:
9,10,11,12,21,25,30,32,35,38,41,43 (Done is fourth; Planning fifth).
Cause: ai-worker ensure_columns appends missing columns but doesn't reorder
existing ones. No rename is needed. Use existing JSON-RPC changeColumnPosition,
verified in installed ColumnProcedure.php, to order existing IDs as
9,21,10,25,30,11,32,38,41,35,43,12. Blocked sits beside active review work.
Preserve all column IDs/titles and task column assignments; capture before/after
assignments and assert unchanged. Rollback: same API with recorded original
order. Acceptance: API readback exact desired order and unchanged task map.
Scope is project3 only; no other boards or automation triggers are changed.

Outcome: scripts/sync-alpha-kanboard.py --apply --order-columns succeeded.
API readback verified all12 positions, original titles/IDs, and unchanged
active/closed task-column assignments. No columns or cards renamed/deleted.

## September 5 — AX-001/task54 active pickup (before action)

Target: task54, project3; move to Work in progress/Default swimlane3 (top,
active-now window), preserving title and history. Then inspect existing Moon
spool `/var/lib/auzix-build/factory-delta/moon-hdd-20260904T150105Z-r5/spool`.
Found exact Enlightenment0.27.1-1 archive and metadata there; no compilation is
planned. Verify archive hash, owned helper/module paths and dependencies before
adding it to replacement selection. Do not mutate completed R8 candidate or
VM145. Rollback: task returns to Planning with findings; code changes remain
separate commits. Acceptance for this step: verified source record and explicit
replacement-selection fix/test; graphical acceptance remains open.

Action refinement before code change: add a single reviewed archive override
to alpha-runtime-closure profile: Enlightenment0.27.1-1 from the Moon r5 spool,
SHA256967d98217ec4d2b64ca5dbe89b22866a95b1af1f8f1c2e46e9e245166e9da671.
Selection helper must verify version and content hash before copying, and
explicitly request this identity. Tests cover override selection and hash
rejection. This doesn't execute or alter the completed R8 build; next build
will require a fresh run ID. Task54 transition readback confirmed top lane3,
Work in progress11. Package emission/boot remain later validation steps.

Outcome:90799fe explicitly selects the complete pinned archive and verifies
record version/hash against archive bytes. 63 unit tests passed, including
reviewed override and stale-byte rejection. No image/VM mutated. Planned next
transition: task54 to Validating35, still top lane3, because source fix exists;
APK emission/installation and graphical boot remain required before Done.
