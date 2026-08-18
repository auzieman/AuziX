#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${AUZIX_DESKTOP_GUIDEBOOK_OUT:-${ROOT_DIR}/out/desktop-guidebook/$(date -u +%Y%m%dT%H%M%SZ)}"

log() {
  printf '[desktop-guidebook] %s\n' "$*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

desktop_value() {
  local key="$1"
  local file="$2"
  awk -F= -v key="${key}" '
    $0 == "[Desktop Entry]" {in_entry=1; next}
    /^\[/ && $0 != "[Desktop Entry]" {in_entry=0}
    in_entry && $1 == key {
      sub(/^[^=]*=/, "")
      print
      exit
    }
  ' "${file}"
}

require_cmd apt-get
require_cmd dpkg-deb
require_cmd awk
require_cmd find
require_cmd jq

[[ "$#" -gt 0 ]] || {
  printf 'usage: %s <debian-binary-package>...\n' "$0" >&2
  exit 2
}

mkdir -p "${OUT_DIR}/debs" "${OUT_DIR}/extract" "${OUT_DIR}/fragments"
: >"${OUT_DIR}/desktop-guidebook.tsv"
: >"${OUT_DIR}/desktop-guidebook.jsonl"

printf 'package\tversion\tdesktop_file\tname\tgeneric_name\tcomment\texec\ttry_exec\ticon\tcategories\tmime_type\tterminal\ttype\tno_display\thidden\n' \
  >"${OUT_DIR}/desktop-guidebook.tsv"

for package in "$@"; do
  package_dir="${OUT_DIR}/extract/${package}"
  deb_dir="${OUT_DIR}/debs/${package}"
  mkdir -p "${deb_dir}" "${package_dir}/control" "${package_dir}/rootfs"
  if ! find "${deb_dir}" -maxdepth 1 -type f -name "${package}_*.deb" -print -quit | grep -q .; then
    (cd "${deb_dir}" && apt-get download "${package}" >/dev/null)
  fi
  deb="$(find "${deb_dir}" -maxdepth 1 -type f -name "${package}_*.deb" -print | sort | tail -1)"
  [[ -n "${deb}" ]] || {
    log "no deb found for ${package}; skipping"
    continue
  }
  rm -rf "${package_dir}/control" "${package_dir}/rootfs"
  mkdir -p "${package_dir}/control" "${package_dir}/rootfs"
  dpkg-deb -e "${deb}" "${package_dir}/control"
  dpkg-deb -x "${deb}" "${package_dir}/rootfs"
  version="$(awk -F': ' '$1 == "Version" {print $2; exit}' "${package_dir}/control/control" 2>/dev/null || true)"
  find "${package_dir}/rootfs" -type f -path '*/usr/share/applications/*.desktop' | sort |
  while IFS= read -r desktop; do
    rel="${desktop#${package_dir}/rootfs}"
    name="$(desktop_value Name "${desktop}")"
    generic_name="$(desktop_value GenericName "${desktop}")"
    comment="$(desktop_value Comment "${desktop}")"
    exec_value="$(desktop_value Exec "${desktop}")"
    try_exec="$(desktop_value TryExec "${desktop}")"
    icon="$(desktop_value Icon "${desktop}")"
    categories="$(desktop_value Categories "${desktop}")"
    mime_type="$(desktop_value MimeType "${desktop}")"
    terminal="$(desktop_value Terminal "${desktop}")"
    type_value="$(desktop_value Type "${desktop}")"
    no_display="$(desktop_value NoDisplay "${desktop}")"
    hidden="$(desktop_value Hidden "${desktop}")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${package}" "${version}" "${rel}" "${name}" "${generic_name}" "${comment}" \
      "${exec_value}" "${try_exec}" "${icon}" "${categories}" "${mime_type}" \
      "${terminal}" "${type_value}" "${no_display}" "${hidden}" \
      >>"${OUT_DIR}/desktop-guidebook.tsv"
    jq -n \
      --arg package "${package}" \
      --arg version "${version}" \
      --arg desktop_file "${rel}" \
      --arg name "${name}" \
      --arg generic_name "${generic_name}" \
      --arg comment "${comment}" \
      --arg exec "${exec_value}" \
      --arg try_exec "${try_exec}" \
      --arg icon "${icon}" \
      --arg categories "${categories}" \
      --arg mime_type "${mime_type}" \
      --arg terminal "${terminal}" \
      --arg type "${type_value}" \
      --arg no_display "${no_display}" \
      --arg hidden "${hidden}" \
      '{
        format: "auzix-debian-desktop-entry-v1",
        package: $package,
        version: $version,
        desktop_file: $desktop_file,
        desktop: {
          type: $type,
          name: $name,
          generic_name: $generic_name,
          comment: $comment,
          exec: $exec,
          try_exec: $try_exec,
          icon: $icon,
          categories: ($categories | split(";") | map(select(length > 0))),
          mime_type: ($mime_type | split(";") | map(select(length > 0))),
          terminal: $terminal,
          no_display: $no_display,
          hidden: $hidden
        },
        auzix_contract: {
          derive_launcher_from_debian_entry: true,
          rewrite_exec_to_program_wrapper: true,
          preserve_categories_and_mime: true,
          hide_original_donor_entry_until_front_door_validates: true,
          menu_promotion_requires: ["command-probe-pass", "ldd-clean", "efreet-cache-refresh"]
        }
      }' >>"${OUT_DIR}/desktop-guidebook.jsonl"
  done
done

{
  printf '# AUZiX Debian desktop guidebook\n\n'
  printf -- '- generated_at: `%s`\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf -- '- output: `%s`\n\n' "${OUT_DIR}"
  printf '## Entries\n\n'
  awk 'BEGIN{FS="\t"} NR > 1 {printf "- `%s` `%s` → **%s** (`%s`) categories=`%s`\n", $1, $3, $4, $7, $10}' \
    "${OUT_DIR}/desktop-guidebook.tsv"
} >"${OUT_DIR}/desktop-guidebook.md"

log "tsv: ${OUT_DIR}/desktop-guidebook.tsv"
log "jsonl: ${OUT_DIR}/desktop-guidebook.jsonl"
log "report: ${OUT_DIR}/desktop-guidebook.md"
