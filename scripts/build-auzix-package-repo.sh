#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
REPO_DIR="${AUZIX_REPO_DIR:-${ROOT_DIR}/artifacts/auzix/repo}"
PACKAGE_DIR="${REPO_DIR}/packages"
INDEX_PATH="${REPO_DIR}/index.json"
PREVIOUS_INDEX="${REPO_DIR}/index.json"
PREVIOUS_PACKAGE_DIR="${REPO_DIR}/packages"
MANIFEST_DIR="${AUZIX_ROOT}/System/Settings/packages"
STACK_DIR="${AUZIX_ROOT}/Stacks/desktop-core"
NORMALIZE_OWNERS="${AUZIX_PACKAGE_NORMALIZE_OWNERS:-0}"

log() {
  printf '[auzix-repo] %s\n' "$*" >&2
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

json_string() {
  jq -Rs . <<<"$1"
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
  local name version package_name package_path tmp_list rel_path size sha normalized_owners_json metadata_path

  name="$(jq -r '.name // empty' "${receipt}")"
  version="$(jq -r '.version // "unknown"' "${receipt}")"
  if [[ -z "${name}" ]]; then
    log "Skipping receipt without name: ${receipt}"
    return 0
  fi

  package_name="$(safe_name "${name}-${version}").auzix.tar.gz"
  package_path="${PACKAGE_DIR}/${package_name}"
  metadata_path="${package_path%.tar.gz}.metadata.tsv"
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
    }'

  rm -f "${tmp_list}"
}

need_cmd jq
need_cmd tar
need_cmd sha256sum
need_cmd stat

if [[ ! -d "${AUZIX_ROOT}/System/PackageDB" ]]; then
  printf 'Auzix PackageDB missing: %s\n' "${AUZIX_ROOT}/System/PackageDB" >&2
  exit 1
fi

previous_repo="$(mktemp -d)"
trap 'rm -rf "${previous_repo}"' EXIT
if [[ -f "${PREVIOUS_INDEX}" && -d "${PREVIOUS_PACKAGE_DIR}" ]] &&
  jq -e '.format == "auzix-repo-v1" and (.packages | type == "array")' "${PREVIOUS_INDEX}" >/dev/null 2>&1; then
  mkdir -p "${previous_repo}/packages"
  cp -f "${PREVIOUS_INDEX}" "${previous_repo}/index.json"
  find "${PREVIOUS_PACKAGE_DIR}" -maxdepth 1 -type f -name '*.auzix.tar.gz' -exec cp -f {} "${previous_repo}/packages/" \;
else
  jq -n '{format: "auzix-repo-v1", packages: []}' >"${previous_repo}/index.json"
  mkdir -p "${previous_repo}/packages"
fi

rm -rf "${REPO_DIR}"
mkdir -p "${PACKAGE_DIR}" "${MANIFEST_DIR}" "${STACK_DIR}"
find "${previous_repo}/packages" -maxdepth 1 -type f -name '*.auzix.tar.gz' -exec cp -f {} "${PACKAGE_DIR}/" \;

entries_tmp="$(mktemp)"
find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f -name '*.json' -print |
  sort |
  while IFS= read -r receipt; do
    package_receipt "${receipt}"
  done >"${entries_tmp}"

jq -s \
  --arg format "auzix-repo-v1" \
  --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg root_contract "strict-root-prototype" \
  '{
    format: $format,
    created: $created,
    root_contract: $root_contract,
    packages: .
  }' "${entries_tmp}" >"${INDEX_PATH}"

merged_tmp="$(mktemp)"
jq -s '
  .[0] as $previous
  | .[1] as $incoming
  | ($incoming.packages | map(.name)) as $incoming_names
  | ($incoming.packages
      | map(select(.source.package? != null) | .source.package)
      | unique) as $incoming_source_packages
  | $incoming + {
      packages: (
        ([
          $previous.packages[]?
          | select(.name as $name | ($incoming_names | index($name) | not))
          | select(
              if (.name | startswith("Debian.")) then
                ((.name | sub("^Debian[.]"; "")) as $source_name
                  | ($incoming_source_packages | index($source_name) | not))
              else
                true
              end
            )
        ] + $incoming.packages)
        | sort_by(.name)
      )
    }
' "${previous_repo}/index.json" "${INDEX_PATH}" >"${merged_tmp}"
mv "${merged_tmp}" "${INDEX_PATH}"

while IFS=$'\t' read -r archive expected_sha; do
  package_path="${PACKAGE_DIR}/${archive}"
  [[ -f "${package_path}" ]] || {
    log "merged index references missing package archive: ${archive}"
    exit 1
  }
  actual_sha="$(sha256sum "${package_path}" | awk '{print $1}')"
  [[ "${actual_sha}" == "${expected_sha}" ]] || {
    log "merged package checksum mismatch: ${archive}"
    exit 1
  }
done < <(jq -r '.packages[] | [.package, .sha256] | @tsv' "${INDEX_PATH}")

cp -f "${INDEX_PATH}" "${MANIFEST_DIR}/repo-index.json"
jq '{format: "auzix-installed-v1", installed: []}' \
  "${INDEX_PATH}" >"${MANIFEST_DIR}/installed.json"

cat > "${MANIFEST_DIR}/first-apps.txt" <<'TXT'
Terminology
XTerm
Curl
NetSurf
LightDM
Enlightenment
OpenSSH
TXT

cat > "${STACK_DIR}/stack.auzix.json" <<'JSON'
{
  "name": "desktop-core",
  "purpose": "First usable Auzix live workstation set: E desktop, greeter, terminal access, and SSH.",
  "services": [
    "/Services/display-manager",
    "/Services/ssh",
    "/Services/udev",
    "/Services/acpid"
  ],
  "programs": [
    "/Programs/Enlightenment/host",
    "/Programs/LightDM/host",
    "/Programs/Terminology/host",
    "/Programs/XTerm/379-1",
    "/Programs/Curl/current",
    "/Programs/NetSurf/current",
    "/Programs/OpenSSH/host"
  ],
  "paths": {
    "settings": "/System/Settings/display",
    "state": "/System/State/display",
    "logs": "/System/Logs/display"
  },
  "notes": "curl validates HTTPS/CA/iconv plumbing before browser work. NetSurf is the first small browser proof. Heavier Firefox/Chromium-style browsers remain optional full-web packages."
}
JSON

rm -f "${entries_tmp}"

log "Repository ready: ${REPO_DIR}"
log "Index staged: ${MANIFEST_DIR}/repo-index.json"
