#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
SOURCE_HOME="${AUZIX_ASSET_HOME:-${HOME}}"
SOURCE_EXTRA_ROOT="${AUZIX_ASSET_EXTRA_ROOT:-}"
SOURCE_SSH="${AUZIX_ASSET_SSH:-}"
SOURCE_RSYNC_SSH="${AUZIX_ASSET_RSYNC_SSH:-ssh}"
DISPLAY_ROOT="${AUZIX_ROOT}/System/Settings/display"
ASSET_ROOT="${DISPLAY_ROOT}/assets"

log() {
  printf '[auzix-e-assets] %s\n' "$*" >&2
}

copy_tree_if_present() {
  local source="$1"
  local target="$2"
  if [[ -n "${SOURCE_SSH}" ]]; then
    mkdir -p "${target}"
    if ${SOURCE_RSYNC_SSH} "${SOURCE_SSH}" "test -d '${source}'" 2>/dev/null; then
      ${SOURCE_RSYNC_SSH} "${SOURCE_SSH}" "tar -C '${source}' -cf - ." 2>/dev/null | tar -C "${target}" -xf -
      find "${target}" -type f \
        ! -name '*.edj' \
        ! -name '*.jpg' \
        ! -name '*.jpeg' \
        ! -name '*.png' \
        -delete
      find "${target}" -type d -empty -delete
    else
      return 0
    fi
    log "staged ${SOURCE_SSH}:${source} -> ${target}"
  elif [[ -d "${source}" ]]; then
    mkdir -p "${target}"
    rsync -a --include='*/' --include='*.edj' --include='*.jpg' --include='*.jpeg' --include='*.png' --exclude='*' "${source}/" "${target}/"
    log "staged ${source} -> ${target}"
  fi
}

if ! command -v rsync >/dev/null 2>&1; then
  printf 'Required command not found: rsync\n' >&2
  exit 1
fi

mkdir -p "${ASSET_ROOT}/backgrounds" "${ASSET_ROOT}/themes" "${ASSET_ROOT}/config"

copy_tree_if_present "${SOURCE_HOME}/.e/e/backgrounds" "${ASSET_ROOT}/backgrounds"
copy_tree_if_present "${SOURCE_HOME}/.e/e/themes" "${ASSET_ROOT}/themes"
copy_tree_if_present "${SOURCE_HOME}/.elementary/themes" "${ASSET_ROOT}/themes"
copy_tree_if_present "${SOURCE_HOME}/Pictures/Wallpapers" "${ASSET_ROOT}/backgrounds"
if [[ -n "${SOURCE_EXTRA_ROOT}" ]]; then
  copy_tree_if_present "${SOURCE_EXTRA_ROOT}/backgrounds" "${ASSET_ROOT}/backgrounds"
  copy_tree_if_present "${SOURCE_EXTRA_ROOT}/themes" "${ASSET_ROOT}/themes"
fi

if [[ -n "${SOURCE_SSH}" ]]; then
  mkdir -p "${ASSET_ROOT}/config"
  if ${SOURCE_RSYNC_SSH} "${SOURCE_SSH}" "test -d '${SOURCE_HOME}/.e/e/config'" 2>/dev/null; then
    ${SOURCE_RSYNC_SSH} "${SOURCE_SSH}" "tar -C '${SOURCE_HOME}/.e/e/config' -cf - ." 2>/dev/null | tar -C "${ASSET_ROOT}/config" -xf -
    find "${ASSET_ROOT}/config" -type f ! -name '*.cfg' -delete
    find "${ASSET_ROOT}/config" -type d -empty -delete
    log "staged selected Enlightenment config from ${SOURCE_SSH}:${SOURCE_HOME}/.e/e/config"
  fi
elif [[ -d "${SOURCE_HOME}/.e/e/config" ]]; then
  mkdir -p "${ASSET_ROOT}/config"
  rsync -a \
    --include='*/' \
    --include='*.cfg' \
    --exclude='*' \
    "${SOURCE_HOME}/.e/e/config/" "${ASSET_ROOT}/config/"
  log "staged selected Enlightenment config from ${SOURCE_HOME}/.e/e/config"
fi

cat > "${DISPLAY_ROOT}/asset-note.txt" <<TXT
Enlightenment assets staged from:
  ${SOURCE_SSH:+${SOURCE_SSH}:}${SOURCE_HOME}

These are not enabled automatically. Use them after EFL/Enlightenment are
installed and the first /System/Tools/start-e session is stable.
TXT

log "asset staging complete: ${ASSET_ROOT}"
