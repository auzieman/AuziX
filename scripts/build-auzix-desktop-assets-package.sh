#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
ASSET_ROOT="${AUZIX_ROOT}/System/Settings/display/assets"
ASSET_SOURCE_ROOT="${ASSET_ROOT}"
ASSET_PROGRAM="${AUZIX_ROOT}/Programs/DesktopAssets/auzietek"
RECEIPT="${AUZIX_ROOT}/System/PackageDB/DesktopAssets-auzietek.auzix.json"
GLOBAL_E_ROOT="${AUZIX_ROOT}/System/Compatibility/usr/share/enlightenment"
# VM135 process evidence proved that this Elive/EFL build opens themes from
# the Elementary catalog, while wallpapers remain in Enlightenment's catalog.
GLOBAL_THEMES="${AUZIX_ROOT}/System/Compatibility/usr/share/elementary/themes"
GLOBAL_BACKGROUNDS="${GLOBAL_E_ROOT}/data/backgrounds"
GLOBAL_TERMINOLOGY_THEMES="${AUZIX_ROOT}/System/Compatibility/usr/share/terminology/themes"
STAGED_COPY="$(mktemp -d)"

trap 'rm -rf "${STAGED_COPY}"' EXIT

log() {
  printf '[auzix-desktop-assets] %s\n' "$*" >&2
}

for command_name in find jq readlink rsync; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "${command_name}" >&2
    exit 1
  fi
done

if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

