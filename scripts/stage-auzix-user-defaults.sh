#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
SOURCE_HOME="${AUZIX_DEFAULTS_HOME:-${HOME}}"
TARGET_HOME="${AUZIX_TARGET_HOME:-${AUZIX_ROOT}/Users/root}"

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
  "${TARGET_HOME}/.e/e" \
  "${TARGET_HOME}/.elementary" \
  "${TARGET_HOME}/Pictures/Wallpapers" \
  "${AUZIX_ROOT}/System/Settings/display/defaults"

copy_filtered_tree "${SOURCE_HOME}/.e/e/config" "${TARGET_HOME}/.e/e/config" \
  --include='*/' \
  --include='*.cfg' \
  --exclude='*'

copy_filtered_tree "${SOURCE_HOME}/.e/e/backgrounds" "${TARGET_HOME}/.e/e/backgrounds" \
  --include='*/' \
  --include='*.edj' \
  --include='*.jpg' \
  --include='*.jpeg' \
  --include='*.png' \
  --exclude='*'

copy_filtered_tree "${SOURCE_HOME}/.e/e/themes" "${TARGET_HOME}/.e/e/themes" \
  --include='*/' \
  --include='*.edj' \
  --exclude='*'

copy_filtered_tree "${SOURCE_HOME}/.e/e/applications" "${TARGET_HOME}/.e/e/applications" \
  --include='*/' \
  --include='*.desktop' \
  --include='*.order' \
  --exclude='*'

copy_filtered_tree "${SOURCE_HOME}/.elementary/themes" "${TARGET_HOME}/.elementary/themes" \
  --include='*/' \
  --include='*.edj' \
  --exclude='*'

copy_filtered_tree "${SOURCE_HOME}/Pictures/Wallpapers" "${TARGET_HOME}/Pictures/Wallpapers" \
  --include='*/' \
  --include='*.jpg' \
  --include='*.jpeg' \
  --include='*.png' \
  --exclude='*'

cat > "${AUZIX_ROOT}/System/Settings/display/defaults/user-defaults-note.txt" <<TXT
User desktop defaults staged from:
  ${SOURCE_HOME}

Target home:
  /Users/root

Only selected Enlightenment config, themes, backgrounds, application launchers,
and wallpaper image formats are copied. Caches, thumbnails, screenshots, logs,
and arbitrary local state are intentionally omitted.
TXT

log "user defaults staged into ${TARGET_HOME}"
