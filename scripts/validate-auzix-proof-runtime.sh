#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT_INPUT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
AUZIX_ROOT="$(cd "${AUZIX_ROOT_INPUT}" 2>/dev/null && pwd || printf '%s\n' "${AUZIX_ROOT_INPUT}")"
REPORT_PATH="${2:-${ROOT_DIR}/out/auzix-strict/proof-runtime-validation.txt}"
ALIAS_POLICY="${AUZIX_PROOF_ALIAS_POLICY:-strict}"
PROFILE="${AUZIX_PROOF_PROFILE:-proof}"
CHROOT_BIN="${AUZIX_CHROOT_BIN:-$(command -v chroot || true)}"
CAN_CHROOT=1

failures=0
warnings=0

mkdir -p "$(dirname "${REPORT_PATH}")"
: > "${REPORT_PATH}"

report() {
  printf '%s\n' "$*" | tee -a "${REPORT_PATH}"
}

pass() {
  report "PASS: $*"
}

warn() {
  warnings=$((warnings + 1))
  report "WARN: $*"
}

fail() {
  failures=$((failures + 1))
  report "FAIL: $*"
}

root_path() {
  printf '%s%s\n' "${AUZIX_ROOT}" "$1"
}

path_exists() {
  [[ -e "$(root_path "$1")" || -L "$(root_path "$1")" ]]
}

