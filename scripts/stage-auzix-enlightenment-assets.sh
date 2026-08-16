#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
SOURCE_HOME="${AUZIX_ASSET_HOME:-${HOME}}"
SOURCE_EXTRA_ROOT="${AUZIX_ASSET_EXTRA_ROOT:-}"
SOURCE_SSH="${AUZIX_ASSET_SSH:-}"
SOURCE_RSYNC_SSH="${AUZIX_ASSET_RSYNC_SSH:-ssh}"
SOURCE_THEME_BUILD="${AUZIX_ASSET_THEME_BUILD:-${SOURCE_HOME}/Enlightenment-Themes/artifacts/bin-e}"
SOURCE_BACKGROUND_BUILD="${AUZIX_ASSET_BACKGROUND_BUILD:-${ROOT_DIR}/../wallpaper}"
SOURCE_REPO_ASSETS="${AUZIX_ASSET_REPO_ROOT:-${ROOT_DIR}/assets/display}"
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

copy_flat_local_assets() {
  local source="$1"
  local target="$2"
  [[ -d "${source}" ]] || return 0
  mkdir -p "${target}"
  find "${source}" -maxdepth 1 -type f \
    \( -name '*.edj' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) \
    -exec cp -f {} "${target}/" \;
  log "staged flat assets ${source} -> ${target}"
}

copy_flat_remote_assets() {
  local source="$1"
  local target="$2"
  [[ -n "${SOURCE_SSH}" ]] || return 0
  mkdir -p "${target}"
  if ${SOURCE_RSYNC_SSH} "${SOURCE_SSH}" "test -d '${source}'" 2>/dev/null; then
    ${SOURCE_RSYNC_SSH} "${SOURCE_SSH}" \
      "cd '${source}' && find . -maxdepth 1 -type f \\( -name '*.edj' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \\) -print0 | tar --null -T - -cf -" \
      2>/dev/null | tar -C "${target}" -xf -
    log "staged flat assets ${SOURCE_SSH}:${source} -> ${target}"
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
copy_tree_if_present "${SOURCE_REPO_ASSETS}/backgrounds" "${ASSET_ROOT}/backgrounds"
copy_tree_if_present "${SOURCE_REPO_ASSETS}/themes" "${ASSET_ROOT}/themes"
if [[ -n "${SOURCE_EXTRA_ROOT}" ]]; then
  copy_tree_if_present "${SOURCE_EXTRA_ROOT}/backgrounds" "${ASSET_ROOT}/backgrounds"
  copy_tree_if_present "${SOURCE_EXTRA_ROOT}/themes" "${ASSET_ROOT}/themes"
fi
copy_flat_local_assets "${SOURCE_BACKGROUND_BUILD}" "${ASSET_ROOT}/backgrounds"
copy_flat_local_assets "${SOURCE_BACKGROUND_BUILD}/themes" "${ASSET_ROOT}/themes"
if [[ -n "${SOURCE_SSH}" ]]; then
  copy_flat_remote_assets "${SOURCE_THEME_BUILD}" "${ASSET_ROOT}/themes"
else
  copy_flat_local_assets "${SOURCE_THEME_BUILD}" "${ASSET_ROOT}/themes"
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

find "${ASSET_ROOT}" -type d -exec chmod 0755 {} + 2>/dev/null || true
find "${ASSET_ROOT}" -type f -exec chmod 0644 {} + 2>/dev/null || true

cat > "${DISPLAY_ROOT}/asset-note.txt" <<TXT
Enlightenment assets staged from:
  ${SOURCE_SSH:+${SOURCE_SSH}:}${SOURCE_HOME}

Themes and backgrounds are exported through Enlightenment's global data paths
by the DesktopAssets package. User profiles inherit them without private copies.
TXT

log "asset staging complete: ${ASSET_ROOT}"
