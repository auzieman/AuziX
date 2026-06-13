#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
PACKAGE_FILTER="${2:-}"
failures=0

report() {
  printf '%s\n' "$*"
}

fail() {
  report "FAIL: $*"
  failures=$((failures + 1))
}

root_path() {
  printf '%s%s\n' "${AUZIX_ROOT}" "$1"
}

check_declared_path() {
  local package_name="$1"
  local declared_path="$2"
  local full_path
  full_path="$(root_path "${declared_path}")"
  if [[ -e "${full_path}" || -L "${full_path}" ]]; then
    return 0
  fi
  fail "${package_name}: declared path is missing: ${declared_path}"
}

audit_receipt() {
  local receipt="$1"
  local package_name prefix loader loader_path library_path
  local command_path full_command elf output

  package_name="$(jq -r '.name // empty' "${receipt}")"
  prefix="$(jq -r '.prefix // .paths.prefix // empty' "${receipt}")"
  loader="$(jq -r '.validation.loader // empty' "${receipt}")"
  library_path="$(jq -r '.runtime_libraries[0] // .paths.libraries // empty' "${receipt}")"
  [[ -n "${package_name}" && -n "${prefix}" ]] || {
    fail "invalid receipt: ${receipt#${AUZIX_ROOT}/}"
    return
  }
  if [[ -n "${PACKAGE_FILTER}" && "${package_name}" != "${PACKAGE_FILTER}" ]]; then
    return
  fi

  report "PACKAGE: ${package_name}"
  check_declared_path "${package_name}" "${prefix}"
  while IFS= read -r command_path; do
    [[ -n "${command_path}" ]] || continue
    check_declared_path "${package_name}" "${command_path}"
  done < <(jq -r '.commands[]?' "${receipt}")
  while IFS= read -r command_path; do
    [[ -n "${command_path}" ]] || continue
    check_declared_path "${package_name}" "${command_path}"
  done < <(jq -r '.compatibility_exports[]?' "${receipt}")
  while IFS= read -r command_path; do
    [[ -n "${command_path}" ]] || continue
    check_declared_path "${package_name}" "${command_path}"
  done < <(jq -r '.runtime_libraries[]?' "${receipt}")

  [[ -n "${loader}" && -n "${library_path}" ]] || {
    report "INFO: ${package_name}: no bundled-loader validation contract"
    return
  }
  loader_path="$(root_path "${loader}")"
  [[ -x "${loader_path}" ]] || {
    fail "${package_name}: loader is missing or not executable: ${loader}"
    return
  }

  while IFS= read -r elf; do
    file "${elf}" | grep -q 'ELF' || continue
    output="$(
      LD_LIBRARY_PATH="$(root_path "${library_path}")" \
        "${loader_path}" \
        --library-path "$(root_path "${library_path}")" \
        --list "${elf}" 2>&1
    )" || {
      fail "${package_name}: loader audit failed: ${elf#${AUZIX_ROOT}}"
      report "${output}"
      continue
    }
    if grep -q 'not found' <<<"${output}"; then
      fail "${package_name}: unresolved dependency: ${elf#${AUZIX_ROOT}}"
      grep 'not found' <<<"${output}"
    fi
  done < <(find "$(root_path "${prefix}")" -type f -perm /111 2>/dev/null | sort)
}

for command_name in file find jq; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "${command_name}" >&2
    exit 1
  }
done
[[ -d "${AUZIX_ROOT}/System/PackageDB" ]] || {
  printf 'AuziX PackageDB is missing: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
}

while IFS= read -r receipt; do
  audit_receipt "${receipt}"
done < <(
  find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f -name '*.auzix.json' |
    sort
)

if (( failures > 0 )); then
  report "AuziX package runtime audit: FAIL (${failures})"
  exit 1
fi
report "AuziX package runtime audit: PASS"