resolve_current() {
  local auzix_path="$1"
  local current suffix target
  if [[ "${auzix_path}" == /Programs/*/current/* ]]; then
    current="${auzix_path%%/current/*}/current"
    suffix="${auzix_path#*/current/}"
    if [[ -L "$(root_path "${current}")" ]]; then
      target="$(readlink "$(root_path "${current}")")"
      case "${target}" in
        /*) printf '%s%s/%s\n' "${AUZIX_ROOT}" "${target}" "${suffix}" ;;
        *) printf '%s%s/%s\n' "${AUZIX_ROOT}" "${current%/current}/${target}" "${suffix}" ;;
      esac
      return
    fi
  fi
  root_path "${auzix_path}"
}

find_program_command() {
  local program="$1"
  local command="$2"
  local base
  for base in \
    "/Programs/${program}/current/Commands/${command}" \
    "/System/Compatibility/bin/${command}" \
    "/System/Compatibility/sbin/${command}"; do
    if [[ -x "$(resolve_current "${base}")" ]]; then
      printf '%s\n' "${base}"
      return 0
    fi
  done
  return 1
}

run_in_root() {
  local label="$1"
  shift
  local output status
  if [[ "${CAN_CHROOT}" != "1" ]]; then
    warn "${label} skipped because this host user cannot chroot; run inside the validation container or as root for the hard probe"
    return 0
  fi
  set +e
  output="$(env -i \
    AUZIX_ROOT="${AUZIX_ROOT}" \
    HOME=/Users/root \
    USER=root \
    LOGNAME=root \
    TERM=xterm-256color \
    TMPDIR=/Work/Temp \
    PATH=/System/Compatibility/bin:/System/Compatibility/sbin:/Programs/BusyBox/current/Commands:/Programs/NcursesBase/current/Commands:/Programs/NcursesBin/current/Commands:/Programs/Python313/current/Commands \
    TERMINFO_DIRS=/Programs/NcursesBase/current/RootFS/usr/share/terminfo:/Programs/NcursesTerm/current/RootFS/usr/share/terminfo:/Programs/KittyTerminfo/current/RootFS/usr/share/terminfo:/System/Compatibility/usr/share/terminfo:/System/Compatibility/lib/terminfo \
    "${CHROOT_BIN}" "${AUZIX_ROOT}" "$@" 2>&1)"
  status=$?
  set -e
  if [[ "${status}" -eq 0 ]]; then
    pass "${label}"
    [[ -n "${output}" ]] && report "${output}"
  else
    fail "${label}"
    [[ -n "${output}" ]] && report "${output}"
  fi
}

report "AUZiX proof runtime validation"
report "Root: ${AUZIX_ROOT}"
report "Report: ${REPORT_PATH}"
report "Alias policy: ${ALIAS_POLICY}"
report "Profile: ${PROFILE}"
report ""

if [[ ! -d "${AUZIX_ROOT}" ]]; then
  fail "AUZiX root is missing: ${AUZIX_ROOT}"
  report ""
  report "Summary: failures=${failures} warnings=${warnings}"
  exit 1
fi

if [[ -z "${CHROOT_BIN}" || ! -x "${CHROOT_BIN}" ]]; then
  fail "host chroot command not found; set AUZIX_CHROOT_BIN"
elif [[ "$(id -u)" != "0" ]]; then
  CAN_CHROOT=0
  warn "not running as root; command probes that need chroot will be skipped locally"
fi

report "Top-level contract"
for dir in /System /Programs /Services /Stacks /Work /Users /Volumes /Network /dev /proc /sys /run; do
  if [[ -d "$(root_path "${dir}")" && ! -L "$(root_path "${dir}")" ]]; then
    pass "${dir} is a real directory"
  else
    fail "${dir} is missing or not a real directory"
  fi
done

report ""
report "Strict-root alias contract"
legacy_paths=(/bin /sbin /lib /lib64 /usr /var /tmp /home /root /opt)
case "${ALIAS_POLICY}" in
  strict)
    for legacy in "${legacy_paths[@]}"; do
      if path_exists "${legacy}"; then
        fail "${legacy} exists while strict proof expects no root-level legacy alias"
      else
        pass "${legacy} absent"
      fi
    done
    ;;
  compat)
    for legacy in "${legacy_paths[@]}"; do
      if [[ -L "$(root_path "${legacy}")" ]]; then
        pass "${legacy} compatibility link exists"
      else
        fail "${legacy} compatibility link missing"
      fi
    done
    ;;
  *)
    fail "unknown AUZIX_PROOF_ALIAS_POLICY=${ALIAS_POLICY}"
    ;;
esac

report ""
report "Core runtime files"
for lib in \
  /System/Libraries/ld-linux-x86-64.so.2 \
  /System/Libraries/libc.so.6 \
  /System/Libraries/libgcc_s.so.1; do
  if [[ -e "$(root_path "${lib}")" || -L "$(root_path "${lib}")" ]]; then
    pass "${lib}"
  else
    fail "missing core runtime file ${lib}"
  fi
done

if [[ -d "$(root_path /Work/Temp)" ]]; then
  pass "/Work/Temp exists for TMPDIR"
else
  fail "/Work/Temp missing; strict mode cannot depend on /tmp"
fi

report ""
report "Identity and user-mode contract"
if [[ -f "$(root_path /System/Settings/passwd)" ]] && grep -Fq 'auzix:x:1000:1000:' "$(root_path /System/Settings/passwd)"; then
  pass "auzix uid 1000 present"
else
  fail "auzix uid 1000 missing from /System/Settings/passwd"
fi
if [[ -d "$(root_path /Users/auzix)" ]]; then
  owner="$(stat -c '%u:%g' "$(root_path /Users/auzix)" 2>/dev/null || true)"
  if [[ "${owner}" == "1000:1000" ]]; then
    pass "/Users/auzix owned by 1000:1000"
  else
    fail "/Users/auzix ownership is ${owner:-unknown}, expected 1000:1000"
  fi
else
  fail "/Users/auzix missing"
fi

report ""
report "Command/front-door probes"
if busybox_cmd="$(find_program_command BusyBox busybox)"; then
  run_in_root "BusyBox front door works" "${busybox_cmd}" true
else
  fail "BusyBox command not found"
fi

if curl_cmd="$(find_program_command Curl curl)"; then
  run_in_root "Curl front door reports version" "${curl_cmd}" --version
else
  warn "Curl not present in this profile"
fi

if nginx_cmd="$(find_program_command Nginx nginx)"; then
  run_in_root "Nginx front door parses version/config" "${nginx_cmd}" -v
else
  warn "Nginx not present in this profile"
fi

report ""
report "Terminfo/curses probes"
if [[ -e "$(root_path /Programs/NcursesBase/current/RootFS/usr/share/terminfo/x/xterm-256color)" || \
      -e "$(root_path /Programs/NcursesTerm/current/RootFS/usr/share/terminfo/x/xterm-256color)" || \
      -e "$(root_path /Programs/KittyTerminfo/current/RootFS/usr/share/terminfo/x/xterm-256color)" ]]; then
  pass "xterm-256color terminfo exists in AUZiX runtime ladder"
else
  fail "xterm-256color terminfo missing from AUZiX runtime ladder"
fi

if htop_cmd="$(find_program_command Htop htop)"; then
  run_in_root "Htop curses front door reports version" "${htop_cmd}" --version
else
  warn "Htop not present in this profile"
fi

if nano_cmd="$(find_program_command Nano nano)"; then
  run_in_root "Nano curses front door reports version" "${nano_cmd}" --version
else
  warn "Nano not present in this profile"
fi

report ""
report "Python-script runtime probes"
if py_cmd="$(find_program_command Python313 python3.13 || true)"; [[ -n "${py_cmd:-}" ]]; then
  run_in_root "Python can import encodings/resource" "${py_cmd}" -c 'import encodings, resource; print("python-runtime-ok")'
else
  warn "Python313 not present in this profile"
fi

if glances_cmd="$(find_program_command Glances glances || true)"; [[ -n "${glances_cmd:-}" ]]; then
  run_in_root "Glances front door reports version" "${glances_cmd}" --version
else
  warn "Glances not present in this profile"
fi

report ""
report "Wrapper and dependency ladder checks"
if [[ -d "$(root_path /System/PackageDB)" ]]; then
  missing_runtime_receipts=0
  while IFS= read -r receipt; do
    package_name="$(jq -r '.name // empty' "${receipt}" 2>/dev/null || true)"
    while IFS= read -r dep; do
      [[ -n "${dep}" ]] || continue
      if ! find "$(root_path /System/PackageDB)" -maxdepth 1 -type f -name "${dep}-*.auzix.json" -print -quit 2>/dev/null | grep -q .; then
        report "MISSING-DEP: ${package_name}: ${dep}"
        missing_runtime_receipts=$((missing_runtime_receipts + 1))
      fi
    done < <(jq -r '.runtime_packages[]?, .depends[]?' "${receipt}" 2>/dev/null | sort -u)
  done < <(find "$(root_path /System/PackageDB)" -maxdepth 1 -type f -name '*.auzix.json' | sort)
  if [[ "${missing_runtime_receipts}" -eq 0 ]]; then
    pass "all declared dependency/runtime package receipts are present"
  else
    fail "${missing_runtime_receipts} declared dependency/runtime package receipts missing"
  fi
else
  fail "/System/PackageDB missing"
fi

if ldd_cmd="$(find_program_command Ldd ldd || find_program_command Ldd auzix-ldd || true)"; [[ -n "${ldd_cmd:-}" ]]; then
  if abiword_cmd="$(find_program_command AbiWord abiword || true)"; [[ -n "${abiword_cmd:-}" ]]; then
    run_in_root "AbiWord wrapper-aware ldd resolves without not-found" "${ldd_cmd}" "${abiword_cmd}"
  else
    warn "AbiWord not present for wrapper-aware ldd probe"
  fi
else
  warn "AUZiX ldd/debug probe not present; add debug-runtime/admin-observe before promotion"
fi

report ""
report "Summary: failures=${failures} warnings=${warnings}"
if [[ "${failures}" -gt 0 ]]; then
  exit 1
fi
