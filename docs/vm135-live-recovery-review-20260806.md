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
- That launcher still wraps `/System/Tools/auzix-installer-gui` in Terminology.
  The resulting terminal reports `Install AuziX stopped running unexpectedly`
  and does not preserve useful child output in
  `/System/Logs/installer/installer-launch.log`.
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

## Bounded next steps

1. Make the desktop installer launcher execute InstallerEFL directly in the
   existing graphical session and preserve a useful log on failure.
2. Verify the private CA is in the compatibility bundle and the browser's NSS
   trust path; change only the missing CA/NSS wiring.
3. Stage custom theme EDJs in Enlightenment's expected system/user locations
   and seed the manually proven sci-fi theme as the `auzix` default.
4. Stage wallpapers in Enlightenment's expected background locations and seed
   the proven default wallpaper.
5. Generate and review an allowlisted SquashFS changed-path manifest before
   triggering another BKC build.

No kernel, initramfs, package-set, base root, or boot-layout rebuild belongs in
this cleanup.
