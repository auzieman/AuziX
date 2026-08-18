#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-/workspace/artifacts/auzix/repo-toast-current}"
ROOT="${2:-/workspace/out/auzix-strict/AuzixRoot}"
OUT="${3:-/workspace/out/package-rebuild/triage-alpha-0.0.1-$(date -u +%Y%m%dT%H%M%SZ)}"

INDEX="${REPO}/index.json"
PACKAGE_DIR="${REPO}/packages"

log() {
  printf '[auzix-repo-triage] %s\n' "$*" >&2
}

require_file() {
  [[ -s "$1" ]] || {
    log "missing required file: $1"
    exit 1
  }
}

mkdir -p "${OUT}"
require_file "${INDEX}"

jq -r '.packages[].name' "${INDEX}" | sort | uniq -d >"${OUT}/duplicates.txt"

if [[ -d "${ROOT}/System/PackageDB" ]]; then
  grep -RIl '/Programs/Libc6/current' "${ROOT}/System/PackageDB" \
    >"${OUT}/alt-glibc-receipts.raw" 2>/dev/null || true
  sed "s#^${ROOT}/##" "${OUT}/alt-glibc-receipts.raw" \
    >"${OUT}/alt-glibc-receipts.txt"
else
  : >"${OUT}/alt-glibc-receipts.txt"
fi

jq -r '
  .packages[]
  | select(.name=="EFL" or .name=="Enlightenment" or .name=="Terminology")
  | [.name, .version, .kind, (.prefix // ""), (.package // "")]
  | @tsv
' "${INDEX}" >"${OUT}/efl-identity.tsv"

jq -r '
  .packages[]
  | select(
      (((.validation? // {}) | tostring) | contains("/Programs/Libc6/current"))
      or
      (((.runtime_ladder? // {}) | tostring) | contains("/Programs/Libc6/current"))
    )
  | [.name, .version, (.package // "")]
  | @tsv
' "${INDEX}" >"${OUT}/index-alt-core.tsv"

jq -r '
  .packages[]
  | select((((.validation? // {}) | tostring) | contains("/lib64/ld-linux-x86-64.so.2")))
  | [.name, .version, (.package // "")]
  | @tsv
' "${INDEX}" >"${OUT}/classic-loader-validation.tsv"

jq -r '
  .packages[]
  | select(.name | test("^(Nano|Pluma|Gedit|L3afpad|Geany|AbiWord|Gnumeric|Midori|Htop|Terminology|XTerm|Flatpak|LibreOffice|EFL|Enlightenment)"))
  | [.name, .version, .kind, (.package // "")]
  | @tsv
' "${INDEX}" | sort >"${OUT}/canaries.tsv"

jq -r '
  .packages[]
  | select((.archive_policy.normalized_owners // false) == true)
  | [.name, .version, (.package // "")]
  | @tsv
' "${INDEX}" >"${OUT}/normalized-owner-packages.tsv"

jq -r '
  .packages[]
  | select((.metadata.preserves // []) | index("setuid") | not)
  | [.name, .version, (.package // "")]
  | @tsv
' "${INDEX}" >"${OUT}/missing-setuid-preserve-metadata.tsv"

archives_count=0
if [[ -d "${PACKAGE_DIR}" ]]; then
  archives_count="$(find "${PACKAGE_DIR}" -maxdepth 1 -name '*.auzix.tar.gz' | wc -l)"
else
  archives_count="$(find "${REPO}" -maxdepth 1 -name '*.auzix.tar.gz' | wc -l)"
fi

{
  echo "# AUZiX alpha-0.0.1 package triage"
  echo
  echo "- generated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- repo: \`${REPO}\`"
  echo "- root: \`${ROOT}\`"
  echo "- package_dir: \`${PACKAGE_DIR}\`"
  echo "- packages: \`$(jq '.packages | length' "${INDEX}")\`"
  echo "- archives: \`${archives_count}\`"
  echo "- receipts: \`$(find "${ROOT}/System/PackageDB" -maxdepth 1 -name '*.auzix.json' 2>/dev/null | wc -l)\`"
  echo "- duplicate active names: \`$(wc -l <"${OUT}/duplicates.txt")\`"
  echo "- alt glibc receipts: \`$(wc -l <"${OUT}/alt-glibc-receipts.txt")\`"
  echo "- index alt-core references: \`$(wc -l <"${OUT}/index-alt-core.tsv")\`"
  echo "- classic loader validation references: \`$(wc -l <"${OUT}/classic-loader-validation.tsv")\`"
  echo "- normalized-owner packages: \`$(wc -l <"${OUT}/normalized-owner-packages.tsv")\`"
  echo "- missing setuid-preserve metadata: \`$(wc -l <"${OUT}/missing-setuid-preserve-metadata.tsv")\`"
  echo
  echo "## Duplicate active names"
  echo
  if [[ -s "${OUT}/duplicates.txt" ]]; then
    sed 's/^/- /' "${OUT}/duplicates.txt"
  else
    echo "None."
  fi
  echo
  echo "## EFL / Enlightenment identity"
  echo
  if [[ -s "${OUT}/efl-identity.tsv" ]]; then
    sed 's/^/- /' "${OUT}/efl-identity.tsv"
  else
    echo "No EFL/Enlightenment/Terminology records found."
  fi
  echo
  echo "## Canary packages"
  echo
  if [[ -s "${OUT}/canaries.tsv" ]]; then
    sed 's/^/- /' "${OUT}/canaries.tsv" | head -120
  else
    echo "No canary records found."
  fi
  echo
  echo "## Classification"
  echo
  echo
  echo "- keep candidates: packages without duplicate names, alt-core references, normalized-owner archive policy, or missing permission metadata."
  echo "- repack candidates: packages with metadata/launcher/path issues but no source rebuild need."
  echo "- rebuild candidates: substrate layers, duplicate active names, packages built against stale/misidentified base, or packages requiring dev-surface rebuild order."
} >"${OUT}/report.md"

log "report=${OUT}/report.md"
cat "${OUT}/report.md"
