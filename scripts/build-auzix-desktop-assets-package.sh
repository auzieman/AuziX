#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
ASSET_ROOT="${AUZIX_ROOT}/System/Settings/display/assets"
ASSET_PROGRAM="${AUZIX_ROOT}/Programs/DesktopAssets/auzietek"
RECEIPT="${AUZIX_ROOT}/System/PackageDB/DesktopAssets-auzietek.auzix.json"

log() {
  printf '[auzix-desktop-assets] %s\n' "$*" >&2
}

if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

if [[ ! -d "${ASSET_ROOT}" ]]; then
  printf 'No staged display assets found: %s\n' "${ASSET_ROOT}" >&2
  printf 'Run scripts/stage-auzix-enlightenment-assets.sh first.\n' >&2
  exit 1
fi

rm -rf "${ASSET_PROGRAM}"
mkdir -p \
  "${ASSET_PROGRAM}/Resources/display/assets" \
  "${AUZIX_ROOT}/System/Settings/display" \
  "${AUZIX_ROOT}/System/PackageDB"

rsync -a \
  --include='*/' \
  --include='*.edj' \
  --include='*.jpg' \
  --include='*.jpeg' \
  --include='*.png' \
  --exclude='*' \
  "${ASSET_ROOT}/" "${ASSET_PROGRAM}/Resources/display/assets/"

rm -rf "${AUZIX_ROOT}/System/Settings/display/assets"
ln -sfn /Programs/DesktopAssets/auzietek/Resources/display/assets \
  "${AUZIX_ROOT}/System/Settings/display/assets"

asset_count="$(find "${ASSET_PROGRAM}/Resources/display/assets" -type f | wc -l | tr -d ' ')"
asset_size="$(du -sb "${ASSET_PROGRAM}/Resources/display/assets" | awk '{print $1}')"

cat > "${ASSET_PROGRAM}/Resources/display/assets/README.auzix-assets.txt" <<EOF
AuziTek desktop asset pack.

This package carries selected Enlightenment backgrounds, themes, and display
assets. Themes are intentionally staged but not force-enabled because E themes
are tightly coupled to the packaged EFL/Enlightenment generation.
EOF

cat > "${RECEIPT}" <<EOF
{
  "name": "DesktopAssets",
  "version": "auzietek",
  "kind": "assets",
  "migration_stage": "stage-1-optional-personal-spin",
  "prefix": "/Programs/DesktopAssets/auzietek",
  "paths": {
    "assets": "/Programs/DesktopAssets/auzietek/Resources/display/assets"
  },
  "settings": [],
  "asset_count": ${asset_count},
  "asset_size": ${asset_size},
  "compatibility_exports": [],
  "notes": "Optional personal desktop asset pack. It is not part of the default reproducible build."
}
EOF

log "DesktopAssets package staged with ${asset_count} files under ${ASSET_PROGRAM}"
