#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
VERSION="${AUZIX_DESKTOP_INTEGRATION_VERSION:-2026.08.09}"
PROGRAM="${AUZIX_ROOT}/Programs/AuzixDesktopIntegration/${VERSION}"
RECEIPT="${AUZIX_ROOT}/System/PackageDB/AuzixDesktopIntegration-${VERSION}.auzix.json"

mkdir -p \
  "${PROGRAM}/Commands" \
  "${PROGRAM}/Resources/xdg/menus" \
  "${PROGRAM}/Resources/desktop-directories" \
  "${PROGRAM}/Resources/applications" \
  "${PROGRAM}/Resources/config" \
  "${AUZIX_ROOT}/System/PackageDB"

cat >"${PROGRAM}/Resources/desktop-directories/auzix-productivity.directory" <<'EOF'
[Desktop Entry]
Type=Directory
Name=Productivity
Comment=Office, documents, spreadsheets, presentations, and publishing
Icon=applications-office
EOF

cat >"${PROGRAM}/Resources/desktop-directories/auzix-office.directory" <<'EOF'
[Desktop Entry]
Type=Directory
Name=Office Suite
Comment=AUZiX office suite review applications
Icon=applications-office
EOF

cat >"${PROGRAM}/Resources/desktop-directories/auzix-internet.directory" <<'EOF'
[Desktop Entry]
Type=Directory
Name=Internet
Comment=Web, mail, chat, and network applications
Icon=applications-internet
EOF

cat >"${PROGRAM}/Resources/desktop-directories/auzix-graphics.directory" <<'EOF'
[Desktop Entry]
Type=Directory
Name=Graphics
Comment=Image, drawing, photo, and publishing tools
Icon=applications-graphics
EOF

cat >"${PROGRAM}/Resources/desktop-directories/auzix-multimedia.directory" <<'EOF'
[Desktop Entry]
Type=Directory
Name=Multimedia
Comment=Audio, video, and media applications
Icon=applications-multimedia
EOF

cat >"${PROGRAM}/Resources/desktop-directories/auzix-development.directory" <<'EOF'
[Desktop Entry]
Type=Directory
Name=Development
Comment=Editors, terminals, source tools, and diagnostics
Icon=applications-development
EOF

cat >"${PROGRAM}/Resources/desktop-directories/auzix-system.directory" <<'EOF'
[Desktop Entry]
Type=Directory
Name=System
Comment=System tools, settings, installer, and packages
Icon=applications-system
EOF

cat >"${PROGRAM}/Resources/desktop-directories/auzix-utilities.directory" <<'EOF'
[Desktop Entry]
Type=Directory
Name=Utilities
Comment=Small tools and accessories
Icon=applications-utilities
EOF

