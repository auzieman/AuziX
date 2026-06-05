#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
REPORT_PATH="${2:-${ROOT_DIR}/out/auzix-strict/audit-report.txt}"
EVIDENCE_PATH="${REPORT_PATH%.txt}.evidence.txt"
LEGACY_POLICY="${AUZIX_LEGACY_POLICY:-compat}"

native_dirs=(
  System
  Programs
  Services
  Stacks
  Work
  Users
  Volumes
  Network
)

runtime_dirs=(
  dev
  proc
  sys
  run
)

compat_links=(
  bin
  sbin
  lib
  lib64
  usr
  etc
  var
  tmp
  opt
  home
  root
)

failures=0

mkdir -p "$(dirname "${REPORT_PATH}")"
: > "${REPORT_PATH}"
: > "${EVIDENCE_PATH}"

report() {
  printf '%s\n' "$*" | tee -a "${REPORT_PATH}"
}

evidence() {
  printf '%s\n' "$*" | tee -a "${EVIDENCE_PATH}" >/dev/null
}

fail() {
  failures=$((failures + 1))
  report "FAIL: $*"
}

pass() {
  report "PASS: $*"
}

resolve_root_path() {
  local path="$1"
  local rel first rest target
  rel="${path#/}"
  first="${rel%%/*}"
  if [[ "${rel}" == "${first}" ]]; then
    rest=""
  else
    rest="${rel#*/}"
  fi

  if [[ -L "${AUZIX_ROOT}/${first}" ]]; then
    target="$(readlink "${AUZIX_ROOT}/${first}")"
    if [[ "${target}" == /* ]]; then
      if [[ -n "${rest}" ]]; then
        printf '%s%s/%s\n' "${AUZIX_ROOT}" "${target}" "${rest}"
      else
        printf '%s%s\n' "${AUZIX_ROOT}" "${target}"
      fi
      return
    fi
  fi

  printf '%s/%s\n' "${AUZIX_ROOT}" "${rel}"
}

if [[ ! -d "${AUZIX_ROOT}" ]]; then
  printf 'Auzix root not found: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

report "Auzix strict root audit"
report "Root: ${AUZIX_ROOT}"
report "Evidence: ${EVIDENCE_PATH}"
report "Legacy policy: ${LEGACY_POLICY}"
report ""

evidence "Auzix strict root evidence"
evidence "Root: ${AUZIX_ROOT}"
evidence ""

report "Native top-level directories"
for dir in "${native_dirs[@]}"; do
  if [[ -d "${AUZIX_ROOT}/${dir}" ]]; then
    pass "/${dir}"
  else
    fail "missing /${dir}"
  fi
done

report ""
report "Linux runtime directories"
for dir in "${runtime_dirs[@]}"; do
  if [[ -d "${AUZIX_ROOT}/${dir}" && ! -L "${AUZIX_ROOT}/${dir}" ]]; then
    pass "/${dir}"
  else
    fail "/${dir} must be a real directory in the staged root"
  fi
done

report ""
report "Compatibility links"
case "${LEGACY_POLICY}" in
  compat)
    for link_name in "${compat_links[@]}"; do
      if [[ -L "${AUZIX_ROOT}/${link_name}" ]]; then
        pass "/${link_name} -> $(readlink "${AUZIX_ROOT}/${link_name}")"
      else
        fail "/${link_name} must be a declared symlink"
      fi
    done
    ;;
  invalid)
    for link_name in "${compat_links[@]}"; do
      if [[ -e "${AUZIX_ROOT}/${link_name}" || -L "${AUZIX_ROOT}/${link_name}" ]]; then
        fail "/${link_name} exists while AUZIX_LEGACY_POLICY=invalid"
      else
        pass "/${link_name} absent"
      fi
    done
    ;;
  *)
    fail "unknown AUZIX_LEGACY_POLICY=${LEGACY_POLICY}"
    ;;
esac

report ""
report "Compatibility subpaths"
if [[ "${LEGACY_POLICY}" == "compat" ]]; then
  for link in \
    "/var/tmp:/Work/Temp" \
    "/var/run:/run" \
    "/var/lock:/run/lock"; do
    path="${link%%:*}"
    target="${link#*:}"
    full="$(resolve_root_path "${path}")"
    if [[ -L "${full}" && "$(readlink "${full}")" == "${target}" ]]; then
      pass "${path} -> ${target}"
    else
      fail "${path} must be a symlink to ${target}"
    fi
  done
else
  report "INFO: skipped compatibility subpath validation under AUZIX_LEGACY_POLICY=${LEGACY_POLICY}"
fi

report ""
report "Legacy path stray scan"
for link_name in "${compat_links[@]}"; do
  if [[ -e "${AUZIX_ROOT}/${link_name}" && ! -L "${AUZIX_ROOT}/${link_name}" ]]; then
    fail "/${link_name} is a real path, not compatibility scaffolding"
  fi
done

if find "${AUZIX_ROOT}" -xdev \( \
  -path "${AUZIX_ROOT}/System/Compatibility/*" -o \
  -path "${AUZIX_ROOT}/System/Settings/*" -o \
  -path "${AUZIX_ROOT}/System/State/*" -o \
  -path "${AUZIX_ROOT}/Work/Temp/*" -o \
  -path "${AUZIX_ROOT}/Programs/*" -o \
  -path "${AUZIX_ROOT}/Users/*" \
  \) -prune -o \( \
  -path "${AUZIX_ROOT}/bin/*" -o \
  -path "${AUZIX_ROOT}/sbin/*" -o \
  -path "${AUZIX_ROOT}/lib/*" -o \
  -path "${AUZIX_ROOT}/lib64/*" -o \
  -path "${AUZIX_ROOT}/usr/*" -o \
  -path "${AUZIX_ROOT}/etc/*" -o \
  -path "${AUZIX_ROOT}/var/*" -o \
  -path "${AUZIX_ROOT}/tmp/*" -o \
  -path "${AUZIX_ROOT}/opt/*" -o \
  -path "${AUZIX_ROOT}/home/*" \
  \) -print | grep -q .; then
  fail "found undeclared files under legacy compatibility paths"
else
  pass "no undeclared files under legacy compatibility paths"
fi

report ""
report "Executable dependency scan"
mapfile -t executables < <(find "${AUZIX_ROOT}/Programs" "${AUZIX_ROOT}/System/Tools" -type f -perm /111 2>/dev/null | sort)
if [[ ${#executables[@]} -eq 0 ]]; then
  report "INFO: no executable payloads yet; ldd/readelf checks skipped"
else
  for exe in "${executables[@]}"; do
    if command -v readelf >/dev/null 2>&1 && readelf -h "${exe}" >/dev/null 2>&1; then
      report "INFO: ELF executable: ${exe#${AUZIX_ROOT}}"
      evidence "================================================================================"
      evidence "Executable: ${exe#${AUZIX_ROOT}}"
      evidence ""
      if command -v stat >/dev/null 2>&1; then
        evidence "[stat]"
        stat "${exe}" 2>&1 | tee -a "${EVIDENCE_PATH}" >/dev/null || true
        evidence ""
      fi
      if command -v file >/dev/null 2>&1; then
        evidence "[file]"
        file "${exe}" 2>&1 | tee -a "${EVIDENCE_PATH}" >/dev/null || true
        evidence ""
      fi
      evidence "[readelf -h]"
      readelf -h "${exe}" 2>&1 | tee -a "${EVIDENCE_PATH}" >/dev/null || true
      evidence ""
      evidence "[readelf -l interpreter]"
      readelf -l "${exe}" 2>&1 | sed -n '/Requesting program interpreter/p;/INTERP/,+2p' | tee -a "${EVIDENCE_PATH}" >/dev/null || true
      evidence ""
      evidence "[readelf -d]"
      readelf -d "${exe}" 2>&1 | tee -a "${EVIDENCE_PATH}" >/dev/null || true
      evidence ""
      if command -v objdump >/dev/null 2>&1; then
        evidence "[objdump -p dynamic fields]"
        objdump -p "${exe}" 2>&1 | grep -E 'program interpreter|NEEDED|RPATH|RUNPATH|SONAME' | tee -a "${EVIDENCE_PATH}" >/dev/null || true
        evidence ""
      fi
      if command -v ldd >/dev/null 2>&1; then
        evidence "[ldd]"
        ldd "${exe}" 2>&1 | tee -a "${EVIDENCE_PATH}" >/dev/null || true
        evidence ""
        interpreter="$(readelf -l "${exe}" 2>/dev/null | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p' | head -n 1)"
        if [[ "${interpreter}" =~ ^/(lib|lib64|usr) ]]; then
          interpreter_path="$(resolve_root_path "${interpreter}")"
          if [[ -e "${interpreter_path}" || -L "${interpreter_path}" ]]; then
            report "WARN: legacy dynamic interpreter ${interpreter} is satisfied by compatibility surface for ${exe#${AUZIX_ROOT}}"
          else
            fail "legacy dynamic interpreter ${interpreter} is missing for ${exe#${AUZIX_ROOT}}"
          fi
        elif readelf -d "${exe}" 2>/dev/null | grep -E 'RPATH|RUNPATH' | grep -E '/usr/|/lib/|/lib64/|/usr/local/' >/dev/null; then
          fail "legacy RPATH/RUNPATH appears in ELF dynamic section for ${exe#${AUZIX_ROOT}}"
        elif ldd "${exe}" 2>/dev/null | grep -E '/usr/|/lib/|/lib64/|/usr/local/' >/dev/null; then
          report "WARN: host ldd resolved legacy paths for ${exe#${AUZIX_ROOT}}; ELF interpreter/RUNPATH remain native"
        else
          pass "no legacy library path surfaced for ${exe#${AUZIX_ROOT}}"
        fi
      fi
      if command -v strings >/dev/null 2>&1; then
        evidence "[strings legacy-path hits]"
        strings -a "${exe}" | grep -E '(^|[^A-Za-z0-9_])/(bin|sbin|lib|lib64|usr|usr/local|etc|var|tmp|home)(/|$)' | sort -u | tee -a "${EVIDENCE_PATH}" >/dev/null || true
        evidence ""
      fi
    fi
  done
fi

report ""
if [[ ${failures} -eq 0 ]]; then
  report "Auzix strict root audit: PASS"
else
  report "Auzix strict root audit: FAIL (${failures})"
fi

exit "${failures}"
