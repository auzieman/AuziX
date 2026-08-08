#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
REPORT_PATH="${2:-${ROOT_DIR}/out/package-bot/command-ldd.tsv}"
PACKAGE_FILTER="${3:-}"

mkdir -p "$(dirname "${REPORT_PATH}")"

for command_name in file find jq ldd; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    printf 'command ldd audit: missing required command: %s\n' "${command_name}" >&2
    exit 1
  }
done

[[ -d "${AUZIX_ROOT}/System/PackageDB" ]] || {
  printf 'command ldd audit: PackageDB missing: %s\n' "${AUZIX_ROOT}/System/PackageDB" >&2
  exit 2
}

root_path() {
  printf '%s/%s\n' "${AUZIX_ROOT}" "${1#/}"
}

package_library_path() {
  local prefix="$1"
  local receipt="$2"
  local rootfs
  rootfs="$(root_path "${prefix}")/RootFS"
  printf '%s' "$(root_path "${prefix}")/Libraries"
  if [[ -d "${rootfs}" ]]; then
    printf ':%s' \
      "${rootfs}/usr/lib/x86_64-linux-gnu" \
      "${rootfs}/usr/lib" \
      "${rootfs}/lib/x86_64-linux-gnu" \
      "${rootfs}/lib"
  fi
  while IFS= read -r dependency_name; do
    [[ -n "${dependency_name}" ]] || continue
    dependency_root="${AUZIX_ROOT}/Programs/${dependency_name}/current"
    dependency_rootfs="${dependency_root}/RootFS"
    [[ -d "${dependency_root}" || -d "${dependency_rootfs}" ]] || continue
    printf ':%s' "${dependency_root}/Libraries"
    if [[ -d "${dependency_rootfs}" ]]; then
      printf ':%s' \
        "${dependency_rootfs}/usr/lib/x86_64-linux-gnu" \
        "${dependency_rootfs}/usr/lib" \
        "${dependency_rootfs}/lib/x86_64-linux-gnu" \
        "${dependency_rootfs}/lib"
    fi
  done < <(jq -r '.runtime_ladder.dependency_packages[]?, .depends[]?' "${receipt}" 2>/dev/null | awk '!seen[$0]++')
  printf ':%s' \
    "${AUZIX_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu" \
    "${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu" \
    "${AUZIX_ROOT}/System/Compatibility/lib64" \
    "${AUZIX_ROOT}/System/Libraries"
}

candidate_elfs_for_command() {
  local command_path="$1"
  local full_command="$2"
  local prefix="$3"
  local rootfs

  rootfs="$(root_path "${prefix}")/RootFS"

  if file "${full_command}" 2>/dev/null | grep -q 'ELF'; then
    printf '%s\n' "${full_command}"
    return
  fi

  if [[ -s "${full_command}" ]]; then
    sed -n 's/.*exec "\${rootfs}"\([^"]*\).*/\1/p' "${full_command}" |
      while IFS= read -r rel_exec; do
        [[ -n "${rel_exec}" && -x "${rootfs}${rel_exec}" ]] && printf '%s\n' "${rootfs}${rel_exec}"
      done
  fi

  local command_base
  command_base="$(basename "${command_path}")"
  for candidate in \
    "$(dirname "${full_command}")/${command_base}.real" \
    "${rootfs}/usr/bin/${command_base}" \
    "${rootfs}/usr/sbin/${command_base}" \
    "${rootfs}/bin/${command_base}" \
    "${rootfs}/sbin/${command_base}"; do
    [[ -x "${candidate}" ]] || continue
    file "${candidate}" 2>/dev/null | grep -q 'ELF' || continue
    printf '%s\n' "${candidate}"
  done
}

printf 'package\tcommand\telf\tstatus\tldd_summary\n' >"${REPORT_PATH}"
failures=0

find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f -name '*.json' -print |
  sort |
  while IFS= read -r receipt; do
    package_name="$(jq -r '.name // empty' "${receipt}")"
    prefix="$(jq -r '.prefix // .paths.prefix // empty' "${receipt}")"
    [[ -n "${package_name}" && -n "${prefix}" ]] || continue
    [[ -z "${PACKAGE_FILTER}" || "${package_name}" == "${PACKAGE_FILTER}" ]] || continue

    while IFS= read -r command_path; do
      [[ -n "${command_path}" ]] || continue
      full_command="$(root_path "${command_path}")"
      if [[ ! -x "${full_command}" ]]; then
        printf '%s\t%s\t\tmissing-command\t%s\n' "${package_name}" "${command_path}" "declared command is missing or not executable" >>"${REPORT_PATH}"
        failures=$((failures + 1))
        continue
      fi

      mapfile -t elfs < <(candidate_elfs_for_command "${command_path}" "${full_command}" "${prefix}" | sort -u)
      if [[ "${#elfs[@]}" -eq 0 ]]; then
        printf '%s\t%s\t\tno-elf\t%s\n' "${package_name}" "${command_path}" "script or non-ELF command; launch-smoke required" >>"${REPORT_PATH}"
        continue
      fi

      library_path="$(package_library_path "${prefix}" "${receipt}")"
      for elf in "${elfs[@]}"; do
        output="$(LD_LIBRARY_PATH="${library_path}" ldd "${elf}" 2>&1 || true)"
        summary="$(printf '%s\n' "${output}" | tr '\t\r\n' '   ' | cut -c1-300)"
        status=pass
        if grep -Eq 'not found|version `[^'\'' ]+'\'' not found|undefined symbol' <<<"${output}"; then
          status=fail
          failures=$((failures + 1))
        fi
        printf '%s\t%s\t%s\t%s\t%s\n' \
          "${package_name}" "${command_path}" "${elf#${AUZIX_ROOT}}" "${status}" "${summary}" >>"${REPORT_PATH}"
      done
    done < <(jq -r '.commands[]?' "${receipt}")
  done

fail_count="$(awk -F '\t' 'NR > 1 && $4 == "fail" {count++} END {print count+0}' "${REPORT_PATH}")"
printf 'command ldd audit: %s failing command ELF payloads; report=%s\n' "${fail_count}" "${REPORT_PATH}" >&2

jq -n \
  --arg report "${REPORT_PATH}" \
  --argjson failing_command_elfs "${fail_count}" \
  '{
    format: "auzix-command-ldd-audit-v1",
    report: $report,
    failing_command_elfs: $failing_command_elfs,
    status: (if $failing_command_elfs == 0 then "pass" else "warn" end)
  }'
