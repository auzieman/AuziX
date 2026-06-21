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

find "${TARGET_HOME}/.e" \
  -type d -exec chmod 0755 {} + 2>/dev/null || true
find "${TARGET_HOME}/.e" \
  -type f -exec chmod 0644 {} + 2>/dev/null || true

cat > "${TARGET_HOME}/.config/autostart/auzix-installer.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Install AuziX
Comment=Start the guided AuziX installer after the desktop session is ready
Exec=/System/Tools/launch-auzix-installer --autostart
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

chmod 0644 "${TARGET_HOME}/.config/autostart/auzix-installer.desktop"
chown -R 1000:1000 "${TARGET_HOME}/.config" 2>/dev/null || true

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
