#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:?usage: package-auzix-receipt-archive.sh <auzix-root> <receipt> <repo-dir>}"
RECEIPT="${2:?usage: package-auzix-receipt-archive.sh <auzix-root> <receipt> <repo-dir>}"
REPO_DIR="${3:?usage: package-auzix-receipt-archive.sh <auzix-root> <receipt> <repo-dir>}"
PACKAGE_DIR="${REPO_DIR}/packages"
ENTRY_DIR="${REPO_DIR}/entries"
NORMALIZE_OWNERS="${AUZIX_PACKAGE_NORMALIZE_OWNERS:-0}"
REJECT_ALT_GLIBC="${AUZIX_REPO_REJECT_ALT_GLIBC:-1}"

log() {
  printf '[auzix-package-archive] %s\n' "$*" >&2
}

safe_name() {
  tr '/: ' '---' <<<"$1" | tr -cd 'A-Za-z0-9_.+-'
}

receipt_paths() {
  local receipt="$1"
  jq -r '
    def arrayish:
      if . == null then []
      elif type == "array" then .
      else [.]
      end;

    [
      .prefix?,
      .paths?.prefix?,
      .paths?.current?,
      (.paths? // {} | to_entries[]?.value),
      (.commands? | arrayish[]),
      (.compatibility_exports? | arrayish[]),
      .hooks?.post_install?,
      (.settings? | arrayish[]),
      .paths?.settings?,
      .service?,
      .paths?.state?,
      .paths?.logs?,
      .paths?.libraries?,
      .paths?.runtime?
    ]
    | map(select(type == "string" and startswith("/")))
    | unique[]
  ' "${receipt}"
}

package_receipt() {
  local receipt="$1"
  local name version package_name package_path tmp_list rel_path size sha normalized_owners_json metadata_path entry_path

  name="$(jq -r '.name // empty' "${receipt}")"
  version="$(jq -r '.version // "unknown"' "${receipt}")"
  if [[ -z "${name}" ]]; then
    log "Skipping receipt without name: ${receipt}"
    return 0
  fi
  if [[ "${REJECT_ALT_GLIBC}" == "1" ]] &&
    grep -F '/Programs/Libc6/current' "${receipt}" >/dev/null 2>&1; then
    log "Refusing ${name}-${version}; receipt references alternate/package-scoped glibc. Rebuild against /System/Libraries core."
    return 1
  fi

  package_name="$(safe_name "${name}-${version}").auzix.tar.gz"
  package_path="${PACKAGE_DIR}/${package_name}"
  metadata_path="${package_path%.tar.gz}.metadata.tsv"
  entry_path="${ENTRY_DIR}/${package_name%.tar.gz}.json"
  tmp_list="$(mktemp)"

  rel_path="${receipt#${AUZIX_ROOT}/}"
  if [[ -f "${AUZIX_ROOT}/${rel_path}" ]]; then
    printf '%s\n' "${rel_path}" >>"${tmp_list}"
  fi

  while IFS= read -r owned_path; do
    rel_path="${owned_path#/}"
    if [[ -e "${AUZIX_ROOT}/${rel_path}" || -L "${AUZIX_ROOT}/${rel_path}" ]]; then
      printf '%s\n' "${rel_path}" >>"${tmp_list}"
    fi
  done < <(receipt_paths "${receipt}")

  sort -u -o "${tmp_list}" "${tmp_list}"
  awk '
    {
      for (i = 1; i <= kept_count; i++) {
        if ($0 == kept[i] || index($0, kept[i] "/") == 1) {
          next
        }
      }
      kept[++kept_count] = $0
      print
    }
  ' "${tmp_list}" >"${tmp_list}.dedup"
  mv "${tmp_list}.dedup" "${tmp_list}"
  if [[ ! -s "${tmp_list}" ]]; then
    log "Skipping ${name}-${version}; no owned paths exist in ${AUZIX_ROOT}"
    rm -f "${tmp_list}"
    return 0
  fi

  log "Packaging ${name}-${version} -> ${package_name}"
  mkdir -p "${PACKAGE_DIR}" "${ENTRY_DIR}"

  {
    printf 'path\ttype\tmode\tuid\tgid\tuser\tgroup\tflags\ttarget\n'
    while IFS= read -r rel_path; do
      full_path="${AUZIX_ROOT}/${rel_path}"
      [[ -e "${full_path}" || -L "${full_path}" ]] || continue
      type="$(stat -c '%F' "${full_path}")"
      mode="$(stat -c '%a' "${full_path}")"
      uid="$(stat -c '%u' "${full_path}")"
      gid="$(stat -c '%g' "${full_path}")"
      user="$(stat -c '%U' "${full_path}")"
      group="$(stat -c '%G' "${full_path}")"
      flags=()
      if [[ "${mode}" =~ ^[4567] ]]; then
        case "${mode:0:1}" in
          4) flags+=(setuid) ;;
          5) flags+=(setuid sticky) ;;
          6) flags+=(setuid setgid) ;;
          7) flags+=(setuid setgid sticky) ;;
        esac
      fi
      target=""
      if [[ -L "${full_path}" ]]; then
        target="$(readlink "${full_path}")"
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "/${rel_path}" "${type}" "${mode}" "${uid}" "${gid}" "${user}" "${group}" \
        "$(IFS=,; printf '%s' "${flags[*]:-}")" "${target}"
    done <"${tmp_list}"
  } >"${metadata_path}"

  tar_args=(
    --directory "${AUZIX_ROOT}"
    --sort=name
    --mtime='UTC 2026-01-01'
    --numeric-owner
  )
  if [[ "${NORMALIZE_OWNERS}" == "1" ]]; then
    log "WARNING: normalizing owners for ${name}-${version}; package ownership semantics will be lost unless permissions metadata restores them"
    tar_args+=(--owner=0 --group=0)
    normalized_owners_json=true
  else
    normalized_owners_json=false
  fi

  tar "${tar_args[@]}" -czf "${package_path}" --files-from "${tmp_list}"
  size="$(stat -c '%s' "${package_path}")"
  sha="$(sha256sum "${package_path}" | awk '{print $1}')"

  jq -n \
    --arg name "${name}" \
    --arg version "${version}" \
    --arg kind "$(jq -r '.kind // "unknown"' "${receipt}")" \
    --arg package "${package_name}" \
    --arg sha256 "${sha}" \
    --argjson size "${size}" \
    --argjson normalized_owners "${normalized_owners_json}" \
    --arg receipt_path "/${receipt#${AUZIX_ROOT}/}" \
    --slurpfile receipt_json "${receipt}" \
    '{
      name: $name,
      version: $version,
      kind: $kind,
      package: $package,
      size: $size,
      sha256: $sha256,
      depends: ($receipt_json[0].depends // []),
      recommends: ($receipt_json[0].recommends // []),
      description: ($receipt_json[0].description // $receipt_json[0].notes // ""),
      migration_stage: ($receipt_json[0].migration_stage // null),
      receipt: $receipt_path,
      prefix: ($receipt_json[0].prefix // $receipt_json[0].paths.prefix // null),
      commands: ($receipt_json[0].commands // []),
      desktop_entries: ($receipt_json[0].desktop_entries // []),
      service: ($receipt_json[0].service // null),
      hooks: ($receipt_json[0].hooks // {}),
      compatibility_exports: ($receipt_json[0].compatibility_exports // []),
      runtime_ladder: ($receipt_json[0].runtime_ladder // null),
      runtime_environment: ($receipt_json[0].runtime_environment // null),
      permissions: ($receipt_json[0].permissions // null),
      archive_policy: {
        numeric_owner: true,
        normalized_owners: $normalized_owners
      },
      metadata: {
        path: ($package | sub("\\.tar\\.gz$"; ".metadata.tsv")),
        format: "auzix-package-metadata-tsv-v1",
        preserves: ["mode", "uid", "gid", "setuid", "setgid", "sticky", "symlink_target"]
      },
      validation: ($receipt_json[0].validation // null),
      source: ($receipt_json[0].source // {})
    }' >"${entry_path}"

  cat "${entry_path}"
  rm -f "${tmp_list}"
}

command -v jq >/dev/null 2>&1 || { printf 'Required command not found: jq\n' >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { printf 'Required command not found: tar\n' >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { printf 'Required command not found: sha256sum\n' >&2; exit 1; }
command -v stat >/dev/null 2>&1 || { printf 'Required command not found: stat\n' >&2; exit 1; }
[[ -f "${RECEIPT}" ]] || { printf 'Receipt missing: %s\n' "${RECEIPT}" >&2; exit 1; }
[[ -d "${AUZIX_ROOT}" ]] || { printf 'AUZiX root missing: %s\n' "${AUZIX_ROOT}" >&2; exit 1; }

package_receipt "${RECEIPT}"
