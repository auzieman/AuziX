# VM135 live recovery review — 2026-08-06

## Proven candidate

- BKC run: `2932a5a5-a874-489c-bc39-52a0feb1d171`
- AuziX source commit: `e841dc7`
- ISO: `auzix-live-recovery-20260806T164443Z.iso`
- ISO SHA-256: `9d22881652e836cae5981185b078e5dc9883c82464630942e9edfc95a62c90b6`
- SquashFS SHA-256: `bb10ffa810a7fb24b5b5e7581a770f578cabbe09a91e6beff774b96bcac1b742`
- VM135 booted the candidate with kernel `6.1.0-48-amd64`, DHCP address
  `192.168.1.60`, working graphical Enlightenment, and working SSH key access.

The candidate root was derived exclusively from the pinned embedded SquashFS.
Its reviewed delta is limited to live SSH access and InstallerEFL files.

## Enlightenment themes and wallpapers

- The packaged custom EDJs are present below
  `/Programs/DesktopAssets/auzietek/Resources/display/assets/themes` and
  `/Programs/DesktopAssets/auzietek/Resources/display/assets/backgrounds`.
- `/System/Compatibility/usr/share/enlightenment/themes` contains readable
  symlinks to the packaged custom theme EDJs.
- `/Users/auzix/.e/e/themes` exists but is empty.
- Manual import copied `E20-Scifi-theme.edj` to
  `/Users/auzix/.elementary/themes`, which is the Elementary toolkit theme
  location rather than Enlightenment's user theme location.
- The operator manually applied `E20-Scifi-theme.edj`; the theme and sci-fi
  wallpaper rendered successfully. Preserve this working user configuration
  as the intended default, without importing unrelated session state.
- The packaged `enlightenment_remote` is Elive's shell implementation. Its
  currently implemented DBus methods cover modules, profiles, desktops, and
  windows. The older `-dirs-list`, `-theme-*`, and `-default-bg-*` options are
  listed only inside its `ignore_this` TODO section and are not callable.

## InstallerEFL

- InstallerEFL is installed and its frontend symlink resolves:
  `/Programs/AuzixInstaller/current/Frontends/efl` ->
  `/Programs/AuzixInstallerEfl/current/Commands/efl`.
- The desktop entry invokes `/System/Tools/launch-auzix-installer`.
- The direct EFL launcher initially exited before `exec`: the unprivileged
  `auzix` session could not create its log below root-owned `/System/Logs`.
- The launcher now logs below `${XDG_STATE_HOME:-$HOME/.local/state}` with a
  `/tmp` fallback. The exact desktop command was live-validated on VM135 and
  left `efl.real` running in the existing graphical session.
- Running the EFL frontend directly as `auzix` with the live session's
  `DISPLAY`, `XDG_RUNTIME_DIR`, and DBus address keeps the frontend alive until
  the five-second diagnostic timeout. EFL logs a non-fatal `hint_fill_set`
  warning. This proves the immediate defect is the legacy terminal launcher,
  not a missing frontend binary.

## Midori CA state

- The Midori package wrapper exports `SSL_CERT_DIR`, `SSL_CERT_FILE`,
  `CURL_CA_BUNDLE`, and `REQUESTS_CA_BUNDLE` using the AuziX compatibility CA
  bundle.
- Midori launches and loads public HTTPS pages, but the operator did not yet
  complete the intended private-CA check. Do not mark CA integration complete
  until a targeted HTTPS request and Midori trust result are recorded.

## Package manager runtime test

- Running `auzix-pkg` as `auzix` fails while creating
  `/System/State/packages` and `/System/Logs/packages` because their parent
  runtime trees are root-owned and not user-writable.
- Running `sudo auzix-pkg refresh` creates those directories as root with mode
  `0755`, leaving subsequent unprivileged refreshes unable to update the cache.
- The configured repository is
  `http://192.168.1.10/auzix/repo` and the client correctly requests
  `/auzix/repo/index.json`.
- The repository data is intact at `/srv/http/auzix/repo/index.json`, with its
  package archives below `/srv/http/auzix/repo/packages`.
- ns1's active nginx configuration has no `/auzix/` location or alias, so all
  tested AuziX repository URLs return HTTP 404. This is a publication/config
  regression, not missing package data.
- Repair repository publication independently from ISO payload work, and add
  an HTTP `index.json` plus package-archive check to the visible BKC pipeline.
- Define the privilege contract explicitly: refresh/list may use user-owned
  cache state, while archive extraction into `/Programs`, `/System`, and
  `/Services` requires the existing privileged installation gate.

### ABIWord install acceptance

