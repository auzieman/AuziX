#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
SOURCE="${AUZIX_ROOT}/Programs/DesktopAssets/auzietek/Resources/display/assets"
GLOBAL_E="${AUZIX_ROOT}/System/Compatibility/usr/share/enlightenment"
VERSION="${AUZIX_DESKTOP_ASSET_VERSION:-2026.06}"

log() {
  printf '[auzix-desktop-repo] %s\n' "$*" >&2
}

for command_name in file find install jq rsync; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    printf 'Required command not found: %s\n' "${command_name}" >&2
    exit 1
  }
done

[[ -d "${SOURCE}/themes" && -d "${SOURCE}/backgrounds" ]] || {
  printf 'DesktopAssets source is missing under %s\n' "${SOURCE}" >&2
  exit 1
}

find_auzix_eet_command() {
  local receipt command_path
  receipt="$(find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f \
    -name 'LibeetBin-*.auzix.json' | sort | tail -1)"
  if [[ -n "${receipt}" ]]; then
    command_path="$(jq -r '.commands[]? | select(test("/eet$"))' "${receipt}" | head -1)"
    if [[ -n "${command_path}" && -x "${AUZIX_ROOT}${command_path}" ]]; then
      printf '%s\n' "${command_path}"
      return 0
    fi
  fi
  return 1
}

EET_COMMAND="$(find_auzix_eet_command || true)"
EET_COMMAND_IS_AUZIX=0
if [[ -z "${EET_COMMAND}" && -x "${ROOT_DIR}/scripts/build-auzix-debian-intake-package.sh" ]]; then
  "${ROOT_DIR}/scripts/build-auzix-debian-intake-package.sh" "${AUZIX_ROOT}" libeet-bin
  EET_COMMAND="$(find_auzix_eet_command || true)"
fi
if [[ -n "${EET_COMMAND}" ]]; then
  EET_COMMAND_IS_AUZIX=1
elif [[ -z "${EET_COMMAND}" ]]; then
  if command -v eet >/dev/null 2>&1; then
    EET_COMMAND="$(command -v eet)"
  else
    printf 'Required command not found: eet; install/stage libeet-bin first.\n' >&2
    exit 1
  fi
fi

eet_list() {
  local asset="$1"
  if [[ "${EET_COMMAND_IS_AUZIX}" == "1" ]]; then
    local asset_path="${asset}"
    case "${asset_path}" in
      "${AUZIX_ROOT}"/*) asset_path="/${asset_path#"${AUZIX_ROOT}/"}" ;;
    esac
    chroot "${AUZIX_ROOT}" "${EET_COMMAND}" -l "${asset_path}" >/dev/null 2>&1
  else
    "${EET_COMMAND}" -l "${asset}" >/dev/null 2>&1
  fi
}

write_activation_hook() {
  local program_root="$1"
  local asset_kind="$2"
  local source_dir="$3"
  local export_dir="$4"

  mkdir -p "${program_root}/Commands"
  cat >"${program_root}/Commands/activate" <<EOF
#!/System/Compatibility/bin/sh
set -eu

BB=/Programs/BusyBox/1.36.1/Commands/busybox
SOURCE=${source_dir}
EXPORT=${export_dir}
ASSET_KIND=${asset_kind}

"\${BB}" mkdir -p "\${EXPORT}" /System/Logs/packages
for asset in "\${SOURCE}"/*; do
  [ -f "\${asset}" ] || continue
  target="\${EXPORT}/\${asset##*/}"
  "\${BB}" rm -f "\${target}"
  if [ "\${ASSET_KIND}" = wallpapers ]; then
    "\${BB}" ln "\${asset}" "\${target}" 2>/dev/null ||
      "\${BB}" cp -f "\${asset}" "\${target}"
  else
    "\${BB}" ln -sfn "\${asset}" "\${target}"
  fi
done
echo "\${AUZIX_PACKAGE_NAME:-desktop-assets} \${AUZIX_PACKAGE_VERSION:-unknown} activated" \
  >>/System/Logs/packages/desktop-assets.log

if "\${BB}" pidof enlightenment >/dev/null 2>&1; then
  (
    "\${BB}" sleep 1
    "\${BB}" su auzix -c \
      'DISPLAY=:0 HOME=/Users/auzix XDG_RUNTIME_DIR=/run/user/1000 enlightenment_remote -restart' \
      >/System/Logs/packages/enlightenment-restart.log 2>&1 || true
  ) &
fi
EOF
  chmod 0755 "${program_root}/Commands/activate"
  printf '%s\n' "${asset_kind}" >"${program_root}/Resources/asset-kind"
}

