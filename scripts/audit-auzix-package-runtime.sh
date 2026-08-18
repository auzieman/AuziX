#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/auzix-library-policy.sh"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
PACKAGE_FILTER="${2:-}"
AUDIT_MODE="${AUZIX_PACKAGE_RUNTIME_AUDIT_MODE:-fail}"
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

host_resolved_root_path() {
  local auzix_path="$1"
  local host_path link_target current_link suffix
  host_path="$(root_path "${auzix_path}")"
  if [[ "${auzix_path}" == /Programs/*/current/* ]]; then
    current_link="${auzix_path%%/current/*}/current"
    suffix="${auzix_path#*/current/}"
    if [[ -L "$(root_path "${current_link}")" ]]; then
      link_target="$(readlink "$(root_path "${current_link}")")"
      case "${link_target}" in
        /*)
          printf '%s%s/%s\n' "${AUZIX_ROOT}" "${link_target}" "${suffix}"
          return
          ;;
        *)
          printf '%s%s/%s\n' "${AUZIX_ROOT}" "${current_link%/current}/${link_target}" "${suffix}"
          return
          ;;
      esac
    fi
  fi
  if [[ -L "${host_path}" ]]; then
    link_target="$(readlink "${host_path}")"
    case "${link_target}" in
      /*)
        printf '%s%s\n' "${AUZIX_ROOT}" "${link_target}"
        return
        ;;
    esac
  fi
  printf '%s\n' "${host_path}"
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

dependency_receipt_exists() {
  local dependency="$1"
  jq -e --arg dependency "${dependency}" '
    (.name // "" | ascii_downcase) == ($dependency | ascii_downcase)
  ' "${AUZIX_ROOT}/System/PackageDB/"*.auzix.json >/dev/null 2>&1
}

audit_app_local_libraries() {
  local package_name="$1"
  local declared_library_path="$2"
  local library_dir lib class relative
  [[ -n "${declared_library_path}" ]] || return 0
  case "${declared_library_path}" in
    /Programs/*/Libraries|/Programs/*/*/Libraries|/Programs/*/current/Libraries) ;;
    *) return 0 ;;
  esac
  library_dir="$(host_resolved_root_path "${declared_library_path}")"
  [[ -d "${library_dir}" ]] || return 0
  while IFS= read -r lib; do
    class="$(auzix_library_policy_class "${lib}")"
    [[ "${class}" == "app-private" ]] && continue
    relative="${lib#${AUZIX_ROOT}}"
    fail "${package_name}: app-local Libraries contains ${class} substrate library: ${relative}"
  done < <(find "${library_dir}" -maxdepth 2 -type f -name 'lib*.so*' -o -type f -name 'ld-linux*.so*' 2>/dev/null | sort)
}

is_bridge_like_receipt() {
  local migration_stage="$1"
  local source_type="$2"
  case "${migration_stage}:${source_type}" in
    *bridge*:*|*staging*:*|first-pass-*:*|stage-0-*:*|stage-1-*:*|*:host-binary|*:debian-binary)
      return 0
      ;;
  esac
  return 1
}

audit_receipt() {
  local receipt="$1"
  local package_name prefix loader loader_path library_path library_path_json library_path_arg
  local command_path full_command elf output command_count migration_stage source_type bridge_like

  package_name="$(jq -r '.name // empty' "${receipt}")"
  if [[ -n "${PACKAGE_FILTER}" && "${package_name}" != "${PACKAGE_FILTER}" ]]; then
    return
  fi
  prefix="$(jq -r '.prefix // .paths.prefix // empty' "${receipt}")"
  migration_stage="$(jq -r '.migration_stage // empty' "${receipt}")"
  source_type="$(jq -r '.source.type // empty' "${receipt}")"
  if jq -e '(.validation // null) | type == "object"' "${receipt}" >/dev/null; then
    loader="$(jq -r '.validation.loader // empty' "${receipt}")"
    library_path_json="$(jq -c '.validation.library_paths // .runtime_libraries // empty' "${receipt}")"
  else
    loader=""
    library_path_json="$(jq -c '.runtime_libraries // empty' "${receipt}")"
  fi
  library_path="$(jq -r '.runtime_libraries[0] // .paths.libraries // empty' "${receipt}")"
  command_count="$(jq '(.commands // []) | length' "${receipt}")"
  bridge_like=0
  if is_bridge_like_receipt "${migration_stage}" "${source_type}"; then
    bridge_like=1
  fi
  [[ -n "${package_name}" && -n "${prefix}" ]] || {
    if [[ -n "${package_name}" && "${command_count}" -eq 0 ]]; then
      report "INFO: ${package_name}: non-command receipt has no prefix; skipping runtime audit"
    else
      fail "invalid receipt: ${receipt#${AUZIX_ROOT}/}"
    fi
    return
  }

  report "PACKAGE: ${package_name}"
  if [[ "${bridge_like}" != "1" ]]; then
    if [[ "$(jq 'has("source_build") or has("build_receipt") or (.build.receipt_required? == true)' "${receipt}")" != "true" ]]; then
      fail "${package_name}: promoted/non-bridge receipt lacks source build/install receipt"
    fi
  fi
  if [[ "${source_type}" == "debian-binary-package" || "${source_type}" == "installed-debian-package" ]]; then
    if [[ "$(jq 'has("debian_package_db") and ((.debian_package_db.payload_manifest // []) | length > 0)' "${receipt}")" != "true" ]]; then
      fail "${package_name}: Debian-derived receipt lacks dpkg-style payload manifest"
    fi
  fi
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
  while IFS= read -r declared_runtime_library; do
    audit_app_local_libraries "${package_name}" "${declared_runtime_library}"
  done < <(jq -r '.runtime_libraries[]? // .paths.libraries? // empty' "${receipt}")
  while IFS= read -r dependency; do
    [[ -n "${dependency}" ]] || continue
    if ! dependency_receipt_exists "${dependency}"; then
      if [[ "${bridge_like}" == "1" ]]; then
        report "INFO: ${package_name}: bridge/proof dependency has no local receipt yet: ${dependency}"
      else
        fail "${package_name}: declared dependency has no local receipt: ${dependency}"
      fi
    fi
  done < <(jq -r '.depends[]?' "${receipt}")

  if [[ "${library_path_json}" != "" && "${library_path_json}" != "null" ]]; then
    library_path_arg="$(
      jq -r '.[]?' <<<"${library_path_json}" |
        while IFS= read -r path_item; do
          [[ -n "${path_item}" ]] || continue
          host_resolved_root_path "${path_item}"
        done | paste -sd: -
    )"
  elif [[ -n "${library_path}" ]]; then
    library_path_arg="$(root_path "${library_path}")"
  else
    library_path_arg=""
  fi

  [[ -n "${loader}" && -n "${library_path_arg}" ]] || {
    if [[ "${command_count}" -gt 0 ]]; then
      if [[ "${bridge_like}" == "1" ]]; then
        report "INFO: ${package_name}: bridge/proof command package has no bundled-loader/library validation contract yet"
      else
        fail "${package_name}: command-bearing package has no bundled-loader/library validation contract"
      fi
    else
      report "INFO: ${package_name}: no bundled-loader validation contract"
    fi
    return
  }
  loader_path="$(host_resolved_root_path "${loader}")"
  [[ -x "${loader_path}" ]] || {
    fail "${package_name}: loader is missing or not executable: ${loader}"
    return
  }

  while IFS= read -r elf; do
    file "${elf}" | grep -q 'ELF' || continue
    output="$(
      LD_LIBRARY_PATH="${library_path_arg}" \
        "${loader_path}" \
        --library-path "${library_path_arg}" \
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

  while IFS= read -r command_path; do
    [[ -n "${command_path}" ]] || continue
    full_command="$(host_resolved_root_path "${command_path}")"
    [[ -x "${full_command}" ]] || {
      fail "${package_name}: front-door command is missing or not executable: ${command_path}"
      continue
    }
    if head -n 1 "${full_command}" 2>/dev/null | grep -q '^#!'; then
      if grep -qE '/usr/bin|/bin/|/usr/sbin|/sbin/' "${full_command}" 2>/dev/null; then
        fail "${package_name}: wrapper contains donor command paths: ${command_path}"
      fi
    fi
  done < <(jq -r '.commands[]?' "${receipt}")
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
  case "${AUDIT_MODE}" in
    warn|warning|report)
      report "AuziX package runtime audit: WARN (${failures}); continuing because AUZIX_PACKAGE_RUNTIME_AUDIT_MODE=${AUDIT_MODE}"
      exit 0
      ;;
    *)
      report "AuziX package runtime audit: FAIL (${failures})"
      exit 1
      ;;
  esac
fi
report "AuziX package runtime audit: PASS"