if [[ -L "${ASSET_ROOT}" ]]; then
  asset_link="$(readlink "${ASSET_ROOT}")"
  if [[ "${asset_link}" = /* ]]; then
    ASSET_SOURCE_ROOT="${AUZIX_ROOT}${asset_link}"
  else
    ASSET_SOURCE_ROOT="$(dirname "${ASSET_ROOT}")/${asset_link}"
  fi
fi

if [[ ! -d "${ASSET_SOURCE_ROOT}" ]]; then
  printf 'No staged display assets found: %s\n' "${ASSET_ROOT}" >&2
  printf 'Run scripts/stage-auzix-enlightenment-assets.sh first.\n' >&2
  exit 1
fi

rsync -a \
  --include='*/' \
  --include='*.edj' \
  --include='*.jpg' \
  --include='*.jpeg' \
  --include='*.png' \
  --include='*.cfg' \
  --exclude='*' \
  "${ASSET_SOURCE_ROOT}/" "${STAGED_COPY}/"

rm -rf "${ASSET_PROGRAM}"
mkdir -p \
  "${ASSET_PROGRAM}/Resources/display/assets" \
  "${GLOBAL_THEMES}" \
  "${GLOBAL_BACKGROUNDS}" \
  "${GLOBAL_TERMINOLOGY_THEMES}" \
  "${AUZIX_ROOT}/System/Settings/display" \
  "${AUZIX_ROOT}/System/PackageDB"

rsync -a "${STAGED_COPY}/" "${ASSET_PROGRAM}/Resources/display/assets/"

rm -rf "${AUZIX_ROOT}/System/Settings/display/assets"
ln -sfn /Programs/DesktopAssets/auzietek/Resources/display/assets \
  "${AUZIX_ROOT}/System/Settings/display/assets"

for asset in "${ASSET_PROGRAM}"/Resources/display/assets/themes/*.edj; do
  [[ -f "${asset}" ]] || continue
  case "$(basename "${asset}" | tr '[:upper:]' '[:lower:]')" in
    *terminology*)
      install -D -m 0644 "${asset}" "${GLOBAL_TERMINOLOGY_THEMES}/$(basename "${asset}")"
      ;;
    *)
      install -D -m 0644 "${asset}" "${GLOBAL_THEMES}/$(basename "${asset}")"
      ;;
  esac
done

default_theme="${ASSET_PROGRAM}/Resources/display/assets/themes/Transient-Color.edj"
if [[ ! -f "${default_theme}" ]]; then
  default_theme="${ASSET_PROGRAM}/Resources/display/assets/themes/Transient.edj"
fi
if [[ ! -f "${default_theme}" ]]; then
  default_theme="${ASSET_PROGRAM}/Resources/display/assets/themes/Dark.edj"
fi
if [[ -f "${default_theme}" ]]; then
  install -D -m 0644 "${default_theme}" "${GLOBAL_THEMES}/default.edj"
  install -D -m 0644 "${default_theme}" "${GLOBAL_TERMINOLOGY_THEMES}/default.edj"
fi

for asset in "${ASSET_PROGRAM}"/Resources/display/assets/backgrounds/*; do
  [[ -f "${asset}" ]] || continue
  case "${asset}" in
    *.edj|*.jpg|*.jpeg|*.png|*.JPG|*.JPEG|*.PNG) ;;
    *) continue ;;
  esac
  install -D -m 0644 "${asset}" "${GLOBAL_BACKGROUNDS}/$(basename "${asset}")"
done

chown -R 0:0 "${ASSET_PROGRAM}" "${GLOBAL_THEMES}" "${GLOBAL_BACKGROUNDS}" "${GLOBAL_TERMINOLOGY_THEMES}" 2>/dev/null || true
find "${ASSET_PROGRAM}" "${GLOBAL_THEMES}" "${GLOBAL_BACKGROUNDS}" "${GLOBAL_TERMINOLOGY_THEMES}" -type d -exec chmod 0755 {} + 2>/dev/null || true
find "${ASSET_PROGRAM}" "${GLOBAL_THEMES}" "${GLOBAL_BACKGROUNDS}" "${GLOBAL_TERMINOLOGY_THEMES}" -type f -exec chmod 0644 {} + 2>/dev/null || true

asset_count="$(find "${ASSET_PROGRAM}/Resources/display/assets" -type f | wc -l | tr -d ' ')"
asset_size="$(du -sb "${ASSET_PROGRAM}/Resources/display/assets" | awk '{print $1}')"
exports_json="$(
  {
    find "${GLOBAL_THEMES}" -maxdepth 1 -type f -printf '/%P\n' |
      sed "s#^/#/System/Compatibility/usr/share/elementary/themes/#"
    find "${GLOBAL_BACKGROUNDS}" -maxdepth 1 -type f -printf '/%P\n' |
      sed "s#^/#/System/Compatibility/usr/share/enlightenment/data/backgrounds/#"
    find "${GLOBAL_TERMINOLOGY_THEMES}" -maxdepth 1 -type f -printf '/%P\n' |
      sed "s#^/#/System/Compatibility/usr/share/terminology/themes/#"
  } | sort -u | jq -R . | jq -s .
)"

cat > "${ASSET_PROGRAM}/Resources/display/assets/README.auzix-assets.txt" <<EOF
AuziTek desktop asset pack.

This package carries selected Enlightenment backgrounds and themes. Assets are
exported into E's global data directories so every user inherits the catalog.
The live/demo default theme export points default.edj at Transient-Color when
present, then Transient, then Dark.  User profile selection remains writable.
EOF

cat > "${RECEIPT}" <<EOF
{
  "name": "DesktopAssets",
  "version": "auzietek",
  "kind": "assets",
  "migration_stage": "stage-1-optional-personal-spin",
  "prefix": "/Programs/DesktopAssets/auzietek",
  "depends": [
    "Enlightenment"
  ],
  "paths": {
    "assets": "/Programs/DesktopAssets/auzietek/Resources/display/assets"
  },
  "global_exports": {
    "themes": "/System/Compatibility/usr/share/elementary/themes",
    "terminology_themes": "/System/Compatibility/usr/share/terminology/themes",
    "backgrounds": "/System/Compatibility/usr/share/enlightenment/data/backgrounds"
  },
  "settings": [],
  "asset_count": ${asset_count},
  "asset_size": ${asset_size},
  "compatibility_exports": ${exports_json},
  "notes": "Optional personal desktop asset pack exported through Enlightenment's global theme and background directories. It is not part of the default reproducible build."
}
EOF

log "DesktopAssets package staged with ${asset_count} files under ${ASSET_PROGRAM}"
