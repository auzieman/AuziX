AUZiX package activation/configure contract
Date: 2026-08-10

Finding:
  AUZiX package installs currently move files into /Programs and expose selected
  compatibility paths, but complex Debian-derived packages also rely on an
  install-time configure phase. Debian/dpkg does this through maintainer
  scripts, triggers, debconf, update-alternatives, ldconfig, tmpfiles, sysusers,
  icon/MIME/schema caches, udev rules, DBus policy, PAM snippets, systemd units,
  and service enablement.

Observed VM135 failures from missing activation:
  - LightDM/Xorg black screen when DBus was not started before display.
  - Greeter worked only after cgroup2, /run, udev, DBus, sshd, and runtime dirs
    were manually bootstrapped.
  - systemd as PID 1 can execute with the matched Libc6 loader/runtime, but fails
    manager initialization before the package-configured OS substrate is present.
  - logind, AccountsService, Mesa/swrast, DBus service activation, and package
    system users are not consistently configured by plain archive extraction.

Required AUZiX package lifecycle:
  1. fetch/build
  2. stage into /Programs/<Name>/<Version>
  3. install/expose compatibility paths
  4. activate/configure
  5. validate

Activation inputs to capture during Debian intake:
  - DEBIAN/preinst, postinst, prerm, postrm, triggers
  - package conffiles
  - /usr/lib/systemd/system and /lib/systemd/system units
  - /usr/lib/tmpfiles.d, /etc/tmpfiles.d
  - /usr/lib/sysusers.d, /etc/sysusers.d
  - /usr/share/dbus-1/system-services and /usr/share/dbus-1/system.d policy
  - /usr/share/polkit-1 actions/rules
  - /lib/udev/rules.d and /usr/lib/udev/rules.d
  - PAM files under /etc/pam.d
  - GSettings schemas, GIO modules, GTK loaders, icon themes, MIME databases
  - ld.so.conf snippets and loader/runtime requirements
  - update-alternatives registrations
  - users/groups implied by maintainer scripts or sysusers

Activation outputs in AUZiX terms:
  - /System/Settings: conffiles, PAM, systemd enablement, DBus config, machine-id
  - /System/State: package state, persistent service state, generated databases
  - /System/Cache: fontconfig, icon, MIME, schema, loader caches
  - /System/Compatibility: legacy-facing aliases and unit/rule/policy visibility
  - /Services: AUZiX service wrappers where native systemd is not PID 1

Immediate implementation direction:
  - Add an `activate` command to auzix-pkg.
  - Store activation metadata in each package receipt.
  - Run package activators after install and after dependency changes.
  - Add triggers for:
      glib-compile-schemas
      gtk-update-icon-cache
      update-desktop-database
      update-mime-database
      fc-cache/fontconfig
      dbus machine-id and policy refresh
      udev rule visibility and trigger/settle
      systemd unit visibility and enablement
      tmpfiles/sysusers application
  - Validation must run after activation, not merely after extraction.

Systemd-specific lesson:
  The minimal remote boot ISO is valid: it can mount the installed AUZiX root and
  execute /init. The systemd PID1 path should wait until activation can provide a
  Debian-like configured substrate. Until then VM135 should stay on AUZiX init
  with explicit core-service bootstrap for filming/usability.

First minimal extraction pass:
  Added scripts/activate-auzix-basic-config.sh. It scans installed
  /Programs/*/*/RootFS trees and exposes low-risk configuration surfaces without
  rebuilding packages:
    - systemd units
    - DBus system policy and service activation files
    - udev rules
    - PAM snippets
    - tmpfiles/sysusers snippets
    - GSettings schemas
    - desktop files, icons, and MIME data
    - machine-id and basic runtime directories

  VM135 activation result after the first pass:
    systemd unit entries: 225
    DBus policy files: 2
    udev rule files: 2
    PAM files: 6
    schema files: 1
    desktop files: 3

  This is intentionally not the full dpkg maintainer-script equivalent yet, but
  it extracts the basics from the packages already installed on the VM.

