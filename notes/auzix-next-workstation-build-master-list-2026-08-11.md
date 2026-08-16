AUZiX next workstation build master list
Date: 2026-08-11

Context:
  Lab is offline, edge is online. VM135 is no longer a mystery pile: it now has
  a mostly working AUZiX desktop proof with Podman pulls/runs, LibreOffice Calc
  and Writer launch, and an AUZiX Nginx container page. The remaining failures
  should feed the next package build plan and installer activation stages.

Inspection update, 2026-08-11 morning:
  VM132 and VM135 were inspected through edge after the lab came back online.
  Captured logs are under:
    /home/auzieman/Projects/AuziX/out/vm132-vm135-inspection-20260811-061901

  Reference hosts:
    VM132 Trixie:
      ssh auzieman@192.168.1.169
      hostname: trixie-smoke-132
      kernel: 6.12.94+deb13-amd64

    VM135 AUZiX:
      ssh root@192.168.1.198
      ssh auzix@192.168.1.198
      hostname: auzix-live
      kernel: 6.1.0-48-amd64

  Treat VM132 as the live dependency/behavior book:
    it has working LibreOffice Impress/Draw, Geany, L3afpad, Gnumeric,
    Galculator, Nano, File, and Podman package metadata available through
    dpkg-query/apt-cache.

  Treat VM135 as the proving ground:
    packages can be present but still fail if the wrapper, runtime ladder,
    activation trigger, DBus/polkit surface, or glibc pairing is wrong.

Do not treat this as a rebuild-everything order. Treat it as the next package
factory input queue: install, capture failure, classify, build/adjust, validate,
then promote only what passes the real-duck gates in
packages/package-validation.contract.md.

Known green / mostly green on VM135:
  - Enlightenment + LightDM graphical login/session reached a usable desktop.
  - Desktop themes/assets mostly restored from known-good live package state.
  - sudo and su work from the auzix operator shell after profile/PAM activation.
  - Flatpak CLI has Flathub visible for --user installs.
  - Podman rootful pulls now work after fixing the glibc/reexec contract.
    Inspection confirmed rootful image inventory includes:
      swarm1.lab.auzietek.com:5001/auzix/service:one-nginx
      swarm1.lab.auzietek.com:5001/auzix/service:zero-busybox
      docker.io/library/python:3.13-alpine
    Rootless Podman still needs uidmap/newuidmap/newgidmap support.
  - AUZiX service images pull from:
      swarm1.lab.auzietek.com:5001/auzix/service:zero-busybox
      swarm1.lab.auzietek.com:5001/auzix/service:one-nginx
  - Podman can run:
      --network none for one-shot BusyBox/Python probes
      --network host for AUZiX Nginx demo
  - LibreOffice Calc and Writer launch from menu after moving launch-generated
    state into user-owned XDG paths.
  - LibreOffice Calc headless conversion proof produced an ODS file.
  - Gnumeric previously passed CLI/version smoke after runtime ladder repair.
  - NetSurf launches.

