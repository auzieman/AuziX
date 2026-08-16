#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
OUT_FILE="${2:-${ROOT_DIR}/out/package-bot/debian-maintainer-surfaces.md}"

mkdir -p "$(dirname "${OUT_FILE}")"

{
  printf '# AUZiX Debian maintainer/config surfaces\n\n'
  printf 'Root: `%s`\n\n' "${AUZIX_ROOT}"
  printf 'This report records Debian package control-dir scripts and config clues captured during binary intake. Do not execute these scripts blindly; mine them for AUZiX activation packages, groups, DBus/polkit/systemd surfaces, triggers, conffiles, users, and cache rebuilds.\n\n'

  if [[ ! -d "${AUZIX_ROOT}/System/PackageDB" ]]; then
    printf 'PackageDB missing.\n'
    exit 0
  fi

  find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f -name '*.json' -print |
    sort |
    while IFS= read -r receipt; do
      surfaces="$(jq -r '.maintainer_surfaces[]? // empty' "${receipt}" 2>/dev/null || true)"
      [[ -n "${surfaces}" ]] || continue
      name="$(jq -r '.name // empty' "${receipt}")"
      version="$(jq -r '.version // empty' "${receipt}")"
      source_package="$(jq -r '.source.package // empty' "${receipt}")"
      printf '## %s %s\n\n' "${name:-unknown}" "${version:-unknown}"
      [[ -n "${source_package}" ]] && printf '%s\n' "- Debian package: \`${source_package}\`"
      printf '%s\n\n' "- Receipt: \`${receipt#${ROOT_DIR}/}\`"
      while IFS= read -r surface; do
        [[ -n "${surface}" ]] || continue
        host_surface="${AUZIX_ROOT}${surface}"
        printf '### `%s`\n\n' "${surface}"
        if [[ -s "${host_surface}" ]]; then
          sed -n '1,80p' "${host_surface}" |
            sed 's/^/    /'
        else
          printf '    missing or empty on host: %s\n' "${host_surface}"
        fi
        printf '\n'
      done <<<"${surfaces}"
    done
} >"${OUT_FILE}"

printf '[auzix-maintainer-surfaces] report: %s\n' "${OUT_FILE}" >&2
