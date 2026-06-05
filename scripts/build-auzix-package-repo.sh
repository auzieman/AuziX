#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
REPO_DIR="${AUZIX_REPO_DIR:-${ROOT_DIR}/artifacts/auzix/repo}"
PACKAGE_DIR="${REPO_DIR}/packages"
INDEX_PATH="${REPO_DIR}/index.json"
MANIFEST_DIR="${AUZIX_ROOT}/System/Settings/packages"
STACK_DIR="${AUZIX_ROOT}/Stacks/desktop-core"

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
      (.commands? | arrayish[]),
      (.compatibility_exports? | arrayish[]),
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
  local name version package_name package_path tmp_list rel_path size sha

  name="$(jq -r '.name // empty' "${receipt}")"
  version="$(jq -r '.version // "unknown"' "${receipt}")"
  if [[ -z "${name}" ]]; then
    log "Skipping receipt without name: ${receipt}"
    return 0
  fi

  package_name="$(safe_name "${name}-${version}").auzix.tar.gz"
  package_path="${PACKAGE_DIR}/${package_name}"
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
  if [[ ! -s "${tmp_list}" ]]; then
    log "Skipping ${name}-${version}; no owned paths exist in ${AUZIX_ROOT}"
    rm -f "${tmp_list}"
    return 0
  fi

  tar \
    --directory "${AUZIX_ROOT}" \
    --sort=name \
    --mtime='UTC 2026-01-01' \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    -czf "${package_path}" \
    --files-from "${tmp_list}"

  size="$(stat -c '%s' "${package_path}")"
  sha="$(sha256sum "${package_path}" | awk '{print $1}')"

  jq -n \
    --arg name "${name}" \
    --arg version "${version}" \
    --arg kind "$(jq -r '.kind // "unknown"' "${receipt}")" \
    --arg package "${package_name}" \
    --arg sha256 "${sha}" \
    --argjson size "${size}" \
    --arg receipt_path "/${receipt#${AUZIX_ROOT}/}" \
    --slurpfile receipt_json "${receipt}" \
    '{
      name: $name,
      version: $version,
      kind: $kind,
      package: $package,
      size: $size,
      sha256: $sha256,
      receipt: $receipt_path,
      prefix: ($receipt_json[0].prefix // $receipt_json[0].paths.prefix // null),
      commands: ($receipt_json[0].commands // []),
      service: ($receipt_json[0].service // null),
      compatibility_exports: ($receipt_json[0].compatibility_exports // [])
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

rm -rf "${REPO_DIR}"
mkdir -p "${PACKAGE_DIR}" "${MANIFEST_DIR}" "${STACK_DIR}"

entries_tmp="$(mktemp)"
find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f -name '*.json' -print |
  sort |
  while IFS= read -r receipt; do
    package_receipt "${receipt}"
  done >"${entries_tmp}"

jq -s \
  --arg format "auzix-repo-v0" \
  --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg root_contract "strict-root-prototype" \
  '{
    format: $format,
    created: $created,
    root_contract: $root_contract,
    packages: .
  }' "${entries_tmp}" >"${INDEX_PATH}"

cp -f "${INDEX_PATH}" "${MANIFEST_DIR}/repo-index.json"
jq '{format, created, root_contract, installed: [.packages[] | {name, version, kind, prefix, commands, service}]}' \
  "${INDEX_PATH}" >"${MANIFEST_DIR}/installed.json"

cat > "${MANIFEST_DIR}/first-apps.txt" <<'TXT'
Terminology
XTerm
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
    "/Programs/NetSurf/current",
    "/Programs/OpenSSH/host"
  ],
  "paths": {
    "settings": "/System/Settings/display",
    "state": "/System/State/display",
    "logs": "/System/Logs/display"
  },
  "notes": "NetSurf is the first small browser proof. Heavier Firefox/Chromium-style browsers remain optional full-web packages."
}
JSON

rm -f "${entries_tmp}"

log "Repository ready: ${REPO_DIR}"
log "Index staged: ${MANIFEST_DIR}/repo-index.json"
