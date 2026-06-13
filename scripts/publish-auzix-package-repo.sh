#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="${1:-${ROOT_DIR}/artifacts/auzix/repo}"
PUBLISH_DIR="${2:-/srv/http/auzix/repo}"
INDEX_PATH="${REPO_DIR}/index.json"
PACKAGE_DIR="${REPO_DIR}/packages"
REPORT_FILE="${ROOT_DIR}/out/package-bot/repository-publish.report.json"
MERGED_INDEX="$(mktemp)"
EMPTY_INDEX="$(mktemp)"
trap 'rm -f "${MERGED_INDEX}" "${EMPTY_INDEX}"' EXIT

log() {
  printf '[auzix-publish] %s\n' "$*" >&2
}

for command_name in jq rsync sha256sum date; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    log "missing command: ${command_name}"
    exit 1
  }
done

jq -e '
  .format == "auzix-repo-v1"
  and (.packages | type == "array")
  and all(.packages[];
    (.package | type == "string")
    and (.sha256 | test("^[a-f0-9]{64}$"))
  )
' "${INDEX_PATH}" >/dev/null

while IFS=$'\t' read -r archive expected_sha; do
  package_path="${PACKAGE_DIR}/${archive}"
  [[ -f "${package_path}" ]] || {
    log "missing package archive: ${archive}"
    exit 1
  }
  actual_sha="$(sha256sum "${package_path}" | awk '{print $1}')"
  [[ "${actual_sha}" == "${expected_sha}" ]] || {
    log "checksum mismatch: ${archive}"
    exit 1
  }
done < <(jq -r '.packages[] | [.package, .sha256] | @tsv' "${INDEX_PATH}")

mkdir -p "${PUBLISH_DIR}/packages" "$(dirname "${REPORT_FILE}")"
rsync -a "${PACKAGE_DIR}/" "${PUBLISH_DIR}/packages/"

jq -n '{format: "auzix-repo-v1", packages: []}' >"${EMPTY_INDEX}"
EXISTING_INDEX="${EMPTY_INDEX}"
if [[ -f "${PUBLISH_DIR}/index.json" ]]; then
  jq -e '
    .format == "auzix-repo-v1"
    and (.packages | type == "array")
  ' "${PUBLISH_DIR}/index.json" >/dev/null
  EXISTING_INDEX="${PUBLISH_DIR}/index.json"
fi

jq -s '
  .[0] as $existing
  | .[1] as $incoming
  | ($incoming.packages | map(.name)) as $incoming_names
  | $incoming + {
      packages: (
        ([
          $existing.packages[]?
          | select(.name as $name | ($incoming_names | index($name) | not))
        ] + $incoming.packages)
        | sort_by(.name)
      )
    }
' "${EXISTING_INDEX}" "${INDEX_PATH}" >"${MERGED_INDEX}"

while IFS=$'\t' read -r archive expected_sha; do
  package_path="${PUBLISH_DIR}/packages/${archive}"
  [[ -f "${package_path}" ]] || {
    log "merged index references missing package archive: ${archive}"
    exit 1
  }
  actual_sha="$(sha256sum "${package_path}" | awk '{print $1}')"
  [[ "${actual_sha}" == "${expected_sha}" ]] || {
    log "merged package checksum mismatch: ${archive}"
    exit 1
  }
done < <(jq -r '.packages[] | [.package, .sha256] | @tsv' "${MERGED_INDEX}")

install -m 0644 "${MERGED_INDEX}" "${PUBLISH_DIR}/index.json.next"
mv -f "${PUBLISH_DIR}/index.json.next" "${PUBLISH_DIR}/index.json"

while IFS= read -r published_path; do
  published_name="$(basename "${published_path}")"
  jq -e --arg package "${published_name}" \
    'any(.packages[]; .package == $package)' "${MERGED_INDEX}" >/dev/null ||
    rm -f "${published_path}"
done < <(find "${PUBLISH_DIR}/packages" -maxdepth 1 -type f -name '*.auzix.tar.gz' -print)

package_count="$(jq '.packages | length' "${MERGED_INDEX}")"
jq -n \
  --arg format "auzix-repository-publish-report-v1" \
  --arg status "complete" \
  --arg published_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg publish_dir "${PUBLISH_DIR}" \
  --arg index_sha256 "$(sha256sum "${PUBLISH_DIR}/index.json" | awk '{print $1}')" \
  --argjson package_count "${package_count}" \
  '{format: $format, status: $status, published_at: $published_at,
    publish_dir: $publish_dir, index_sha256: $index_sha256,
    package_count: $package_count}' >"${REPORT_FILE}"

log "published ${package_count} packages to ${PUBLISH_DIR}"