cat >"${PROGRAM}/Resources/xdg/menus/e-applications.menu" <<'EOF'
<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN" "http://www.freedesktop.org/standards/menu-spec/menu-1.0.dtd">
<Menu>
  <Name>Applications</Name>
  <DefaultAppDirs/>
  <AppDir>/System/Compatibility/usr/share/applications</AppDir>
  <DefaultDirectoryDirs/>
  <DirectoryDir>/System/Compatibility/usr/share/desktop-directories</DirectoryDir>

  <Menu>
    <Name>Productivity</Name>
    <Directory>auzix-productivity.directory</Directory>
    <Menu>
      <Name>Office Suite</Name>
      <Directory>auzix-office.directory</Directory>
      <Include>
        <Category>Office</Category>
      </Include>
      <Exclude>
        <Filename>auzix-office-review.desktop</Filename>
      </Exclude>
    </Menu>
    <Include>
      <Filename>auzix-office-review.desktop</Filename>
      <Category>WordProcessor</Category>
      <Category>Spreadsheet</Category>
      <Category>Presentation</Category>
      <Category>Database</Category>
    </Include>
  </Menu>

  <Menu>
    <Name>Internet</Name>
    <Directory>auzix-internet.directory</Directory>
    <Include>
      <Category>Network</Category>
      <Category>WebBrowser</Category>
      <Category>Email</Category>
      <Category>Chat</Category>
    </Include>
  </Menu>

  <Menu>
    <Name>Graphics</Name>
    <Directory>auzix-graphics.directory</Directory>
    <Include>
      <Category>Graphics</Category>
      <Category>Photography</Category>
      <Category>RasterGraphics</Category>
      <Category>VectorGraphics</Category>
      <Category>2DGraphics</Category>
    </Include>
    <Exclude>
      <Category>Office</Category>
    </Exclude>
  </Menu>

  <Menu>
    <Name>Multimedia</Name>
    <Directory>auzix-multimedia.directory</Directory>
    <Include>
      <Category>AudioVideo</Category>
      <Category>Audio</Category>
      <Category>Video</Category>
      <Category>Player</Category>
    </Include>
  </Menu>

  <Menu>
    <Name>Development</Name>
    <Directory>auzix-development.directory</Directory>
    <Include>
      <Category>Development</Category>
      <Category>IDE</Category>
      <Category>TextEditor</Category>
      <Category>TerminalEmulator</Category>
    </Include>
  </Menu>

  <Menu>
    <Name>Utilities</Name>
    <Directory>auzix-utilities.directory</Directory>
    <Include>
      <Category>Utility</Category>
      <Category>FileManager</Category>
    </Include>
  </Menu>

  <Menu>
    <Name>System</Name>
    <Directory>auzix-system.directory</Directory>
    <Include>
      <Category>System</Category>
      <Category>Settings</Category>
    </Include>
  </Menu>

  <Menu>
    <Name>Other</Name>
    <Directory>auzix-other.directory</Directory>
    <OnlyUnallocated/>
    <Include><All/></Include>
  </Menu>
</Menu>
EOF

cat >"${PROGRAM}/Resources/config/mimeapps.list" <<'EOF'
[Default Applications]
application/vnd.oasis.opendocument.spreadsheet=auzix-libreoffice-calc.desktop
application/vnd.oasis.opendocument.text=auzix-libreoffice-writer.desktop
application/vnd.oasis.opendocument.presentation=auzix-libreoffice-impress.desktop
application/vnd.oasis.opendocument.graphics=auzix-libreoffice-draw.desktop
application/vnd.oasis.opendocument.formula=auzix-libreoffice-math.desktop
application/vnd.oasis.opendocument.database=auzix-libreoffice-base.desktop
text/csv=auzix-libreoffice-calc.desktop
text/plain=auzix-libreoffice-writer.desktop
application/rtf=auzix-libreoffice-writer.desktop
application/msword=auzix-libreoffice-writer.desktop
application/vnd.openxmlformats-officedocument.wordprocessingml.document=auzix-libreoffice-writer.desktop
application/vnd.ms-excel=auzix-libreoffice-calc.desktop
application/vnd.openxmlformats-officedocument.spreadsheetml.sheet=auzix-libreoffice-calc.desktop
application/vnd.ms-powerpoint=auzix-libreoffice-impress.desktop
application/vnd.openxmlformats-officedocument.presentationml.presentation=auzix-libreoffice-impress.desktop

[Added Associations]
application/vnd.oasis.opendocument.spreadsheet=auzix-libreoffice-calc.desktop;auzix-gnumeric.desktop;
application/vnd.oasis.opendocument.text=auzix-libreoffice-writer.desktop;auzix-abiword.desktop;
text/csv=auzix-libreoffice-calc.desktop;auzix-gnumeric.desktop;
text/plain=auzix-libreoffice-writer.desktop;auzix-abiword.desktop;
EOF

cat >"${PROGRAM}/Resources/applications/auzix-midori.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Midori
Comment=Midori web browser
Exec=/Programs/Midori/current/Commands/midori %U
Icon=web-browser
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
EOF

cat >"${PROGRAM}/Resources/applications/auzix-netsurf.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=NetSurf
Comment=NetSurf web browser
Exec=/Programs/NetSurf/current/Commands/netsurf %U
Icon=web-browser
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
EOF