- `auzix-pkg install AbiWord` completed and recorded AbiWord as installed.
- Run Everything discovers and launches AbiWord successfully.
- The package installed its command wrapper, application icons, upstream
  desktop file, and the compatibility export
  `/System/Compatibility/usr/share/applications/auzix-abiword.desktop`.
- No application icon appeared in E because the per-user Efreet desktop cache
  retained its boot-time timestamp. Icon caches were regenerated, but the
  desktop application cache was not. Package post-install must explicitly
  request an Efreet desktop-cache refresh.

### Theme discovery acceptance

- E does not list custom personal or system themes even though the system
  catalog contains readable symlinks to every packaged EDJ.
- The manually copied real `E20-Scifi-theme.edj` is accepted and renders.
- Replacing a theme catalog symlink with a real file and seeding
  `/Users/auzix/.e/e/themes` did not make the theme appear.
- Inspection of the running Enlightenment process showed its open live theme
  files are `/Users/auzix/.elementary/themes/E20-Scifi-theme.edj` and
  `/System/Compatibility/usr/share/elementary/themes/default.edj`. This Elive
  build therefore discovers live themes through the Elementary theme catalog.
- VM135 was hotpatched by hard-linking/copying the 20 custom EDJs beside the
  proven system `default.edj`. For the next ISO, consolidate the EDJs into this
  live catalog and remove the redundant theme exports/package copies; retaining
  duplicate locations is not a requirement.
- Wallpaper discovery did work after replacing its compatibility symlinks with
  real files/hard links. Preserve that bounded package change.
- The packaged Elive `enlightenment_remote` omits the legacy directory-query
  family and returns success after printing help for unsupported options. The
  AuziX compatibility front end was live-validated with
  `-wallpaper-dir-list`, `-theme-dir-list`, and `-app-dir-list`; delegation to
  the Elive backend still reports Enlightenment `0.25.4`.
- The compatibility front end also provides `-wallpaper-list`, `-theme-list`,
  and `-app-list` (plus `-available-list` aliases) so validation can enumerate
  the files available through each reported search path.

## Bounded next steps

1. Make the desktop installer launcher execute InstallerEFL directly in the
   existing graphical session and preserve a useful log on failure.
2. Verify the private CA is in the compatibility bundle and the browser's NSS
   trust path; change only the missing CA/NSS wiring.
3. Export custom theme EDJs into
   `/System/Compatibility/usr/share/elementary/themes`, update the AuziX
   `-theme-dir-list`/`-theme-list` compatibility queries to report that proven
   catalog, and seed the manually proven sci-fi theme as the `auzix` default.
4. Stage wallpapers in Enlightenment's expected background locations and seed
   the proven default wallpaper.
5. Generate and review an allowlisted SquashFS changed-path manifest before
   triggering another BKC build.

## EFL frontend preflight gate

- Build Installer EFL and Package Manager EFL independently in the disposable
  EFL builder before the next ISO packaging stage.
- Validate both PackageDB receipts, program commands, `/System/Tools` links,
  desktop entries, unprivileged launch behavior, and user-writable logs.
- Package Manager EFL remains a thin client: refresh/list/install operations
  delegate to `auzix-pkg`; it does not implement a second transaction engine.
- Publish both frontends as ordinary AuziX packages where practical. The live
  ISO may preinstall those same packages, but must not carry separate ad-hoc
  copies.
- Screenshot review of the first Installer EFL launch found excessive vertical
  expansion, weak field affordances, and actions below the visible area. The
  next preflight build uses a compact framed form with aligned controls,
  side-by-side gated actions, visible status, and BlackKnight/Auzietek operator
  language while leaving window chrome to the selected E theme.

## Live and optional package policy

- Keep the live ISO focused on installation and recovery. Add a small storage
  cohort beginning with GParted and its operational helpers: `parted`,
  `e2fsprogs`, `dosfstools`, `exfatprogs`, `ntfs-3g`, `lvm2`, `cryptsetup`,
  `mdadm`, `dmsetup`, `smartmontools`, `nvme-cli`, and `efibootmgr`.
- Add `testdisk` and GNU `ddrescue` as recovery candidates after package/runtime
  audit; destructive tools still require explicit privilege and device gates.
- Keep office, graphics, media, development, and alternate desktop applications
  as ordinary optional packages discoverable through Package Manager EFL.
- Model the installer after Elive's proven separation: automatic guarded
  planning plus an explicit GParted/manual-partitioning escape hatch. Reuse
  public Elive behavior and source where licensing and provenance are clear;
  do not copy unverified fragments.