Known broken / next capture items:
  - Flatpak system install:
      org.freedesktop.Flatpak.SystemHelper is missing from the system bus.
      Current workaround is `flatpak install --user ...`.
      Required package surface:
        flatpak-system-helper executable
        org.freedesktop.Flatpak.SystemHelper system DBus service
        polkit policy
        system bus activation visibility
        full /var/lib/flatpak state contract
      Inspection found no flatpak system-helper/service/polkit files in the
      targeted search output. This is package/activation missing, not a Flathub
      problem.
      Later local-only VM135 check:
        Flatpak 1.16.6 runs.
        System and user Flathub remotes are visible.
        The auzix user already has Flatpak runtime pieces installed.
        The installed Flatpak payload exposes flatpak/flatpak.real only; no
        flatpak-system-helper binary/service/polkit payload is present.
      Conclusion:
        user-mode Flatpak is salvageable locally; system installs require a real
        helper/package payload in the next build.

  - Flatpak app install/run:
      Firefox, Opera, Sublime, Zed, Bazaar, Micro, Clementine should be retested
      with --user first. If install succeeds but run fails, capture bubblewrap,
      portal, /var, XDG_RUNTIME_DIR, DBus, and font/GL errors separately.

  - Podman networking:
      Pull/unpack and host/none runs work.
      Default bridge fails:
        netavark: create bridge: Netlink error: Operation not supported
      Next package/config checks:
        kernel bridge/netfilter modules
        CAP_NET_ADMIN path
        sysctl surfaces
        netavark config
        aardvark-dns
        iptables/nftables availability
        /proc, /sys, /run, cgroup2 mount package ownership

  - LibreOffice suite:
      Calc and Writer are the only desktop-ready visible office launchers.
      Keep startcenter hidden until the UNO deployment exception is resolved.
      Impress/Draw are not present as AUZiX packages on VM135 yet.
      VM132 confirms the Debian command surface:
        /usr/bin/loimpress -> /usr/lib/libreoffice/program/simpress
        /usr/bin/lodraw -> /usr/lib/libreoffice/program/sdraw
      VM132 dependency hints:
        libreoffice-impress depends on libreoffice-core, libreoffice-draw,
        libreoffice-uiconfig-impress, libbox2d2, libepoxy0, libetonyek,
        libmwaw, libodfgen, librevenge, libstaroffice, UNO libs.
        libreoffice-draw brings libcdr, libfreehand, libmspub, libpagemaker,
        libqxp, libvisio, libwpg, libzmf, plus UNO/common libs.
      Next proof targets:
        LibreOfficeImpress --headless --version
        LibreOfficeDraw --headless --version
        sample odp open/export if Impress reaches launch-clean
      Builder rule already learned:
        app launchers must not rebuild /System/State as a desktop user.
      Later local-only VM135 check confirms:
        LibreOfficeCommon contains Impress/Draw icons and shared assets, but
        there is no LibreOfficeImpress/LibreOfficeDraw receipt and no loimpress,
        lodraw, simpress, or sdraw executable in /Programs.
      Conclusion:
        no honest local launcher-only fix exists for Impress/Draw; they need
        package payloads promoted from the next build.

  - Midori:
      User reports a new "getting squashed" / squash-related CLI error.
      Known wrapper is mostly user-XDG but still exposes /usr/share and gconv
      compatibility paths.
      Next capture:
        exact CLI error text
        wrapper stderr
        NSS cert/profile state
        fontconfig state
        ownership of /Users/auzix/.config/mozilla/midori and .cache/mozilla
        whether the error is from browser sandboxing, NSS DB, or missing
        squashfs/libarchive-style helper.
      Inspection targeted run:
        /Programs/Midori/current/Commands/midori --version
        produced stack smashing detected / Aborted.
      NetSurf explicit wrapper showed the same stack-smashing/abort pattern.
      This suggests a shared runtime/ABI/loader issue, not just one browser.
      Later local-only VM135 repair proved Midori was fixable without lab:
        the stack-smash came from including /Programs/Midori/current/Libraries
        ahead of the AUZiX package library tree. Removing that bundled library
        directory from the wrapper and preferring package libs made:
          /Programs/Midori/current/Commands/midori --version
        return:
          Mozilla Midori 11.8
      Keep Resources/midori in the library path for Mozilla private objects,
      but do not blindly include the repacked Libraries directory when it mixes
      ABI generations.

  - Browsers:
      Native Midori and NetSurf should remain small-browser proofs.
      Firefox/Opera should be Flatpak-first until native WebKit/Gecko packaging
      is intentionally scoped.
      Browser failures should be split into:
        CA/NSS trust
        fonts
        sandbox/user namespace
        DBus/portal
        GPU/software rendering
        missing media codecs

  - Native editors / developer tools:
      Leafpad/l3afpad and Geany are not desktop-ready.
      User reports missing deps.
      Prior notes already mention GLib/GLIBC-style mismatch symptoms for Geany.
      Next probes:
        l3afpad --version or simple file open
        geany --version
        geany opens a sample source file from menu
        ldd/readelf on the target ELF, not just the wrapper
      Likely package surfaces:
        Gtk3Runtime
        GLib/GSettings schemas
        GtkSourceView for Geany/Pluma/Gedit-style editors
        icon/MIME/desktop database refresh
        matched Libc6/GLib runtime ladder
      Inspection specifics:
        L3afpad is installed on VM135 and Libcloudproviders0 is installed,
        but the generated wrapper/loader path is wrong:
          /Programs/L3afpad/current/Commands/l3afpad:
            error while loading shared libraries:
            /Programs/L3afpad/current/Commands/l3afpad: invalid ELF header
        This means the wrapper itself leaked into the dynamic loader search
        path as a library candidate. Fix wrapper generation and then retest the
        real ELF at:
          /Programs/L3afpad/current/RootFS/usr/bin/l3afpad

        Follow-up VM135 hotfix proved the deeper class:
          adding Libcloudproviders0 exposed missing Libatomic1;
          adding Libatomic1 exposed old compatibility libmount;
          adding Libmount1 exposed old compatibility HarfBuzz;
          adding Libharfbuzz0b made L3afpad reach the expected SSH-only failure:
            l3afpad: Cannot open display
        Conclusion:
          installed package libraries were present, but the wrapper dependency
          list did not surface them before /System/Compatibility. This is a
          runtime ladder/name-closure bug, not a missing-package-only bug.
          The Debian intake wrapper generator now needs to prefer existing
          package library trees and fall back across installed /Programs libs
          during alpha workstation builds.

        Geany is not installed on VM135. VM132 dependency hints:
          geany-common
          libatk1.0-0t64
          libcairo2
          libgdk-pixbuf-2.0-0
          libglib2.0-0t64
          libgtk-3-0t64
          libpango-1.0-0
          libpangocairo-1.0-0
          libstdc++6

  - AbiWord:
      Parked after normalizer/publication gaps:
        AbiWordCommon
        XfontsUtils
        SensibleUtils
        LibjsonGlib10Common
        LibsecretCommon
        GlibNetworking
        HunspellEnUs
        Libaspell15
      Next action is not another fake menu entry. Build/publish missing data and
      common packages, then run literal abiword probe.

  - Galculator:
      Known issue from package gate:
        libquadmath.so.0 installed but invisible.
      This is a runtime ladder problem, not necessarily a missing package.
      Fix wrapper dependency closure and validate `galculator --version`.
      VM132 confirms libquadmath0 owns libquadmath.so.0.

  - File:
      Known issue:
        missing libmagic.so.1.
      Build/activate File + Libmagic package together. File is a core diagnostic
      dependency and should be in the debug/workstation base.
      VM132 confirms libmagic1t64 owns libmagic.so.1.

  - Htop/Nano/Ripgrep:
      Prior shakedown showed GLIBC/GLib mismatch symptoms.
      Retest after the glibc 2.41 compatibility promotion. Some of these may now
      be path/runtime ladder fixes rather than rebuilds.
      VM135 inspection confirms Htop is installed, but Nano is not present in
      PackageDB. Htop should be a quick wrapper/runtime retest; Nano should be
      added to the debug/core batch.

  - Calligra:
      Known issue:
        missing libkomain.so.40.
      Lower priority than LibreOffice/OpenOffice unless it becomes a dependency
      magnet for KDE/Qt runtime.
      VM132 confirms calligra-libs owns libkomain.so.40.

  - Desktop activation triggers:
      VM135 activation log still shows broken trigger/runtime behavior:
        update-mime-database cannot load libatomic.so.1
        udevadm reports a GLIBC_PRIVATE symbol lookup error against
        /System/Compatibility/usr/lib/x86_64-linux-gnu/libc.so.6
      This belongs in the base activation/runtime repair batch before more GUI
      packages are declared passing.

  - Curl/package install reliability:
      Previous issue:
        libcurl symbol mismatch curl_global_trace.
      Curl must keep the private-loader/matched-runtime contract unless rebuilt
      against the current base compatibility Libc6.

