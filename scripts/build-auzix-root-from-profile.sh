#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${1:?usage: build-auzix-root-from-profile.sh PROFILE [TARGET_ROOT]}"
TARGET_ROOT="${2:-${ROOT_DIR}/out/auzix-install-root/AuzixRoot}"
ALLOW_PENDING="${AUZIX_ALLOW_PENDING_PROFILE_ITEMS:-0}"

log() {
  printf '[auzix-root-from-profile] %s\n' "$*" >&2
}

fail() {
  printf '[auzix-root-from-profile] FAIL: %s\n' "$*" >&2
  exit 1
}

run_step() {
  log "$*"
  "$@"
}

[[ -f "${PROFILE}" ]] || fail "profile not found: ${PROFILE}"
BASH_CMD="${BASH:-}"
if [[ -z "${BASH_CMD}" ]]; then
  for candidate in \
    /System/Compatibility/bin/bash \
    /Programs/Bash/current/Commands/bash \
    /usr/bin/bash \
    /bin/bash \
    bash; do
    if command -v "${candidate}" >/dev/null 2>&1 || [[ -x "${candidate}" ]]; then
      BASH_CMD="${candidate}"
      break
    fi
  done
fi
[[ -n "${BASH_CMD}" ]] || fail "bash is required for AUZiX root-profile builder scripts"

run_script() {
  local script="$1"
  shift
  run_step "${BASH_CMD}" "${script}" "$@"
}

if [[ "$(id -u)" != "0" && -z "${FAKEROOTKEY:-}" && "${AUZIX_ALLOW_UNPRIVILEGED_BUILD:-0}" != "1" ]]; then
  cat >&2 <<'EOF'
[auzix-root-from-profile] refusing unprivileged target-root build
[auzix-root-from-profile] Root assembly must preserve package ownership, setuid
[auzix-root-from-profile] bits, sticky dirs, and lifecycle state. Run in the
[auzix-root-from-profile] builder/root-capable lab path or a fakeroot session.
EOF
  exit 1
fi

build_package() {
  local item="$1"
  case "${item}" in
    BusyBox)
      run_script "${ROOT_DIR}/scripts/build-auzix-busybox-package.sh" "${TARGET_ROOT}"
      ;;
    AuzixPackageTools)
      run_script "${ROOT_DIR}/scripts/build-auzix-package-tools-package.sh" "${TARGET_ROOT}"
      ;;
    AuzixInstaller)
      run_script "${ROOT_DIR}/scripts/build-auzix-installer-package.sh" "${TARGET_ROOT}"
      ;;
    OpenSSH|Access|AuzixAccess)
      run_script "${ROOT_DIR}/scripts/build-auzix-access-package.sh" "${TARGET_ROOT}"
      ;;
    Sudo)
      run_script "${ROOT_DIR}/scripts/build-auzix-sudo-package.sh" "${TARGET_ROOT}"
      ;;
    CACerts|CaCertificates)
      run_script "${ROOT_DIR}/scripts/build-auzix-ca-certificates-package.sh" "${TARGET_ROOT}"
      ;;
    Curl)
      run_script "${ROOT_DIR}/scripts/build-auzix-curl-package.sh" "${TARGET_ROOT}"
      ;;
    Iproute2|IPUtils)
      run_script "${ROOT_DIR}/scripts/build-auzix-iputils-package.sh" "${TARGET_ROOT}"
      ;;
    E2fsprogs)
      run_script "${ROOT_DIR}/scripts/build-auzix-command-suite-package.sh" "${TARGET_ROOT}" "${ROOT_DIR}/packages/e2fsprogs.command-suite.json"
      ;;
    Dosfstools)
      run_script "${ROOT_DIR}/scripts/build-auzix-command-suite-package.sh" "${TARGET_ROOT}" "${ROOT_DIR}/packages/dosfstools.command-suite.json"
      ;;
    Parted)
      run_script "${ROOT_DIR}/scripts/build-auzix-command-suite-package.sh" "${TARGET_ROOT}" "${ROOT_DIR}/packages/parted.command-suite.json"
      ;;
    Strace)
      run_script "${ROOT_DIR}/scripts/build-auzix-strace-package.sh" "${TARGET_ROOT}"
      ;;
    AuzixServiceRuntime)
      run_script "${ROOT_DIR}/scripts/build-auzix-service-runtime-package.sh" "${TARGET_ROOT}"
      ;;
    UtilLinux|File)
      if [[ "${ALLOW_PENDING}" == "1" ]]; then
        log "PENDING ${item}: no first-class root-profile builder yet"
      else
        fail "${item} is in ${PROFILE} but has no first-class root-profile builder yet"
      fi
      ;;
    *)
      if [[ "${ALLOW_PENDING}" == "1" ]]; then
        log "PENDING ${item}: unknown root-profile item"
      else
        fail "unknown root-profile item: ${item}"
      fi
      ;;
  esac
}

rm -rf "${TARGET_ROOT}"
run_script "${ROOT_DIR}/scripts/scaffold-auzix-strict-root.sh" "${TARGET_ROOT}"

while IFS= read -r line || [[ -n "${line}" ]]; do
  line="${line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -n "${line}" ]] || continue
  build_package "${line}"
done <"${PROFILE}"

run_script "${ROOT_DIR}/scripts/add-auzix-live-tools.sh" "${TARGET_ROOT}"

mkdir -p "${TARGET_ROOT}/System/State/install"
cat >"${TARGET_ROOT}/System/State/install/root-build.txt" <<EOF
root_build_mode=package-built
profile=${PROFILE}
target_root=${TARGET_ROOT}
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

if [[ -x "${TARGET_ROOT}/System/Tools/finalize-installed-root" ]]; then
  run_step chroot "${TARGET_ROOT}" /System/Tools/finalize-installed-root /
fi

log "PASS target root built from profile: ${TARGET_ROOT}"