- None of these packages enters the next ISO until its AuziX package receipt,
  dependencies, desktop discovery, privilege path, and live launch are
  preflighted through a BKC-visible package lane.

## Upcoming ISO frontend checkpoint

- Installer EFL and Package Manager EFL source/UI cleanup is in scope now;
  compilation and package publication may be tabled until the BKC-visible EFL
  package-build lane is ready.
- Both frontends use the same compact BlackKnight/Auzietek operator language,
  selected E theme chrome, explicit state text, and controls that remain visible
  at the supported fallback resolution.
- Installer acceptance: enumerate real target disks rather than relying on a
  text default, offer the preflighted GParted escape hatch, preserve the
  plan/validate/destructive-confirmation separation, and retain actionable logs.
- Package Manager acceptance: refresh and enumerate the repository, prominently
  display package name/version/kind/size, install only the selected safe package
  through `auzix-pkg`, refresh Efreet after desktop-package changes, and expose
  failures through visible status plus a user-readable log.
- Do not trigger the next ISO merely to compile these frontends. Build and
  preflight their ordinary packages first, then consume the validated receipts
  in the preserved-SquashFS ISO lane.

### Shared installer/package selection model

- Installer EFL must enumerate real install candidates (`sd*`, `vd*`, and
  `nvme*`) with device size/model rather than defaulting a free-text `/dev/sda`.
- Keep storage choices intentionally small: whole-disk automatic layout or a
  root/home split controlled by a simple percentage/ratio. GParted is the
  advanced manual-partitioning escape hatch.
- Installer EFL and Package Manager EFL should consume one package-profile
  format and render packages as multi-select checkboxes. A reviewed first-boot
  desktop profile may preselect useful packages such as AbiWord and Gnumeric.
- Checking packages never performs a transaction by itself. Installer review
  records the selected package profile in its plan; Package Manager review
  submits the selected set to `auzix-pkg` only after explicit confirmation.
- Package metadata shown beside each checkbox should include name, version,
  kind, size, installed/available state, and a short description when present.
- After a successful desktop-package transaction, refresh Efreet once so new
  applications become visible without restarting the entire desktop.

### Minimum credible installer inputs

- Machine: hostname with a sensible editable default, timezone, locale, and
  keyboard layout.
- Primary account: username, optional display name, password plus confirmation,
  and an explicit administrator/sudo membership choice.
- Root account: choose disabled/direct-login-off, use the primary account's
  password, or supply and confirm a separate root password. Never embed a
  default password or persist plaintext credentials in the plan or logs.
- Storage: selected discovered disk, whole-disk versus root/home split, split
  ratio, bootloader mode, and an explicit destructive target summary.
- Software: checkbox-based reviewed package profile shared with Package Manager
  EFL, including useful first-boot defaults without silently installing them.
- Review: show identity, storage, boot, accounts, and package selections before
  enabling the separate destructive authorization action.

### VM135 UI preflight — current overlay

- Committed sources compiled in temporary R730 builder scratch with
  `-Wall -Wextra -Werror`; this was a one-off diagnostic preflight, not a
  package publication or ISO build.
- Installer EFL binary SHA-256:
  `13adf070d847e924bbcdf383dc06a6225b5b42e3a6bf4a0d804937c20be3ccd8`.
- Package Manager EFL binary SHA-256:
  `10f5faa368cf27015d1113cf825de467e0186f8634b7a7c5a1ad659153eb3de4`.
- Both binaries were staged only into VM135's writable overlay and remained
  alive in the existing E session. Package Manager completed its initial query
  with no lingering child and the user-owned repository cache remained valid.
- The only captured runtime diagnostic was the known nonfatal Elementary
  `hint_fill_set` warning. Visual/operator acceptance remains pending.
- First visual review at the operator-selected higher resolution found three
  follow-ups: remove literal markup from package rows, capture the complete
  100-row `auzix-pkg` stream, and shorten installer actions so both remain
  visible. Installer validation also requires the current backend package: the
  booted baseline predates the committed `plan` command used by Installer EFL.
- The unconfirmed EFL plan must live in the user's state tree. Writing it below
  root-owned `/System/State` failed correctly; only the separately authorized
  destructive execution may cross into privileged system state.
- MVP pass `ee6be33` compiled both frontends with `-Werror`. Installer SHA-256
  was `561660bad70a4a3700f118d9650f106f64f9363be5d0b61e87233d804392e81c`;
  Package Manager SHA-256 was
  `130435ff08c1f9c92e03ba7811500c220576b37d020491bc3dc52af316924e24`.
