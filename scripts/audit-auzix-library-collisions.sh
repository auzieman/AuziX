#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/}"
OUT="${2:-/tmp/auzix-library-collisions-$(date -u +%Y%m%dT%H%M%SZ)}"

mkdir -p "${OUT}"

root_path() {
  local path="$1"
  if [[ "${ROOT}" == "/" ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s/%s\n' "${ROOT%/}" "${path#/}"
  fi
}

scan_root() {
  local label="$1"
  local path="$2"
  local full
  full="$(root_path "${path}")"
  [[ -d "${full}" ]] || return 0
  find "${full}" \( -type f -o -type l \) 2>/dev/null |
    awk -v label="${label}" -v root="${ROOT%/}" '
      /\/lib/ && /[.]so/ {
        p=$0
        rel=p
        if (root != "" && root != "/") sub("^" root, "", rel)
        n=p
        sub(/^.*\//, "", n)
        if (n ~ /^lib/ && n ~ /[.]so/) print n "\t" label "\t" rel
      }
    '
}

{
  scan_root system-libraries /System/Libraries
  scan_root compat-lib /System/Compatibility/lib
  scan_root compat-usr-lib /System/Compatibility/usr/lib
  scan_root programs /Programs
} | sort >"${OUT}/libraries.tsv"

awk -F '\t' '
  {
    count[$1]++
    lines[$1]=lines[$1] $0 "\n"
  }
  END {
    for (name in count) {
      if (count[name] > 1) {
        printf "%s\t%d\n%s", name, count[name], lines[name]
      }
    }
  }
' "${OUT}/libraries.tsv" | sort >"${OUT}/collisions.tsv"

awk -F '\t' '
  {
    if ($3 ~ /^\/System\/Libraries/ || $3 ~ /^\/System\/Compatibility/) next
    if ($1 ~ /^(libc|libm|libpthread|librt|libdl|ld-linux|libgcc_s|libstdc[+][+]|libatomic|libssl|libcrypto|libeina|libevas|libedje|libelementary|libefreet|libecore|libglib|libgtk|libgdk|libpango|libcairo|libfontconfig|libfreetype)/) {
      print
    }
  }
' "${OUT}/libraries.tsv" >"${OUT}/program-coreish-libs.tsv"

{
  echo "# AUZiX library collision audit"
  echo
  echo "- generated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- root: \`${ROOT}\`"
  echo "- libraries: \`$(wc -l <"${OUT}/libraries.tsv")\`"
  echo "- colliding basenames: \`$(awk -F '\t' 'NF==2 {n++} END {print n+0}' "${OUT}/collisions.tsv")\`"
  echo "- program-owned core-ish libs: \`$(wc -l <"${OUT}/program-coreish-libs.tsv")\`"
  echo
  echo "## Program-owned core-ish libs"
  echo
  if [[ -s "${OUT}/program-coreish-libs.tsv" ]]; then
    awk 'NR <= 200 { print "- " $0 }' "${OUT}/program-coreish-libs.tsv"
  else
    echo "None."
  fi
  echo
  echo "## First collisions"
  echo
  if [[ -s "${OUT}/collisions.tsv" ]]; then
    awk 'NR <= 240 { print "- " $0 }' "${OUT}/collisions.tsv"
  else
    echo "None."
  fi
} >"${OUT}/report.md"

cat "${OUT}/report.md"
printf '[auzix-library-collisions] out=%s\n' "${OUT}" >&2