cat >"${PROGRAM}/Resources/applications/auzix-flatpak.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Flatpak
Comment=Flatpak command line package/runtime tool
Exec=/Programs/Flatpak/current/Commands/flatpak --help
Icon=application-x-executable
Terminal=true
Categories=System;PackageManager;
EOF

cat >"${PROGRAM}/Commands/activate" <<EOF
#!/Programs/BusyBox/current/Commands/busybox sh
set -eu
BB=/Programs/BusyBox/current/Commands/busybox
prefix=/Programs/AuzixDesktopIntegration/current

"\${BB}" mkdir -p \\
  /etc/xdg/menus \\
  /System/Compatibility/usr/share/desktop-directories \\
  /System/Compatibility/usr/share/applications \\
  /Users/auzix/.config \\
  /Users/auzix/.local/share/applications

"\${BB}" cp "\${prefix}/Resources/xdg/menus/e-applications.menu" /etc/xdg/menus/e-applications.menu
for item in "\${prefix}"/Resources/desktop-directories/*.directory; do
  [ -f "\${item}" ] || continue
  "\${BB}" cp "\${item}" "/System/Compatibility/usr/share/desktop-directories/\${item##*/}"
done
for item in "\${prefix}"/Resources/applications/*.desktop; do
  [ -f "\${item}" ] || continue
  "\${BB}" cp "\${item}" "/System/Compatibility/usr/share/applications/\${item##*/}"
done
"\${BB}" cp "\${prefix}/Resources/config/mimeapps.list" /Users/auzix/.config/mimeapps.list
"\${BB}" cp "\${prefix}/Resources/config/mimeapps.list" /Users/auzix/.local/share/applications/mimeapps.list
"\${BB}" chown -R auzix:auzix /Users/auzix/.config /Users/auzix/.local/share 2>/dev/null || true

if "\${BB}" pidof enlightenment >/dev/null 2>&1; then
  (
    "\${BB}" sleep 1
    "\${BB}" su auzix -c 'DISPLAY=:0 HOME=/Users/auzix XDG_RUNTIME_DIR=/run/user/1000 enlightenment_remote -restart' \\
      >/System/Logs/packages/enlightenment-menu-restart.log 2>&1 || true
  ) &
fi
EOF
chmod 0755 "${PROGRAM}/Commands/activate"

cat >"${PROGRAM}/Commands/e-launcher-sync" <<'EOF'
#!/Programs/BusyBox/current/Commands/busybox sh
set -eu
BB=/Programs/BusyBox/current/Commands/busybox
APPDIR=/System/Compatibility/usr/share/applications
EBASE=/Users/auzix/.e/e/applications
ALL="${EBASE}/menu/all"
FAV="${EBASE}/menu/favorite"
BAR="${EBASE}/bar/default"

"${BB}" mkdir -p "${ALL}" "${FAV}" "${BAR}"

# Only publish the current desktop-ready baseline.  Package install hooks may
# extend this once their watcher contract passes; failed-smoke entries stay out.
approved='
auzix-libreoffice-startcenter.desktop
auzix-libreoffice-calc.desktop
auzix-libreoffice-writer.desktop
auzix-libreoffice-impress.desktop
auzix-libreoffice-draw.desktop
auzix-libreoffice-math.desktop
auzix-libreoffice-base.desktop
auzix-AbiWord-abiword.desktop
auzix-abiword.desktop
auzix-Gnumeric-org.gnumeric.gnumeric.desktop
auzix-gnumeric.desktop
auzix-Geany-geany.desktop
auzix-Pluma-pluma.desktop
auzix-Micro-micro.desktop
auzix-Htop-htop.desktop
auzix-Galculator-galculator.desktop
auzix-midori.desktop
auzix-netsurf.desktop
netsurf-gtk.desktop
io.github.kolunmi.Bazaar.desktop
auzix-flatpak.desktop
'

for name in ${approved}; do
  [ -f "${APPDIR}/${name}" ] || continue
  "${BB}" cp "${APPDIR}/${name}" "${ALL}/${name}"