- A synthetic graphical plan successfully validated in VM135 with a split
  layout, 60% home allocation, primary username, disabled-root policy, region
  defaults, and AbiWord/Gnumeric selections. It remained explicitly
  unconfirmed and contained no passwords.
- Both MVP windows remain live for operator review. Do not call the installer
  install-capable until discovered-disk selection, credential handoff, package
  checkbox behavior, and the final review gate are separately accepted.
- UI refinement commit `a5b0e72` compiled with `-Wall -Wextra -Werror` in
  disposable R730 scratch. Installer SHA-256 is
  `ac16fe788aeb24f99277ee355ee9702d972b92b699c50138c6ef941e09445533`;
  Package Manager SHA-256 is
  `6f9013c42164972fbf1da1ab9792be3127b448c8d544a5539e8b7dae71ec1d79`.
- Those exact binaries are running in VM135's overlay as PIDs 4700 and 4701.
  This pass separates and frames password confirmation, adds a scrollable
  eight-item first-boot package set, and makes Package Manager rows toggle
  their checkboxes. Logs contain only the known nonfatal EFL fill-hint warning.
- Password values are still memory-only validation inputs; the backend does
  not yet apply credentials. Disk discovery/selection and destructive review
  remain explicit blockers to calling this installer install-capable.

## Next ISO build steps

1. Start only from the hash-pinned, runtime-proven ISO and its embedded
   SquashFS. Extract that root once; do not layer ISO images or import a newly
   remixed root.
2. Snapshot a clean committed source tree on R730. Refuse dirty source and
   record the source commit in the BKC-visible run receipt.
3. Apply only the reviewed deltas: live SSH access, installer backend/schema,
   Installer EFL, Package Manager EFL, corrected CA/browser trust wiring,
   DesktopAssets exports, user defaults, and the 1080p display preference.
4. Export theme EDJs to the process-proven Elementary catalog
   `/System/Compatibility/usr/share/elementary/themes`; keep wallpapers in
   Enlightenment's background catalog. Seed the accepted sci-fi selection in
   the `auzix` profile without copying caches or unrelated home state.
5. Repack one fresh SquashFS, replace only the SquashFS payload in a copied
   boot tree, and reproduce the preserved BIOS/UEFI boot map.
6. Before publication, verify backend/schema and both EFL package receipts,
   CA bundle and browser trust, theme/wallpaper catalogs and defaults, 1080p
   preference, SSH access, `auzix-pkg refresh`, and ISO BIOS/UEFI validation.
7. Publish ISO, SHA-256, changed-path manifest, build log, and receipt through
   the visible BKC lane. Boot that exact checksum on VM135 and repeat the live
   acceptance checks before any GitHub merge.

## Executable installer and package transaction preflight

- Commit `d164e3a` adds the first deliberately narrow executable EFL handoff.
  The graphical frontend still writes only an unconfirmed plan. The backend
  `execute PLAN EXPECTED_DISK` action revalidates it, requires the reviewed
  disk to match, creates a private mode-0600 confirmed copy, and removes that
  copy after invoking the existing disk executor.
- VM135 no-op-executor tests passed for a reviewed `/dev/sda` whole-disk plan
  and refused both a `/dev/sdb` substitution and a plan containing first-boot
  packages. No block device was written during this preflight.
- Installer EFL SHA-256 is
  `e13dee7f71eac7a8cbb4183e9e86bc3ebc4a57cfc8e537021fb367ed47224318`;
  that exact binary is running in VM135 as PID 4833.
- The current executable slice is intentionally whole-disk only. It retains
  the live image's account defaults; split root/home, credential application,
  and installed-root package transactions remain hard refusals rather than
  ignored UI selections.
- A real current-repository transaction on VM135 installed
  `Debian.gnumeric` `1.12.57-1.1+b1` through the same privileged absolute
  `auzix-pkg` path used by Package Manager EFL. Fetch, checksum verification,
  extraction, finalization, and installed-state registration passed.
- That package is still `stage-0-fhs-build`: its receipt declares no commands
  or compatibility exports. This is evidence that repository transactions
  work, but also the reason to defer a larger first-boot catalog until the
  Ollama-assisted package worker and per-package porting lane improve runtime
  integration.

## Recovery ISO r4 boot validation

- Source commit: `1773061c20f44d1c4bacb5cf34565c36d1e428a5`.
- Build lineage: BKC run `2e526763-fada-4b82-b64c-a81403a0594f`, worker retry
  `r4`. The deployed BKC image recorded the run but reported the workflow as
  unwired; the exact committed worker script produced the linked receipt.
- Artifact:
  `auzix-live-recovery-2e526763-fada-4b82-b64c-a81403a0594f-r4.iso`.