VM135 Enlightenment recovery addendum:
  The installed VM135 desktop proved that Enlightenment/EFL packages need a
  broader activation surface than command binaries and desktop files. E reached
  LightDM and then failed in layers until these Debian runtime surfaces were
  restored:

    - /usr/lib/x86_64-linux-gnu/enlightenment/utils and modules
    - /usr/bin/efreetd plus /Programs/EFL/current activation
    - /usr/share/enlightenment/data/config and backgrounds/themes
    - /usr/share/elementary and /usr/lib/x86_64-linux-gnu/elementary/modules
    - /usr/lib/x86_64-linux-gnu/evas/modules/engines
    - /usr/lib/x86_64-linux-gnu/ecore_evas/engines
    - /usr/lib/x86_64-linux-gnu/edje/modules
    - /usr/lib/x86_64-linux-gnu/ecore_imf/modules
    - Mesa DRI swrast under /usr/lib/x86_64-linux-gnu/dri
    - setuid root mode on enlightenment_system, enlightenment_sys, and
      enlightenment_ckpasswd

  Failure ladder observed:

    1. Missing enlightenment utils caused alert/helper path failures.
    2. Missing efreetd left E stuck at EIO Init waiting for
       /run/user/1000/.ecore/efreetd/0.
    3. Missing Elementary and E config data made first-run/profile setup fail.
    4. Missing Evas engines let X/GLX exist, but EFL could not create canvases.
    5. Missing Ecore_Evas engines produced:
         "Enlightenment cannot create a compositor."
    6. Incorrect helper permissions left privileged E_System/Auth paths wrong.

  After restoring these, E reached:

      ESTART: ... MAIN LOOP AT LAST

  Packaging rule:
    Treat EFL module directories as executable runtime payloads, not optional
    data. The activation pass now exports E/EFL/Elementary module/resource trees
    and reapplies Debian's setuid helper permissions.

  LightDM/session rule:
    LightDM must run /System/Tools/start-enlightenment-session as a session-only
    wrapper. /System/Tools/start-e is the live-CD/X-spawning path and will fail
    under LightDM with "Server is already active for display 0". Logout should
    return to LightDM; autologin is only for controlled smoke tests.

  Remaining follow-up packages:
    - fontconfig default config and cache
    - locale generation or locale archive package for en_US/en_US.UTF-8
    - PulseAudio/PipeWire session service or mask E mixer until sound exists
    - ldd/readelf diagnostic tools in the base workstation/debug set
    - AbiWord/Gnumeric/office packages built on a Debian-capable builder, then
      installed through auzix-pkg rather than hand-copied

Theme/resource relocation addendum:
  E themes and backgrounds exposed another activation class. AUZiX-owned theme
  packages may correctly store canonical assets under /Programs, but the desktop
  must also see .edj payloads in Enlightenment's discovery paths:

    - /System/Compatibility/usr/share/enlightenment/data/themes
    - /System/Compatibility/usr/share/enlightenment/data/backgrounds
    - /Users/<user>/.e/e/themes
    - /Users/<user>/.e/e/backgrounds
    - /Users/<user>/.elementary/themes

  The activation pass now exports .edj files from AuzixThemes and DesktopAssets
  package resources into those locations. Package-owned source stays in
  /Programs; the compatibility/user paths are generated visibility surfaces.

  Correction from VM135 recenter:
    The known-good live desktop package exported themes to:
      /System/Compatibility/usr/share/enlightenment/themes
    while later activation also tried:
      /System/Compatibility/usr/share/enlightenment/data/themes
    Both should be populated for now. The older path is the proven AUZiX/E
    package contract from the working live ISO.

