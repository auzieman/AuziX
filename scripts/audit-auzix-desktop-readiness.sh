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

printf 'package\tkind\tcommand_count\tdesktop_count\tvisible_desktop_count\tvisible_menu_exec_count\tstatus\tnotes\n' >"${REPORT_PATH}"

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
    visible_desktop_count=0
    visible_menu_exec_count=0
    notes=()
    for desktop_entry in "${desktop_entries[@]}"; do
      desktop_path="${AUZIX_ROOT}/${desktop_entry#/}"
      [[ -s "${desktop_path}" ]] || {
        notes+=("missing-desktop:${desktop_entry}")
        continue
      }
      desktop_count=$((desktop_count + 1))
      has_auzix_exec=0
      if grep -Eq '^Exec=/Programs/[^/]+/current/Commands/' "${desktop_path}"; then
        has_auzix_exec=1
      fi
      if ! grep -Eq '^(NoDisplay=true|Hidden=true)' "${desktop_path}"; then
        visible_desktop_count=$((visible_desktop_count + 1))
        if [[ "${has_auzix_exec}" -eq 1 ]]; then
          visible_menu_exec_count=$((visible_menu_exec_count + 1))
        else
          notes+=("visible-desktop-exec-not-front-door:${desktop_entry}")
        fi
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
      elif [[ "${visible_desktop_count}" -gt 1 ]]; then
        status=fail
        notes+=("duplicate-visible-menu-entries:${visible_desktop_count}")
      elif [[ "${visible_desktop_count}" -eq 0 ]]; then
        [[ "${status}" == "fail" ]] || status=warn
        notes+=("installed-not-desktop-visible")
      elif [[ "${visible_menu_exec_count}" -eq 0 ]]; then
        status=fail
        notes+=("no-auzix-menu-exec")
      fi
    fi

    note_text="$(IFS=,; printf '%s' "${notes[*]:-}")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${name}" "${kind}" "${command_count}" "${desktop_count}" "${visible_desktop_count}" "${visible_menu_exec_count}" "${status}" "${note_text}" \
      >>"${REPORT_PATH}"
  done

fail_count="$(awk -F '\t' 'NR > 1 && $7 == "fail" {count++} END {print count+0}' "${REPORT_PATH}")"
printf 'desktop readiness audit: %s failing desktop packages; report=%s\n' "${fail_count}" "${REPORT_PATH}" >&2

jq -n \
  --arg report "${REPORT_PATH}" \
  --argjson failing_desktop_packages "${fail_count}" \
  '{
    format: "auzix-desktop-readiness-audit-v1",
    report: $report,
    failing_desktop_packages: $failing_desktop_packages,
    status: (if $failing_desktop_packages == 0 then "pass" else "fail" end)
  }'

if [[ "${fail_count}" -gt 0 ]]; then
  exit 1
fi