done

"${BB}" cat >"${BAR}/.order" <<'ORDER'
auzix-midori.desktop
auzix-libreoffice-calc.desktop
auzix-libreoffice-writer.desktop
auzix-AbiWord-abiword.desktop
auzix-Geany-geany.desktop
auzix-Pluma-pluma.desktop
auzix-Micro-micro.desktop
ORDER

"${BB}" cat >"${FAV}/.order" <<'ORDER'
auzix-midori.desktop
auzix-netsurf.desktop
auzix-libreoffice-startcenter.desktop
auzix-libreoffice-calc.desktop
auzix-libreoffice-writer.desktop
auzix-AbiWord-abiword.desktop
auzix-Gnumeric-org.gnumeric.gnumeric.desktop
auzix-Geany-geany.desktop
auzix-Pluma-pluma.desktop
auzix-Micro-micro.desktop
auzix-Htop-htop.desktop
auzix-flatpak.desktop
ORDER

"${BB}" chown -R auzix:auzix "${EBASE}" 2>/dev/null || true
if "${BB}" pidof enlightenment >/dev/null 2>&1; then
  "${BB}" su auzix -c 'DISPLAY=:0 HOME=/Users/auzix XDG_RUNTIME_DIR=/run/user/1000 enlightenment_remote -restart' \
    >/System/Logs/packages/enlightenment-launcher-sync.log 2>&1 || true
fi
EOF
chmod 0755 "${PROGRAM}/Commands/e-launcher-sync"

ln -sfn "/Programs/AuzixDesktopIntegration/${VERSION}" "${AUZIX_ROOT}/Programs/AuzixDesktopIntegration/current"

cat >"${RECEIPT}" <<EOF
{
  "name": "AuzixDesktopIntegration",
  "version": "${VERSION}",
  "kind": "desktop-integration",
  "migration_stage": "stage-1-workstation-proof",
  "prefix": "/Programs/AuzixDesktopIntegration/${VERSION}",
  "depends": ["BusyBox", "Enlightenment"],
  "commands": [
    "/Programs/AuzixDesktopIntegration/${VERSION}/Commands/activate",
    "/Programs/AuzixDesktopIntegration/${VERSION}/Commands/e-launcher-sync"
  ],
  "hooks": {
    "post_install": "/Programs/AuzixDesktopIntegration/${VERSION}/Commands/activate",
    "desktop_sync": "/Programs/AuzixDesktopIntegration/${VERSION}/Commands/e-launcher-sync"
  },
  "compatibility_exports": [
    "/etc/xdg/menus/e-applications.menu",
    "/System/Compatibility/usr/share/desktop-directories/auzix-productivity.directory",
    "/System/Compatibility/usr/share/desktop-directories/auzix-office.directory",
    "/System/Compatibility/usr/share/desktop-directories/auzix-internet.directory",
    "/System/Compatibility/usr/share/desktop-directories/auzix-graphics.directory",
    "/System/Compatibility/usr/share/desktop-directories/auzix-multimedia.directory",
    "/System/Compatibility/usr/share/desktop-directories/auzix-development.directory",
    "/System/Compatibility/usr/share/desktop-directories/auzix-system.directory",
    "/System/Compatibility/usr/share/desktop-directories/auzix-utilities.directory",
    "/System/Compatibility/usr/share/applications/auzix-midori.desktop",
    "/System/Compatibility/usr/share/applications/auzix-netsurf.desktop",
    "/System/Compatibility/usr/share/applications/auzix-flatpak.desktop",
    "/Users/auzix/.config/mimeapps.list",
    "/Users/auzix/.local/share/applications/mimeapps.list"
  ],
  "notes": "Curated AUZiX XDG/E menu tree, baseline browser/package-manager launchers, and open-with defaults. Keeps unvalidated launchers out of the main desktop-ready path."
}
EOF

printf '[auzix-desktop-integration] staged %s at %s\n' "${VERSION}" "${PROGRAM}" >&2
