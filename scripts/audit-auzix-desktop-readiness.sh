#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
REPORT_PATH="${2:-${ROOT_DIR}/out/package-bot/desktop-readiness.tsv}"

mkdir -p "$(dirname "${REPORT_PATH}")"

if [[ ! -d "${AUZIX_ROOT}/System/PackageDB" ]]; then
  printf 'desktop readiness audit: PackageDB missing: %s\n' "${AUZIX_ROOT}/System/PackageDB" >&2
  exit 2
fi

printf 'package\tkind\tcommand_count\tdesktop_count\tmenu_exec_count\tstatus\tnotes\n' >"${REPORT_PATH}"

find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f -name '*.json' -print |
  sort |
  while IFS= read -r receipt; do
    name="$(jq -r '.name // empty' "${receipt}")"
    kind="$(jq -r '.kind // "unknown"' "${receipt}")"
    [[ -n "${name}" ]] || continue

    command_count="$(jq '(.commands // []) | length' "${receipt}")"
    mapfile -t desktop_entries < <(
      jq -r '
        [
          (.desktop_entries? // empty),
          (.compatibility_exports? // [] | .[]? | select(endswith(".desktop")))
        ]
        | flatten
        | .[]?
      ' "${receipt}" 2>/dev/null |
        sort -u
    )

    desktop_count=0
    menu_exec_count=0
    notes=()
    for desktop_entry in "${desktop_entries[@]}"; do
      desktop_path="${AUZIX_ROOT}/${desktop_entry#/}"
      [[ -s "${desktop_path}" ]] || {
        notes+=("missing-desktop:${desktop_entry}")
        continue
      }
      desktop_count=$((desktop_count + 1))
      if grep -Eq '^Exec=/Programs/|^Exec=/System/Tools/|^Exec=/System/Compatibility/' "${desktop_path}"; then
        menu_exec_count=$((menu_exec_count + 1))
      else
        notes+=("desktop-exec-not-auzix:${desktop_entry}")
      fi
    done

    status=skip
    if [[ "${kind}" == "program" || "${kind}" == "application-adapter" ]]; then
      status=pass
      if [[ "${command_count}" -eq 0 ]]; then
        status=fail
        notes+=("no-commands")
      fi
      if [[ "${desktop_count}" -eq 0 ]]; then
        status=fail
        notes+=("no-menu-entry")
      elif [[ "${menu_exec_count}" -eq 0 ]]; then
        status=fail
        notes+=("no-auzix-menu-exec")
      fi
    fi

    note_text="$(IFS=,; printf '%s' "${notes[*]:-}")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${name}" "${kind}" "${command_count}" "${desktop_count}" "${menu_exec_count}" "${status}" "${note_text}" \
      >>"${REPORT_PATH}"
  done

fail_count="$(awk -F '\t' 'NR > 1 && $6 == "fail" {count++} END {print count+0}' "${REPORT_PATH}")"
printf 'desktop readiness audit: %s failing desktop packages; report=%s\n' "${fail_count}" "${REPORT_PATH}" >&2

jq -n \
  --arg report "${REPORT_PATH}" \
  --argjson failing_desktop_packages "${fail_count}" \
  '{
    format: "auzix-desktop-readiness-audit-v1",
    report: $report,
    failing_desktop_packages: $failing_desktop_packages,
    status: (if $failing_desktop_packages == 0 then "pass" else "warn" end)
  }'