Next build batches:
  1. Base activation/runtime repair batch
     Purpose: make installed apps see the same stable OS substrate.
     Items:
       Libc6 compatibility promotion package
       AuzixInteractiveShellProfile
       Sudo/PAM runtime
       AuzixUserGroups
       AuzixServiceRuntime
       DBus activation surfaces
       Polkit policy surfaces
       Fontconfig/CA/NSS support
       Uidmap/newuidmap/newgidmap for rootless container mode
       desktop trigger bundle:
         glib-compile-schemas
         update-desktop-database
         update-mime-database
         gtk-update-icon-cache
         fc-cache
       libatomic visibility for shared-mime-info/update-mime-database
       udev/glibc matched-runtime check

  2. Debug/core tools batch
     Purpose: stop flying blind on VM135.
     Items:
       Coreutils
       UtilLinux
       Procps
       File + Libmagic
       LDD/readelf/binutils helpers
       Strace
       Less
       Tar/Gzip/Xz/Zstd
       Git
       Nano
       Htop
       Ripgrep
      VM132 package hints:
        file -> libmagic1t64
        htop/nano -> libncursesw6 + libtinfo6

  3. Desktop editor batch
     Purpose: get a few real native editors working and force GTK/GSettings
     closure correctness.
     Items:
       l3afpad or Leafpad
       Geany
       Pluma
       Gedit optional if GTKSourceView/GSettings are ready
      Immediate fixes:
        repair wrapper generation so command wrapper paths never enter
        LD_LIBRARY_PATH/loader --library-path as library candidates.
        add Geany + geany-common package pair from VM132 dependency spine.
     Literal probes:
       --version
       open sample text/source file
       menu launch through E

  4. Office completion batch
     Purpose: turn working Calc/Writer into a small office group.
     Items:
       LibreOfficeImpress
       LibreOfficeDraw
       LibreOffice Math/Base only after Impress/Draw pass
       AbiWord dependency closure
       Gnumeric revalidation
       Galculator runtime ladder fix
     Literal probes:
       lowriter --version + sample odt
       localc --version + csv->ods conversion
       loimpress --headless --version
       lodraw --headless --version
      Immediate package targets from VM132:
        LibreOfficeDraw
        LibreOfficeImpress
        LibreOfficeUiconfigDraw
        LibreOfficeUiconfigImpress
        Libbox2d2
        Libcdr011
        Libfreehand011
        Libmspub011
        Libpagemaker000
        Libqxp000
        Libvisio011
        Libzmf000

  5. Flatpak system-helper / app adapter batch
     Purpose: make Flatpak useful from the desktop without login walls.
     Items:
       FlatpakSystemHelper
       Bubblewrap / var alias runtime
       OSTree
       XdgDbusProxy
       XdgDesktopPortal
       PolicyKit
       FlatpakRuntimeSupport
       FirefoxFlatpakAdapter
       SublimeFlatpakAdapter
       ZedFlatpakAdapter
       BazaarFlatpakAdapter
     Literal probes:
       flatpak remotes -d
       flatpak install --user flathub org.mozilla.firefox
       flatpak install --user flathub com.sublimehq.SublimeText
       wrapper appears in /Programs and E menu

  6. Container host completion batch
     Purpose: move from filmable host/none networking to normal pod networking.
     Items:
       Podman wrapper/reexec contract package
       Libsubid/Uidmap/newuidmap/newgidmap
       Slirp4netns/Pasta
       Netavark/AardvarkDNS bridge requirements
       iptables/nftables package
       kernel module/sysctl/mount activation
     Literal probes:
       podman pull AUZiX zero/nginx/python
       podman run --network none zero/python
       podman run --network host nginx and HTTP probe
       then bridge-network pod after netavark fix

