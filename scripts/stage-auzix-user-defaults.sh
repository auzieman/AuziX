#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
SOURCE_HOME="${AUZIX_DEFAULTS_HOME:-${HOME}}"
TARGET_HOME="${AUZIX_TARGET_HOME:-${AUZIX_ROOT}/Users/auzix}"

log() {
  printf '[auzix-user-defaults] %s\n' "$*" >&2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

copy_filtered_tree() {
  local source="$1"
  local target="$2"
  shift 2
  [[ -d "${source}" ]] || return 0
  mkdir -p "${target}"
  rsync -a --prune-empty-dirs "$@" "${source}/" "${target}/"
  log "staged ${source} -> ${target}"
}

require_cmd rsync

mkdir -p \
  "${TARGET_HOME}/.e/e/config" \
  "${TARGET_HOME}/.config/autostart" \
  "${TARGET_HOME}/Desktop" \
  "${AUZIX_ROOT}/System/Settings/display/defaults"

copy_filtered_tree "${SOURCE_HOME}/.e/e/config" "${TARGET_HOME}/.e/e/config" \
  --include='*/' \
  --include='*.cfg' \
  --exclude='*'

copy_filtered_tree "${SOURCE_HOME}/.e/e/applications" "${TARGET_HOME}/.e/e/applications" \
  --include='*/' \
  --include='*.desktop' \
  --include='*.order' \
  --exclude='*'

copy_filtered_tree "${SOURCE_HOME}/.elementary/config" "${TARGET_HOME}/.elementary/config" \
  --include='*/' \
  --include='*.cfg' \
  --exclude='*'

E_CONFIG_ROOT="${AUZIX_E_CONFIG_ROOT:-/usr/share/enlightenment/data/config}"
if [[ ! -s "${TARGET_HOME}/.e/e/config/standard/e.cfg" && -d "${E_CONFIG_ROOT}" ]]; then
  for profile in standard default; do
    [[ -d "${E_CONFIG_ROOT}/${profile}" ]] || continue
    mkdir -p "${TARGET_HOME}/.e/e/config/${profile}"
    rsync -a --include='*/' --include='*.cfg' --exclude='*' \
      "${E_CONFIG_ROOT}/${profile}/" "${TARGET_HOME}/.e/e/config/${profile}/"
    log "seeded packaged Enlightenment ${profile} config"
  done
fi

if [[ ! -s "${TARGET_HOME}/.e/e/config/profile.cfg" ]] && command -v eet >/dev/null 2>&1; then
  profile_tmp="$(mktemp)"
  printf standard > "${profile_tmp}"
  eet -i "${TARGET_HOME}/.e/e/config/profile.cfg" config "${profile_tmp}" 0 2>/dev/null || true
  rm -f "${profile_tmp}"
fi

E_MODULE_ROOT="${AUZIX_E_MODULE_ROOT:-${AUZIX_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/modules}"
if [[ -d "${E_MODULE_ROOT}" ]]; then
  while IFS= read -r cfg; do
    module="$(basename "${cfg}")"
    module="${module#module.}"
    module="${module%%.cfg*}"
    [[ -n "${module}" ]] || continue
    [[ -d "${E_MODULE_ROOT}/${module}" ]] && continue
    [[ -d "${E_MODULE_ROOT}/${module//_/-}" ]] && continue
    mkdir -p "$(dirname "${cfg}")/disabled-auzix-missing-modules"
    mv -f "${cfg}" "$(dirname "${cfg}")/disabled-auzix-missing-modules/" 2>/dev/null || true
    log "disabled stale Enlightenment module config: ${module}"
  done < <(find "${TARGET_HOME}/.e/e/config" -type f -name 'module.*.cfg*' 2>/dev/null)
fi

find "${TARGET_HOME}/.e" \
  -type d -exec chmod 0755 {} + 2>/dev/null || true
find "${TARGET_HOME}/.e" \
  -type f -exec chmod 0644 {} + 2>/dev/null || true
find "${TARGET_HOME}/.elementary" \
  -type d -exec chmod 0755 {} + 2>/dev/null || true
find "${TARGET_HOME}/.elementary" \
  -type f -exec chmod 0644 {} + 2>/dev/null || true

# The live ISO is staged as root, but Enlightenment writes randr, profile, and
# wizard/session state during first launch.  If these trees remain root-owned,
# E can render far enough to look alive and then pause or fail on writes such as
# ~/.e/e/config/default/e_randr2.cfg.tmp.
chown -R 1000:1000 "${TARGET_HOME}/.e" 2>/dev/null || true
chown -R 1000:1000 "${TARGET_HOME}/.elementary" 2>/dev/null || true

cat > "${TARGET_HOME}/.config/autostart/auzix-installer.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Install AuziX
Comment=Desktop launcher is preferred; do not start the installer unattended
Exec=/System/Tools/launch-auzix-installer --autostart
Terminal=false
X-GNOME-Autostart-enabled=false
Hidden=true
EOF

chmod 0644 "${TARGET_HOME}/.config/autostart/auzix-installer.desktop"

cat > "${TARGET_HOME}/Desktop/Install AuziX.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Install AuziX
Comment=Start the guided AuziX installer
Exec=/System/Tools/launch-auzix-installer
Icon=drive-harddisk
Terminal=false
Categories=System;Settings;
EOF
chmod 0755 "${TARGET_HOME}/Desktop/Install AuziX.desktop"

cat > "${TARGET_HOME}/Desktop/AUZiX Rescue Terminal.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=AUZiX Rescue Terminal
Comment=Open a reliable rescue shell
Exec=/System/Tools/launch-rescue-terminal
Icon=utilities-terminal
Terminal=false
Categories=System;TerminalEmulator;
EOF
chmod 0755 "${TARGET_HOME}/Desktop/AUZiX Rescue Terminal.desktop"

cat > "${TARGET_HOME}/Desktop/AUZiX Browser.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=AUZiX Browser
Comment=Open the AUZiX web start page
Exec=/System/Tools/launch-auzix-browser https://auzietek.com
Icon=web-browser
Terminal=false
Categories=Network;WebBrowser;
EOF
chmod 0755 "${TARGET_HOME}/Desktop/AUZiX Browser.desktop"

cat > "${TARGET_HOME}/Desktop/AUZiX Files.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=AUZiX Files
Comment=Open the Enlightenment file manager
Exec=/System/Tools/launch-auzix-files
Icon=system-file-manager
Terminal=false
Categories=System;FileManager;
EOF
chmod 0755 "${TARGET_HOME}/Desktop/AUZiX Files.desktop"

chown -R 1000:1000 "${TARGET_HOME}/.config" 2>/dev/null || true
chown -R 1000:1000 "${TARGET_HOME}/Desktop" 2>/dev/null || true

cat > "${AUZIX_ROOT}/System/Settings/display/defaults/user-defaults-note.txt" <<TXT
User desktop defaults staged from:
  ${SOURCE_HOME}

Target home:
  ${TARGET_HOME#"${AUZIX_ROOT}"}

Only selected Enlightenment config, application launchers, and the installer
autostart entry are copied. Themes and backgrounds belong to the global
DesktopAssets package. Caches, thumbnails, screenshots, logs, and arbitrary
local state are omitted.
TXT

log "user defaults staged into ${TARGET_HOME}"
