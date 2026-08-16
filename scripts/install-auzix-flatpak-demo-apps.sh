#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
REFS_FILE="${2:-${ROOT_DIR}/profiles/flatpak/auzix-2026-08-11-demo-apps.refs}"
FLATPAK_USER="${AUZIX_FLATPAK_USER:-auzix}"

log() {
  printf '[auzix-flatpak-demo] %s\n' "$*" >&2
}

[[ -f "${REFS_FILE}" ]] || {
  log "refs file not found: ${REFS_FILE}"
  exit 1
}

if [[ -x "${AUZIX_ROOT}/Programs/FlatpakRuntimeSupport/current/Commands/repair-var-alias" ]]; then
  log "repairing Flatpak /var alias support"
  "${AUZIX_ROOT}/Programs/FlatpakRuntimeSupport/current/Commands/repair-var-alias" || true
fi

if command -v flatpak >/dev/null 2>&1; then
  flatpak_cmd=(flatpak)
elif [[ -x "${AUZIX_ROOT}/Programs/Flatpak/current/Commands/flatpak" ]]; then
  flatpak_cmd=("${AUZIX_ROOT}/Programs/Flatpak/current/Commands/flatpak")
else
  log "flatpak command not found"
  exit 1
fi

while IFS= read -r ref; do
  [[ -n "${ref}" ]] || continue
  [[ "${ref}" != \#* ]] || continue
  log "installing Flatpak user ref: ${ref}"
  if command -v su >/dev/null 2>&1 && id "${FLATPAK_USER}" >/dev/null 2>&1; then
    su - "${FLATPAK_USER}" -c "$(printf '%q ' "${flatpak_cmd[@]}") install --user -y flathub ${ref}" || {
      log "failed to install ${ref}"
      continue
    }
  else
    "${flatpak_cmd[@]}" install --user -y flathub "${ref}" || {
      log "failed to install ${ref}"
      continue
    }
  fi
done <"${REFS_FILE}"

for recipe in \
  packages/firefox-flatpak-adapter.json \
  packages/opera-flatpak-adapter.json \
  packages/sublime-flatpak-adapter.json \
  packages/zed-flatpak-adapter.json \
  packages/codium-flatpak-adapter.json \
  packages/gimp-flatpak-adapter.json \
  packages/blender-flatpak-adapter.json \
  packages/clementine-flatpak-adapter.json \
  packages/shotwell-flatpak-adapter.json \
  packages/fs-uae-flatpak-adapter.json \
  packages/bottles-flatpak-adapter.json; do
  [[ -f "${ROOT_DIR}/${recipe}" ]] || continue
  log "building adapter: ${recipe}"
  "${ROOT_DIR}/scripts/build-auzix-flatpak-adapter-package.sh" "${AUZIX_ROOT}" "${ROOT_DIR}/${recipe}"
done

if [[ -x "${ROOT_DIR}/scripts/repair-auzix-desktop-menu.sh" ]]; then
  log "refreshing AUZiX desktop menu"
  "${ROOT_DIR}/scripts/repair-auzix-desktop-menu.sh" "${AUZIX_ROOT}" || true
fi

log "done"