- Static validation passed `AUZIXLIVE`, protective MBR/GPT/APM, BIOS GRUB El
  Torito, UEFI El Torito, and all bounded payload assertions.
- Proxmox verified the published checksum, attached the ISO to VM135, used the
  required stop/start fallback after ACPI shutdown timed out, and booted it
  CD-first. SSH returned at `192.168.1.60`.
- Runtime validation passed kernel `6.1.0-48-amd64`, SSH, Xorg, Enlightenment,
  installer backend, both EFL frontend hashes, CA compatibility links, and a
  real hard-linked sci-fi EDJ in the process-proven Elementary catalog.
- Installer EFL and Package Manager EFL launched in the clean session as PIDs
  1987 and 1988 for operator review.
- Follow-up: this media still exposes Elive's limited native
  `enlightenment_remote`; stage the committed AuziX compatibility wrapper as a
  bounded file delta and point its theme queries at the Elementary catalog.
- Operator screenshots at 14:04 and 14:08 prove the public HTTPS site loads,
  AbiWord and Gnumeric launch after Package Manager transactions, and the
  higher 1920x1080 mode works. The theme selector's reported failure is
  specific: `Scifi-terminology-theme.edj` is a Terminology theme and was
  incorrectly exported into Elementary's theme catalog. Route it to
  `/System/Compatibility/usr/share/terminology/themes` and keep it out of the
  desktop theme selector.
- Installer password entries render vertically compressed inside their frames;
  enforce minimum entry and frame dimensions in the next EFL preflight.

## Next-ISO display evidence

- VM135 uses Proxmox's default virtual display with AuziX's Xorg `modesetting`
  driver; no alternate VNC/display driver is required.
- The current live session selected `1280x800`.
- Xorg accepted advertised modes including `1920x1080`, `1920x1200`, and
  `2048x1152`. The packaged and live-regenerated Xorg configurations now prefer
  `1920x1080`, with `1280x800` and `1024x768` fallbacks for smaller viewers.
- The next candidate must include commits `fa1e1df` (validated wallpaper
  exports), `7fe24cf` and `b7025a5` (validated Enlightenment directory and
  asset queries), and `1aaa38f` (1080p preferred mode).
- Theme acceptance for the next candidate: `-theme-dir-list` reports the
  Elementary system catalog, `-theme-list` enumerates all packaged custom
  EDJs, the graphical selector shows them after a clean boot, and the sci-fi
  theme is the default without a manual import.

No kernel, initramfs, package-set, base root, or boot-layout rebuild belongs in
this cleanup.

## Launch-candidate install evidence

- Clean source commit `9138e3dc32d236c6b9c43ab084e01e652669fe46`
  produced `auzix-live-launch-launch-20260806-9138e3d.iso` with SHA-256
  `bc5ab250780d7ed7619a45db073f3ce1e4c355574d6f1d8dd637b20ad2121776`.
  The ISO passed the static BIOS/UEFI and bounded-payload contract.
- VM135 booted that checksum from CD, proved the corrected Elementary and
  Terminology catalogs, then executed an unconfirmed whole-disk plan through
  the separately guarded `execute PLAN /dev/sda` handoff.
- The first install exposed a BIOS GRUB embedding bug because legacy BusyBox
  geometry selected sector 32. Commit `fb52e3b` fixes the executor to start at
  sector 2048 and excludes transient browser storage and `/Work/Temp` sockets
  from the installed-root copy.
- The corrected executor completed, GRUB installed without error, and VM135
  rebooted disk-first with `/dev/sda1` mounted at `/` and
  `root=LABEL=AUZIXROOT auzix.root=LABEL=AUZIXROOT` on its kernel command line.
- This is an installed-root MVP, not a clean launch candidate yet. Confirmed
  bugs are: missing ext4 tooling causes an ext2 fallback; the selected hostname
  is not applied; Midori is not consistently consuming system CA trust; the
  selected sci-fi theme and 1920x1080 mode are not automatic; and password
  fields begin content-sized instead of occupying their intended width.
- The service intake probe passed for OpenSSH server, Nginx, Samba, NFS client,
  Podman, and debootstrap only as stage-0 payload receipts. Its supposedly
  Trixie builder resolved Bookworm versions after refreshing APT metadata, so
  suite/snapshot pinning is required before any of those packages are published.
- `docs/images/Screenshot at 2026-08-06 14-58-22.png` is the installed-root
  publication proof: the AuziX desktop shows AbiWord, Gnumeric, the public
  Auzietek site, Package Control, and the on-disk AuziX root in one session.
