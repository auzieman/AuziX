#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-/}"
REPORT_PATH="${2:-${ROOT_DIR}/out/package-bot/enlightenment-launch-evidence.txt}"

mkdir -p "$(dirname "${REPORT_PATH}")"

case "${AUZIX_ROOT}" in
  /) root_prefix="" ;;
  *) root_prefix="${AUZIX_ROOT}" ;;
esac

p() {
  printf '%s%s\n' "${root_prefix}" "$1"
}

{
  printf 'AUZiX Enlightenment launch evidence\n'
  printf 'generated_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'root=%s\n\n' "${AUZIX_ROOT}"

  printf '## Enlightenment user logs\n\n'
  find "$(p /Users)" -maxdepth 2 -type f \
    \( -name '.e-log.log' -o -name 'e.log' -o -name 'enlightenment*.log' \) \
    -print 2>/dev/null |
    sort |
    while IFS= read -r log_path; do
      printf '### %s\n' "${log_path}"
      tail -n 80 "${log_path}" 2>/dev/null || true
      printf '\n'
    done

  printf '## Package/session logs that often include launcher failures\n\n'
  find "$(p /System/Logs)" -maxdepth 3 -type f \
    \( -name '*enlightenment*.log' -o -name '*efreet*.log' -o -name '*desktop*.log' -o -name '*launcher*.log' \) \
    -print 2>/dev/null |
    sort |
    while IFS= read -r log_path; do
      printf '### %s\n' "${log_path}"
      tail -n 80 "${log_path}" 2>/dev/null || true
      printf '\n'
    done

  printf '## Visible desktop entries and Exec targets\n\n'
  app_dir="$(p /System/Compatibility/usr/share/applications)"
  if [[ -d "${app_dir}" ]]; then
    find "${app_dir}" -maxdepth 1 -type f -name '*.desktop' -print |
      sort |
      while IFS= read -r desktop_file; do
        if grep -Eq '^(NoDisplay=true|Hidden=true)' "${desktop_file}"; then
          continue
        fi
        printf '### %s\n' "${desktop_file}"
        grep -E '^(Name|Exec|TryExec|Icon|Categories|NoDisplay|Hidden|X-AUZiX-Launcher-State)=' \
          "${desktop_file}" 2>/dev/null || true
        printf '\n'
      done
  fi
} >"${REPORT_PATH}"

printf 'enlightenment launch evidence: %s\n' "${REPORT_PATH}" >&2