Installer/package group implication:
  The installer should not just extract packages. It needs staged activation:
    stage 0 filesystem aliases + BusyBox command surface
    stage 1 users/groups/passwd/PAM/sudo/polkit
    stage 2 runtime state: /run, /var, machine-id, dbus, udev, cgroups
    stage 3 package visibility: libs, fonts, desktop files, MIME, icons, schemas
    stage 4 service enablement: sshd, dbus, lightdm, podman
    stage 5 user session: E config, themes, menus, Flatpak remotes
    stage 6 validation: ldd/readelf, command probes, GUI launcher probes,
            podman/flatpak probes

Immediate when lab returns:
  1. Pull VM135 package logs and shell history if available:
       /System/Logs/packages
       /System/State/packages
       /System/PackageDB
       /Users/auzix/.xsession-errors
       /tmp/*install*
       /tmp/*flatpak*
       /tmp/*podman*
  2. Run scripts/watch-auzix-workstation-packages.py if the target has enough
     Python; otherwise run the shell probes manually.
  3. For each failure, capture:
       package
       command/desktop entry
       exact stderr
       ldd/loader output
       missing file/lib/service name
       classification:
         missing package
         installed but not on runtime ladder
         activation surface missing
         permission/group/polkit
         ABI/glibc mismatch
         desktop/menu integration
  4. Feed only the compact failure packet to ai_worker/Ollama.
  5. Build the smallest batch that fixes a class, not a single app.

Priority readback:
Tonight should focus on turning VM135 discoveries into reproducible package
  groups. We already have enough proof that AUZiX is viable. The next win is
  boring and powerful: dependency closure, activation stages, and literal probes
  until the workstation tree can be recreated from packages instead of memory.

Applied repo/VM135 cleanup, 2026-08-11:
  - Added scripts/repair-auzix-desktop-menu.sh.
    It rebuilds the AUZiX Enlightenment/freedesktop menu taxonomy with:
      System, Internet, Office, Graphics, Development, Multimedia, Settings,
      Other
    It normalizes existing desktop entries toward AUZiX /Programs wrappers and
    refreshes desktop/MIME databases when helpers are available.
  - Deployed the menu repair to VM135. It found 18 desktop entries and restored
    AUZiX-path Exec targets for visible apps including Calc, Writer, Gnumeric,
    L3afpad, Midori, NetSurf, Htop, Terminology, and XTerm.
  - Patched scripts/build-auzix-debian-intake-package.sh wrapper generation so
    generated wrappers:
      only add existing directories to runtime search paths,
      dedupe search paths,
      prefer package RootFS library trees before /System/Compatibility,
      and fall back across installed /Programs/*/current/RootFS library dirs
      during alpha workstation builds.
  - Hotfixed VM135 L3afpad wrapper with the proven runtime closure:
      Libcloudproviders0 Libatomic1 Libmount1 Libharfbuzz0b
    Probe result is now display-only failure over SSH rather than missing
    libraries:
      l3afpad: Cannot open display
