#!/usr/bin/env bash
set -euo pipefail

REPO=""
APPLY=0
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"

usage() {
  printf 'Usage: %s --repo PATH [--apply]\n' "$0"
}

while (($#)); do
  case "$1" in
    --repo) REPO="${2:?missing repository path}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "${REPO}" && -s "${REPO}/index.json" && -d "${REPO}/packages" ]] || {
  printf 'Invalid AUZiX repository: %s\n' "${REPO:-unset}" >&2
  exit 2
}
command -v jq >/dev/null
command -v sha256sum >/dev/null

QUARANTINE="${REPO}/quarantine/suite-drift-${RUN_ID}"
MANIFEST="${QUARANTINE}/manifest.tsv"
mkdir -p "${QUARANTINE}/packages"

jq -r '
  .packages[] |
  select(
    ((.source.suite // "") == "bookworm") or
    ((.version // "") | test("deb12|bookworm"; "i"))
  ) |
  [.name, .version, (.source.suite // "unspecified"), .package, .sha256] | @tsv
' "${REPO}/index.json" | sort >"${MANIFEST}"

count="$(wc -l <"${MANIFEST}" | tr -d ' ')"
printf 'confirmed_suite_drift=%s\n' "${count}"
cat "${MANIFEST}"

if ((APPLY == 0)); then
  printf 'DRY RUN: pass --apply to quarantine archives and rewrite the active index.\n'
  exit 0
fi

cp -a "${REPO}/index.json" "${QUARANTINE}/index.before.json"
while IFS=$'\t' read -r name version suite package digest; do
  [[ -n "${package}" ]] || continue
  source_archive="${REPO}/packages/${package}"
  [[ -f "${source_archive}" ]] || {
    printf 'STOP: indexed archive is missing: %s\n' "${source_archive}" >&2
    exit 3
  }
  actual="$(sha256sum "${source_archive}" | awk '{print $1}')"
  [[ "${actual}" == "${digest}" ]] || {
    printf 'STOP: checksum mismatch for %s\n' "${source_archive}" >&2
    exit 4
  }
done <"${MANIFEST}"

tmp_index="${REPO}/index.json.${RUN_ID}.tmp"
jq '
  .packages |= map(select(
    (((.source.suite // "") == "bookworm") or
     ((.version // "") | test("deb12|bookworm"; "i"))) | not
  ))
' "${REPO}/index.json" >"${tmp_index}"
jq -e '.format and (.packages | type == "array")' "${tmp_index}" >/dev/null

while IFS=$'\t' read -r name version suite package digest; do
  [[ -n "${package}" ]] || continue
  mv "${REPO}/packages/${package}" "${QUARANTINE}/packages/${package}"
done <"${MANIFEST}"

mv "${tmp_index}" "${REPO}/index.json"
cat >"${QUARANTINE}/receipt.txt" <<EOF
format=auzix-repo-suite-drift-quarantine-v1
run_id=${RUN_ID}
repository=${REPO}
removed_from_active_index=${count}
active_index_sha256=$(sha256sum "${REPO}/index.json" | awk '{print $1}')
status=complete
EOF

printf 'PASS: quarantined %s confirmed Bookworm entries at %s\n' "${count}" "${QUARANTINE}"