Menu/package integration addendum:
  Desktop menu presence has two required halves:
    1. package install state:
         /Programs/<Name>/current, receipts, command wrappers, libraries
    2. desktop integration state:
         /System/Compatibility/usr/share/applications/*.desktop,
         package-aware Exec= paths, icon/theme exports, update-desktop-database,
         efreet cache refresh, and optional user E defaults

  VM135 had menu entries missing because the known-good live package lane was
  not fully installed after the tiny netinstall hydration. Restored from the
  known-good live root for the demo layer:
    - Midori 11.8
    - NetSurf 3.10-1+b3
    - XTerm 379-1
    - Terminology host

  The active repo still drifted for several of these names:
    - Midori, NetSurf, and XTerm were absent from the current published repo.
    - Terminology 1.14.0-1 failed on missing Libevas1EnginesWayland.
    - DesktopFileUtils and DBUSBin were required to refresh desktop/menu state
      and signal Enlightenment cleanly.

  Known-good desktop entries should use explicit AUZiX program paths where
  possible, e.g. /Programs/Midori/current/Commands/midori, instead of relying on
  session PATH magic.

VM135 office recenter addendum:
  For the filmable workstation pass, keep the office menu honest:
    - visible and smoke-clean:
        Gnumeric 1.12.57
        LibreOffice Calc 25.2.3.2
        LibreOffice Writer 25.2.3.2
    - hidden until installed/validated:
        LibreOffice startcenter, raw Debian libreoffice*.desktop entries,
        LibreOffice Impress/Draw/Base/Math launch actions
    - queued:
        AbiWord

  Gnumeric installed after temporarily removing bad/unpublished dependency names
  from the VM135 cached repo index. Its wrappers then needed Libdav1d7 added to
  the runtime package ladder because libdav1d.so.7 was installed but invisible
  to the wrapper. Builder rule: generated wrappers must include the full
  transitive runtime package closure, not only the first-level package depends.

  AbiWord progressed through the same normalizer debt but was parked after
  repeated missing aliases/content packages:
    AbiWordCommon, XfontsUtils, SensibleUtils, LibjsonGlib10Common,
    LibsecretCommon, GlibNetworking, HunspellEnUs, Libaspell15

  These are not reasons to fake a menu entry. They are package-normalizer and
  data-package publication fixes for the next builder run.

Fontconfig addendum:
  VM135 showed /System/Settings/fonts as a symlink to
  /System/Compatibility/etc/fonts while the target directory was absent. That
  made applications print "Cannot load default config file" even after
  Fontconfig and FontconfigConfig packages were installed. Activation must
  create /System/Compatibility/etc/fonts and export package RootFS/etc/fonts and
  RootFS/usr/share/fontconfig before running fc-cache.

Installer test-harness addendum:
  Package install smoke scripts must preserve the real auzix-pkg exit status
  when logging through tee. A pipeline like `auzix-pkg install X | tee log`
  reports tee's status under plain /bin/sh, which hid missing dependency errors
  as rc:0 during the workstation pass.

Trigger environment addendum:
  Activation triggers are package-owned binaries too. On VM135
  update-mime-database was present but failed to load libatomic.so.1 until the
  activation pass exported the installed compatibility library path. Trigger
  execution must prefer /System/Compatibility library roots, with /System/Libraries
  last for AUZiX core fallback.

Sudo/PAM bootstrap addendum:
  VM135 root could run podman directly, and the auzix user already had the
  correct operator-facing groups:
    sudo, wheel, input, render, netdev, audio, video, users

  The failure was not Podman permission state. sudo loaded its binary and
  sudoers policy, then aborted during PAM initialization:
    "sudo: unable to initialize PAM: Critical error - immediate abort"

  strace showed sudo reading /etc/pam.d/sudo, loading pam_permit.so, then
  falling through to /etc/pam.d/other. That fallback file included Debian's
  common-* PAM stack, but common-auth/common-account/common-password/common-session
  were absent from the installed AUZiX root. This made even root's own
  `sudo -n id` fail before sudoers was evaluated.

  Immediate VM135 repair:
    - create permissive bootstrap common-* PAM files under /System/Settings/pam.d
    - keep /etc -> /System/Settings
    - expose /lib/security -> /System/Compatibility/lib/x86_64-linux-gnu/security
    - create /run/sudo/ts and /var/lib/sudo/lectured
    - restore root:root 4755 mode on the sudo executable

  Result:
    - `su auzix -c "sudo -n busybox id"` returns uid 0
    - `su auzix -c "sudo -n podman ps"` lists containers

  Builder/package rule:
    Sudo and PAM are not just command packages. The package contract must include
    PAM service files, the included common-* base stack, the module search path,
    setuid permissions, and sudo runtime directories. Rootless Podman is a
    separate follow-up that needs newuidmap/newgidmap and subuid/subgid support;
    the filmable operator path can use passwordless sudo for Podman first.

Interactive shell and Flatpak bootstrap addendum:
  VM135 also showed that package installation alone did not make an operator
  shell usable. sudo worked when called through an explicit AUZiX PATH, but a
  normal login shell had no /etc/profile, no user .profile/.shrc, and no exposed
  `su` command. BusyBox already provided the su applet; activation simply failed
  to expose it.

  Immediate VM135 repair:
    - expose BusyBox applet shims under /System/Compatibility/bin for core
      operator tools such as su, cat, df, du, ps, grep, sed, less, id, env
    - expose sudo, podman, and flatpak under compatibility command paths
    - seed /System/Settings/profile with AUZiX PATH, LD_LIBRARY_PATH,
      XDG_DATA_DIRS, and XDG_CONFIG_DIRS
    - seed /Users/<user>/.profile and .shrc to source /System/Settings/profile

  Flatpak had a working binary and repairable system installation, but no
  configured remotes. Activation now ensures /var/lib/flatpak points at
  /System/State/flatpak and adds the default Flathub system remote when flatpak
  is present.

  Result:
    - `command -v su`, `command -v sudo`, and `command -v flatpak` work in an
      auzix shell after sourcing /System/Settings/profile
    - `sudo -n id` works for the auzix operator user
    - `flatpak remotes -d` shows Flathub

LibreOffice launcher-state addendum:
  VM135 LibreOffice menu launchers failed before starting LibreOffice:
    "ln: /System/State/libreoffice/program/bootstraprc: File exists"

  The wrapper was doing launch-time assembly into /System/State/libreoffice
  while running as the desktop user. Even with `ln -sfn`, a non-root user cannot
  reliably rebuild root-owned global state on every click. The same wrapper also
  generated fontconfig state under /System/Settings and /System/Cache.

  Rule:
    Package activation may build root-owned global compatibility state.
    User application launchers must either read that state or generate their own
    state under user-owned XDG paths.

  Immediate VM135 repair:
    - Calc/Writer/Common wrappers now build launch state under:
        ${XDG_CACHE_HOME:-$HOME/.cache}/auzix-libreoffice
    - wrapper-private LibreOffice settings now go under:
        ${XDG_CONFIG_HOME:-$HOME/.config}/auzix-libreoffice-settings
    - wrapper-private fontconfig config/cache now go under:
        $XDG_CONFIG_HOME/fontconfig and $HOME/.cache/fontconfig

  Result:
    - `localc --version` works as auzix
    - `lowriter --version` works as auzix
    - the generic LibreOffice startcenter still throws a UNO deployment
      exception, so the menu should keep startcenter hidden until the broader
      LibreOffice suite package set is complete.

Midori follow-up note:
  Midori mostly uses user-owned XDG paths already, but its wrapper still exposes
  /usr/share and gconv compatibility paths. If fonts/certs remain twitchy, audit
  it under the same rule: launcher state belongs under user XDG paths; system CA
  compatibility helps OpenSSL consumers, but Firefox/Midori-family applications
  also carry NSS profile databases such as cert9.db/pkcs11.txt.

Flatpak system-helper addendum:
  VM135 Flatpak CLI and Flathub remote were present, but a normal system install
  failed:
    "The name org.freedesktop.Flatpak.SystemHelper was not provided by any
     .service files"

  The current AUZiX Flatpak package is a command-suite/runtime slice. It exposes
  the flatpak CLI and some MIME/session DBus files, but it does not include the
  full Debian Flatpak system-helper surface:
    - flatpak-system-helper executable
    - org.freedesktop.Flatpak.SystemHelper system DBus service
    - polkit policy for privileged system installs
    - service activation under the system bus

  Immediate VM135 workaround:
    Use per-user Flatpak installs:
      flatpak install --user flathub org.mozilla.firefox
      flatpak install --user flathub com.sublimehq.SublimeText

  Activation now seeds Flathub for both the system installation and each
  /Users/<user> Flatpak installation. Full system-wide Flatpak installation is a
  follow-up package task, not a shell tweak.

Podman reexec/glibc addendum:
  VM135 could run `podman ps`, but image pulls failed during layer unpack:
    "storage-untar / /proc/self/fd/4"
    "/: error while loading shared libraries: /: cannot read file data"

  strace showed Podman re-execing itself through /proc/self/exe for
  storage-untar. AUZiX had launched podman.real through an explicit ld-linux
  wrapper, so /proc/self/exe pointed at the dynamic loader instead of the
  podman.real binary. The loader then interpreted the storage-untar arguments as
  loader arguments and tried to load "/" as a library.

  Rule:
    Go programs or any binary that re-execs /proc/self/exe must not be launched
    through an explicit loader wrapper. They need to be executed directly with a
    compatible system interpreter/runtime path.

  A direct podman.real launch exposed the deeper base mismatch: /lib64/ld-linux
  and /lib/x86_64-linux-gnu/libc.so.6 were still Debian 12 / glibc 2.36 while
  the current Podman and package set required Debian 13 / glibc 2.41. Promoting
  the matched Libc6 package loader/libc pair into /System/Compatibility fixed
  the reexec/unpack path.

  Immediate VM135 repair:
    - backup old compatibility loader/libc under /System/Backups
    - promote Libc6 2.41 loader to /System/Compatibility/lib64/ld-linux-x86-64.so.2
    - promote Libc6 2.41 libc/libm to /System/Compatibility/lib/x86_64-linux-gnu
    - expose Podman support libraries under compatibility lib paths, excluding
      private libc/ld-linux
    - change Podman wrapper to export compatibility LD_LIBRARY_PATH and exec
      podman.real directly

  Result:
    Pulls now work on VM135:
      swarm1.lab.auzietek.com:5001/auzix/service:zero-busybox
      swarm1.lab.auzietek.com:5001/auzix/service:one-nginx
      docker.io/library/python:3.13-alpine

  Runtime network note:
    Default Podman bridge creation still fails:
      "netavark: create bridge: Netlink error: Operation not supported"

    Filmable workaround:
      - use `--network none` for non-network one-shot containers
      - use `--network host` for the Nginx demo container

    Verified commands:
      podman run --rm --network none swarm1.lab.auzietek.com:5001/auzix/service:zero-busybox /Programs/BusyBox/current/Commands/busybox echo "AUZiX zero says hello"
      podman run --rm --network none docker.io/library/python:3.13-alpine python -V
      podman run -d --network host --name auzix-one-nginx swarm1.lab.auzietek.com:5001/auzix/service:one-nginx

    Verified page:
      http://127.0.0.1:8080/