build_themes() {
  local program="${AUZIX_ROOT}/Programs/AuzixThemes/${VERSION}"
  local assets="${program}/Resources/themes"
  local exports="${GLOBAL_E}/themes"
  local count=0

  rm -rf "${program}"
  mkdir -p "${assets}" "${exports}"
  while IFS= read -r -d '' theme; do
    if eet_list "${theme}"; then
      install -m 0444 "${theme}" "${assets}/$(basename "${theme}")"
      count=$((count + 1))
    else
      log "Skipping invalid theme: ${theme}"
    fi
  done < <(find "${SOURCE}/themes" -maxdepth 1 -type f -name '*.edj' -print0 | sort -z)
  [[ "${count}" -gt 0 ]] || {
    printf 'No valid themes found.\n' >&2
    exit 1
  }

  write_activation_hook \
    "${program}" themes \
    "/Programs/AuzixThemes/${VERSION}/Resources/themes" \
    /System/Compatibility/usr/share/enlightenment/themes
  ln -sfn "/Programs/AuzixThemes/${VERSION}" "${AUZIX_ROOT}/Programs/AuzixThemes/current"
  for theme in "${assets}"/*; do
    [[ -f "${theme}" ]] || continue
    ln -sfn "/Programs/AuzixThemes/${VERSION}/Resources/themes/$(basename "${theme}")" \
      "${exports}/$(basename "${theme}")"
  done

  exports_json="$(find "${exports}" -maxdepth 1 -type l -printf '/System/Compatibility/usr/share/enlightenment/themes/%f\n' | sort -u | jq -R . | jq -s .)"
  cat >"${AUZIX_ROOT}/System/PackageDB/AuzixThemes-${VERSION}.auzix.json" <<EOF
{
  "name": "AuzixThemes",
  "version": "${VERSION}",
  "kind": "assets",
  "migration_stage": "stage-1-desktop-repository",
  "prefix": "/Programs/AuzixThemes/${VERSION}",
  "depends": ["BusyBox", "Enlightenment"],
  "paths": {
    "current": "/Programs/AuzixThemes/current"
  },
  "hooks": {
    "post_install": "/Programs/AuzixThemes/${VERSION}/Commands/activate"
  },
  "compatibility_exports": ${exports_json},
  "asset_count": ${count},
  "notes": "Validated Enlightenment EDJ themes exported into the global theme catalog."
}
EOF
  log "Staged ${count} validated themes"
}

build_wallpapers() {
  local program="${AUZIX_ROOT}/Programs/AuzixWallpapers/${VERSION}"
  local assets="${program}/Resources/backgrounds"
  local exports="${GLOBAL_E}/data/backgrounds"
  local count=0

  rm -rf "${program}"
  mkdir -p "${assets}" "${exports}"
  while IFS= read -r -d '' wallpaper; do
    case "${wallpaper}" in
      *.edj)
        eet_list "${wallpaper}" || {
          log "Skipping invalid EDJ background: ${wallpaper}"
          continue
        }
        ;;
      *.jpg|*.jpeg|*.png|*.JPG|*.JPEG|*.PNG)
        file --mime-type "${wallpaper}" | grep -q 'image/' || {
          log "Skipping invalid image background: ${wallpaper}"
          continue
        }
        ;;
      *) continue ;;
    esac
    install -m 0444 "${wallpaper}" "${assets}/$(basename "${wallpaper}")"
    count=$((count + 1))
  done < <(find "${SOURCE}/backgrounds" -maxdepth 1 -type f -print0 | sort -z)
  if [[ "${count}" -eq 0 ]]; then
    log "No valid wallpapers found; staging empty wallpaper package"
  fi

  write_activation_hook \
    "${program}" backgrounds \
    "/Programs/AuzixWallpapers/${VERSION}/Resources/backgrounds" \
    /System/Compatibility/usr/share/enlightenment/data/backgrounds
  ln -sfn "/Programs/AuzixWallpapers/${VERSION}" "${AUZIX_ROOT}/Programs/AuzixWallpapers/current"
  for wallpaper in "${assets}"/*; do
    [[ -f "${wallpaper}" ]] || continue
    rm -f "${exports}/$(basename "${wallpaper}")"
    ln "${wallpaper}" "${exports}/$(basename "${wallpaper}")"
  done

  exports_json="$(find "${exports}" -maxdepth 1 -type f -printf '/System/Compatibility/usr/share/enlightenment/data/backgrounds/%f\n' | sort -u | jq -R . | jq -s .)"
  cat >"${AUZIX_ROOT}/System/PackageDB/AuzixWallpapers-${VERSION}.auzix.json" <<EOF
{
  "name": "AuzixWallpapers",
  "version": "${VERSION}",
  "kind": "assets",
  "migration_stage": "stage-1-desktop-repository",
  "prefix": "/Programs/AuzixWallpapers/${VERSION}",
  "depends": ["BusyBox", "Enlightenment"],
  "paths": {
    "current": "/Programs/AuzixWallpapers/current"
  },
  "hooks": {
    "post_install": "/Programs/AuzixWallpapers/${VERSION}/Commands/activate"
  },
  "compatibility_exports": ${exports_json},
  "asset_count": ${count},
  "notes": "Validated EDJ and image wallpapers exported into the global Enlightenment background catalog."
}
EOF
  log "Staged ${count} validated wallpapers"
}

build_themes
build_wallpapers
