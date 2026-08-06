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
