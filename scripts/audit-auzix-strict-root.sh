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

resolve_program_current_path() {
  local path="$1"
  local rel program rest current_link version
  rel="${path#/Programs/}"
  program="${rel%%/*}"
  rest="${rel#*/current/}"
  current_link="${AUZIX_ROOT}/Programs/${program}/current"
  if [[ -L "${current_link}" ]]; then
    version="$(basename "$(readlink "${current_link}")")"
    printf '%s/Programs/%s/%s/%s\n' "${AUZIX_ROOT}" "${program}" "${version}" "${rest}"
    return
  fi
  resolve_root_path "${path}"
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
report "Identity baseline"
passwd_file="${AUZIX_ROOT}/System/Settings/passwd"
group_file="${AUZIX_ROOT}/System/Settings/group"
shadow_file="${AUZIX_ROOT}/System/Settings/shadow"
if [[ -f "${passwd_file}" ]] && grep -Fq 'auzix:x:1000:1000:' "${passwd_file}"; then
  pass "/System/Settings/passwd contains auzix uid 1000"
else
  fail "/System/Settings/passwd is missing auzix uid 1000"
fi
if [[ -f "${group_file}" ]] && grep -Fq 'auzix:x:1000:' "${group_file}"; then
  pass "/System/Settings/group contains auzix gid 1000"
else
  fail "/System/Settings/group is missing auzix gid 1000"
fi
if [[ -d "${AUZIX_ROOT}/Users/auzix" ]]; then
  pass "/Users/auzix exists"
else
  fail "/Users/auzix is missing"
fi
if [[ -f "${shadow_file}" ]]; then
  mode="$(stat -c '%a' "${shadow_file}" 2>/dev/null || true)"
  if [[ "${mode}" == "600" ]]; then
    pass "/System/Settings/shadow mode is 0600"
  else
    fail "/System/Settings/shadow mode must be 0600, got ${mode:-unknown}"
  fi
else
  fail "/System/Settings/shadow is missing"
fi

report ""
report "Runtime network and browser contract"
start_sequence="${AUZIX_ROOT}/System/Boot/StartSequence"
ca_bundle="${AUZIX_ROOT}/System/Compatibility/etc/ssl/certs/ca-certificates.crt"
mdev_config="${AUZIX_ROOT}/System/Settings/mdev.conf"

if [[ -x "${start_sequence}" ]]; then
  pass "/System/Boot/StartSequence is executable"
else
  fail "/System/Boot/StartSequence is missing or not executable"
fi

runtime_contract_patterns=(
  'ping_group_range'
  'chmod 0666 /dev/random /dev/urandom'
  'ln -sfn /run/resolv.conf /System/Settings/resolv.conf'
  'udhcpc -i "${iface}"'
  'chown -R 1000:1000'
  '/Users/auzix/.cache'
  '/Users/auzix/.config'
  '/Users/auzix/.local'
)
for pattern in "${runtime_contract_patterns[@]}"; do
  if [[ -f "${start_sequence}" ]] && grep -Fq "${pattern}" "${start_sequence}"; then
    pass "startup contract contains ${pattern}"
  else
    fail "startup contract is missing ${pattern}"
  fi
done

if [[ -f "${start_sequence}" ]]; then
  mdev_scan_count="$(grep -Fc '"${BB}" mdev -s' "${start_sequence}" || true)"
  entropy_repair_count="$(grep -Fc '"${BB}" chmod 0666 /dev/random /dev/urandom' "${start_sequence}" || true)"
  if [[ "${mdev_scan_count}" -gt 0 && "${entropy_repair_count}" -ge "${mdev_scan_count}" ]]; then
    pass "every startup mdev scan is paired with an entropy-device permission repair"
  else
    fail "startup mdev scans can reset entropy-device permissions"
  fi
fi

for device in random urandom; do
  if [[ -f "${mdev_config}" ]] && grep -Eq "^${device}[[:space:]]+0:0[[:space:]]+0666$" "${mdev_config}"; then
    pass "mdev policy keeps /dev/${device} world-readable"
  else
    fail "mdev policy does not preserve /dev/${device} permissions"
  fi
done

if [[ -s "${ca_bundle}" ]]; then
  pass "browser CA bundle is staged"
else
  fail "browser CA bundle is missing or empty"
fi

midori_wrapper="${AUZIX_ROOT}/Programs/Midori/current/Commands/midori"
if [[ -e "${AUZIX_ROOT}/Programs/Midori/current" || -L "${AUZIX_ROOT}/Programs/Midori/current" ]]; then
  midori_wrapper="${AUZIX_ROOT}/Programs/Midori/$(basename "$(readlink "${AUZIX_ROOT}/Programs/Midori/current")")/Commands/midori"
  midori_contract_patterns=(
    'SSL_CERT_FILE='
    'GCONV_PATH='
    'Resources/midori:/Programs/Midori/current/Libraries'
    'Midori profile directories are not writable'
  )
  for pattern in "${midori_contract_patterns[@]}"; do
    if [[ -f "${midori_wrapper}" ]] && grep -Fq "${pattern}" "${midori_wrapper}"; then
      pass "Midori runtime contract contains ${pattern}"
    else
      fail "Midori runtime contract is missing ${pattern}"
    fi
  done
  midori_program="$(dirname "$(dirname "${midori_wrapper}")")"
  if [[ -s "${midori_program}/Resources/midori/libnssckbi.so" ]]; then
    pass "Midori NSS trust module is staged"
  else
    fail "Midori NSS trust module is missing or empty"
  fi
else
  report "INFO: Midori is not staged; Midori-specific checks skipped"
fi

report ""
report "Installer contract"
installer_paths=(
  "/Programs/Lua/current/Commands/lua"
  "/Programs/Dialog/current/Commands/dialog"
  "/Programs/AuzixInstaller/current/Commands/auzix-installer"
  "/Programs/AuzixInstaller/current/Commands/auzix-installer-gui"
  "/System/Settings/installer/install-plan.schema.json"
  "/System/Settings/installer/questions.json"
  "/System/Settings/installer/plans/default.json"
  "/System/Tools/auzix-install-disk"
)
for path in "${installer_paths[@]}"; do
  case "${path}" in
    /Programs/*/current/*) full="$(resolve_program_current_path "${path}")" ;;
    *) full="$(resolve_root_path "${path}")" ;;
  esac
  if [[ -e "${full}" || -L "${full}" ]]; then
    pass "${path}"
  else
    fail "installer contract is missing ${path}"
  fi
done

installer_jq="$(resolve_program_current_path "/Programs/AuzixPackageTools/current/Commands/jq.real")"
if [[ -x "${installer_jq}" ]]; then
  if "${installer_jq}" -e '.format == "auzix-install-plan-v1"' \
    "${AUZIX_ROOT}/System/Settings/installer/plans/default.json" >/dev/null; then
    pass "default install plan uses auzix-install-plan-v1"
  else
    fail "default install plan format is invalid"
  fi
  if "${installer_jq}" -e '
    .format == "auzix-installer-questions-v1"
    and .plan_format == "auzix-install-plan-v1"
    and any(.questions[]; .id == "target_disk")
    and any(.questions[]; .id == "confirmed")
  ' "${AUZIX_ROOT}/System/Settings/installer/questions.json" >/dev/null; then
    pass "installer question contract covers target selection and destructive confirmation"
  else
    fail "installer question contract is invalid"
  fi
else
  fail "installer validation requires the packaged jq runtime"
fi

if "${ROOT_DIR}/scripts/test-auzix-installer.sh" "${AUZIX_ROOT}" >/dev/null 2>&1; then
  pass "installer validation and guarded execution tests"
else
  fail "installer validation or guarded execution tests failed"
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
