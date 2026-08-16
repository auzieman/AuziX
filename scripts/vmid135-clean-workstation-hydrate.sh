#!/usr/bin/env bash
set -euo pipefail

# Hydrate vmid135 from the installed-root SSH shell using explicit package
# tiers. This is not a GUI repair script; it is a package transaction runner
# that records what happened and stops on important gates.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${TARGET:-root@192.168.1.198}"
REPO="${REPO:-http://192.168.1.10/auzix/repo}"
PROFILE="${PROFILE:-profiles/packages/auzix-vmid135-clean-workstation.packages}"
TARGET_ROOT="${TARGET_ROOT:-/}"
TARGET_DEVICE="${TARGET_DEVICE:-}"
REMOTE_PROFILE="/System/Settings/install/auzix-vmid135-clean-workstation.packages"
REMOTE_RUNNER="/System/Tools/hydrate-clean-workstation"
REMOTE_ACTIVATE="/System/Tools/activate-auzix-basic-config"
REMOTE_STAGE="/Work/Temp/auzix-clean-workstation-stage"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

if [[ ! -f "${PROFILE}" ]]; then
  echo "profile not found: ${PROFILE}" >&2
  exit 2
fi

ssh "${SSH_OPTS[@]}" "${TARGET}" "BB=/Programs/BusyBox/current/Commands/busybox; [ -x \"\${BB}\" ] || BB=/Programs/BusyBox/1.36.1/Commands/busybox; \"\${BB}\" mkdir -p '${REMOTE_STAGE}'"
scp -q "${PROFILE}" "${TARGET}:${REMOTE_STAGE}/profile.packages"
scp -q "${ROOT_DIR}/scripts/activate-auzix-basic-config.sh" "${TARGET}:${REMOTE_STAGE}/activate-auzix-basic-config"

ssh "${SSH_OPTS[@]}" "${TARGET}" "BB=/Programs/BusyBox/current/Commands/busybox; [ -x \"\${BB}\" ] || BB=/Programs/BusyBox/1.36.1/Commands/busybox; \"\${BB}\" cat > '${REMOTE_STAGE}/hydrate-clean-workstation'" <<'REMOTE_SCRIPT'
#!/System/Compatibility/bin/sh
set -eu

BB=/Programs/BusyBox/current/Commands/busybox
[ -x "${BB}" ] || BB=/Programs/BusyBox/1.36.1/Commands/busybox
PKG=/System/Tools/auzix-pkg
[ -x "${PKG}" ] || PKG=/System/Compatibility/bin/auzix-pkg

PROFILE=/System/Settings/install/auzix-vmid135-clean-workstation.packages
REPO_URL="${1:-http://192.168.1.10/auzix/repo}"
MODE="${2:-full}"
UNTIL_SECTION="${3:-}"
RUN_GENERIC_ACTIVATION="${RUN_GENERIC_ACTIVATION:-0}"
LOG_DIR=/System/Logs/install
RECEIPT_DIR=/System/State/install/receipts
STAMP="$("${BB}" date -u +%Y%m%dT%H%M%SZ 2>/dev/null || "${BB}" date +%s)"
LOG="${LOG_DIR}/vmid135-clean-workstation-${STAMP}.log"
RECEIPT="${RECEIPT_DIR}/vmid135-clean-workstation-${STAMP}.txt"

"${BB}" mkdir -p "${LOG_DIR}" "${RECEIPT_DIR}" /Work/Temp 2>/dev/null || true

log() {
  echo "$*"
  echo "$*" >>"${LOG}" 2>/dev/null || true
}

fail() {
  log "FATAL $*"
  exit 1
}

run() {
  log "+ $*"
  "$@" >>"${LOG}" 2>&1
}

resolve_cmd() {
  for p in "$@"; do
    [ -x "${p}" ] && { echo "${p}"; return 0; }
  done
  return 1
}

install_pkg() {
  pkg="$1"
  [ -n "${pkg}" ] || return 0
  log "PACKAGE ${pkg}"
  if "${PKG}" status "${pkg}" 2>/dev/null | "${BB}" grep -q '"state": "installed"'; then
    log "SKIP installed ${pkg}"
    return 0
  fi
  run "${PKG}" install "${pkg}"
}

run_hook_if_present() {
  hook="$1"
  if [ -x "${hook}" ]; then
    run "${hook}"
  else
    log "SKIP missing hook ${hook}"
  fi
}

run_activation_pass() {
  log "LIFECYCLE activation-pass"
  if [ "${RUN_GENERIC_ACTIVATION}" != "1" ]; then
    log "SKIP generic activation pass; using package hooks plus generated-state triggers"
    return 0
  fi
  if [ -x /System/Tools/activate-auzix-basic-config ]; then
    AUZIX_REFRESH_DESKTOP_DEFAULTS="${AUZIX_REFRESH_DESKTOP_DEFAULTS:-0}" \
      run /System/Tools/activate-auzix-basic-config
  else
    log "SKIP missing /System/Tools/activate-auzix-basic-config"
  fi
}

refresh_generated_state() {
  log "GENERATED_STATE refresh"
  cmd="$(resolve_cmd /Programs/SharedMimeInfo/current/Commands/update-mime-database /System/Compatibility/bin/update-mime-database /System/Compatibility/usr/bin/update-mime-database || true)"
  [ -n "${cmd}" ] && run "${cmd}" /System/Compatibility/usr/share/mime || true

  cmd="$(resolve_cmd /Programs/DesktopFileUtils/current/Commands/update-desktop-database /System/Compatibility/bin/update-desktop-database /System/Compatibility/usr/bin/update-desktop-database || true)"
  [ -n "${cmd}" ] && run "${cmd}" /System/Compatibility/usr/share/applications || true

  cmd="$(resolve_cmd /Programs/Libglib20Bin/current/Commands/glib-compile-schemas /System/Compatibility/bin/glib-compile-schemas /System/Compatibility/usr/bin/glib-compile-schemas || true)"
  [ -n "${cmd}" ] && [ -d /System/Compatibility/usr/share/glib-2.0/schemas ] && run "${cmd}" /System/Compatibility/usr/share/glib-2.0/schemas || true

  cmd="$(resolve_cmd /Programs/GTKUpdateIconCache/current/Commands/gtk-update-icon-cache /System/Compatibility/bin/gtk-update-icon-cache /System/Compatibility/usr/bin/gtk-update-icon-cache || true)"
  [ -n "${cmd}" ] && [ -d /System/Compatibility/usr/share/icons/hicolor ] && run "${cmd}" -f -t /System/Compatibility/usr/share/icons/hicolor || true
}

write_identity_minimal() {
  log "IDENTITY minimal"
  echo auzix >/System/Settings/hostname 2>/dev/null || true
  "${BB}" hostname auzix 2>/dev/null || true
  # Keep root traversal boring for LightDM/DBus/session users.
  for p in / /System /System/Settings /System/Compatibility /Programs /Services /Users /Work; do
    [ -e "$p" ] && "${BB}" chmod 0755 "$p" 2>/dev/null || true
  done
}

has_ext4_tooling() {
  for p in \
    /Programs/E2fsprogs/current/Commands/mkfs.ext4 \
    /Programs/E2fsprogs/current/Commands/mke2fs \
    /Programs/E2fsprogs/current/RootFS/usr/sbin/mkfs.ext4 \
    /Programs/E2fsprogs/current/RootFS/usr/sbin/mke2fs \
    /Programs/E2fsprogs/current/RootFS/sbin/mkfs.ext4 \
    /Programs/E2fsprogs/current/RootFS/sbin/mke2fs \
    /System/Compatibility/sbin/mkfs.ext4 \
    /System/Compatibility/sbin/mke2fs \
    /System/Compatibility/usr/sbin/mkfs.ext4 \
    /System/Compatibility/usr/sbin/mke2fs; do
    [ -x "${p}" ] && { log "PRESENT ext4-tool ${p}"; return 0; }
  done
  return 1
}

preflight_ext4() {
  log "PREFLIGHT ext4"
  if has_ext4_tooling; then
    log "PASS ext4 tooling present"
    return 0
  fi
  install_pkg E2fsprogs
  if has_ext4_tooling; then
    log "PASS ext4 tooling installed"
    return 0
  fi
  "${PKG}" files E2fsprogs >>"${LOG}" 2>&1 || true
  fail "ext4 tooling unavailable after E2fsprogs install; package export/current link needs repair before clean install"
}

install_profile() {
  current_section=
  previous_section=
  while IFS= read -r line || [ -n "${line}" ]; do
    case "${line}" in
      ''|'#'*) continue ;;
      '['*']')
        if [ -n "${current_section}" ]; then
          run_activation_pass
          case "${current_section}" in
            desktop-generated-state)
              refresh_generated_state
              ;;
          esac
          validate_section "${current_section}"
          if [ -n "${UNTIL_SECTION}" ] && [ "${current_section}" = "${UNTIL_SECTION}" ]; then
            log "DONE until-section ${UNTIL_SECTION}"
            return 0
          fi
        fi
        previous_section="${current_section}"
        current_section="${line#[}"
        current_section="${current_section%]}"
        log "SECTION ${current_section}"
        ;;
      *)
        install_pkg "${line}"
        case "${line}" in
          AuzixServiceRuntime)
            run_hook_if_present /Programs/AuzixServiceRuntime/current/Commands/ensure-runtime-mounts
            ;;
          AuzixDesktopIntegration)
            run_hook_if_present /Programs/AuzixDesktopIntegration/current/Commands/activate
            run_hook_if_present /Programs/AuzixDesktopIntegration/current/Commands/e-launcher-sync
            ;;
        esac
        ;;
    esac
  done <"${PROFILE}"
  if [ -n "${current_section}" ]; then
    run_activation_pass
    case "${current_section}" in
      desktop-generated-state)
        refresh_generated_state
        ;;
    esac
    validate_section "${current_section}"
  fi
}

section_packages() {
  wanted="$1"
  in_section=0
  while IFS= read -r line || [ -n "${line}" ]; do
    case "${line}" in
      ''|'#'*) continue ;;
      '['*']')
        section="${line#[}"
        section="${section%]}"
        [ "${section}" = "${wanted}" ] && in_section=1 || in_section=0
        ;;
      *)
        [ "${in_section}" = 1 ] && echo "${line}"
        ;;
    esac
  done <"${PROFILE}"
}

validate_package_surface() {
  pkg="$1"
  log "VALIDATE package ${pkg}"
  if ! "${PKG}" status "${pkg}" 2>/dev/null | "${BB}" grep -q '"state": "installed"'; then
    log "FAIL package-not-installed ${pkg}"
    return 1
  fi
  "${PKG}" status "${pkg}" 2>/dev/null |
    "${BB}" awk '
      /"\\/Programs\\// || /"\\/System\\/Compatibility\\// || /"\\/etc\\// || /"\\/Users\\// {
        gsub(/[",]/, "", $0)
        gsub(/^[ \t]+/, "", $0)
        print $0
      }
    ' |
    while IFS= read -r path; do
      case "${path}" in
        /*)
          if [ -e "${path}" ] || [ -L "${path}" ]; then
            log "PRESENT ${path}"
          else
            log "MISSING ${pkg} ${path}"
          fi
          ;;
      esac
    done || true
}

validate_root_permissions() {
  log "VALIDATE root-permissions"
  for p in / /System /System/Settings /System/Compatibility /Programs /Services /Users /Work /run /run/dbus /run/user; do
    if [ -e "${p}" ]; then
      mode="$("${BB}" stat -c '%a' "${p}" 2>/dev/null || echo unknown)"
      owner="$("${BB}" stat -c '%U:%G' "${p}" 2>/dev/null || echo unknown)"
      log "STAT ${p} ${owner} ${mode}"
    else
      log "MISSING dir ${p}"
    fi
  done
}

validate_section() {
  section="$1"
  log "VALIDATE section ${section}"
  validate_root_permissions
  section_packages "${section}" | while IFS= read -r pkg; do
    validate_package_surface "${pkg}" || true
  done
  case "${section}" in
    installer-preflight)
      has_ext4_tooling || fail "section ${section}: ext4 tooling missing"
      ;;
    base-runtime)
      [ -d /run ] || fail "section ${section}: /run missing"
      [ -d /run/dbus ] || fail "section ${section}: /run/dbus missing"
      ;;
    desktop-session|desktop-generated-state)
      [ -e /etc/xdg/menus/e-applications.menu ] || log "MISSING desktop-menu /etc/xdg/menus/e-applications.menu"
      [ -d /System/Compatibility/usr/share/applications ] || log "MISSING applications-dir"
      [ -d /System/Compatibility/usr/share/desktop-directories ] || log "MISSING desktop-directories-dir"
      ;;
    container-host)
      if [ -x /Programs/Podman/current/Commands/podman ]; then
        /Programs/Podman/current/Commands/podman --version >>"${LOG}" 2>&1 || log "WARN podman --version failed"
      fi
      ;;
  esac
}

validate_minimal() {
  log "VALIDATE minimal"
  for p in \
    /Programs/E2fsprogs/current/Commands/mkfs.ext4 \
    /Programs/E2fsprogs/current/Commands/mke2fs \
    /Programs/AuzixServiceRuntime/current/Commands/ensure-runtime-mounts \
    /Programs/DBUSX11/current/Commands/dbus-launch \
    /Programs/LibefreetBin/current/Commands/efreetd \
    /Programs/AuzixDesktopIntegration/current/Commands/activate \
    /System/Compatibility/usr/share/applications \
    /System/Compatibility/usr/share/desktop-directories \
    /etc/xdg/menus/e-applications.menu; do
    if [ -e "${p}" ]; then log "PRESENT ${p}"; else log "MISSING ${p}"; fi
  done
  "${PKG}" list installed >>"${LOG}" 2>&1 || true
}

: >"${LOG}"
log "AUZiX vmid135 clean workstation hydration ${STAMP}"
log "repo=${REPO_URL}"
log "profile=${PROFILE}"
log "mode=${MODE}"
log "until_section=${UNTIL_SECTION}"
log "run_generic_activation=${RUN_GENERIC_ACTIVATION}"

run "${PKG}" refresh "${REPO_URL}"
write_identity_minimal
preflight_ext4
if [ "${MODE}" = "preflight-only" ]; then
  validate_minimal
  log "DONE preflight-only"
  exit 0
fi
install_profile
refresh_generated_state
validate_minimal

{
  echo "log=${LOG}"
  echo "profile=${PROFILE}"
  echo "repo=${REPO_URL}"
  echo "completed=${STAMP}"
} >"${RECEIPT}"
log "RECEIPT ${RECEIPT}"
REMOTE_SCRIPT

MODE="${MODE:-full}"
UNTIL_SECTION="${UNTIL_SECTION:-}"
ssh "${SSH_OPTS[@]}" "${TARGET}" "
set -eu
BB=/Programs/BusyBox/current/Commands/busybox
[ -x \"\${BB}\" ] || BB=/Programs/BusyBox/1.36.1/Commands/busybox
TARGET_ROOT='${TARGET_ROOT}'
TARGET_DEVICE='${TARGET_DEVICE}'
[ -n \"\${TARGET_ROOT}\" ] || TARGET_ROOT=/
case \"\${TARGET_ROOT}\" in
  /) ;;
  /*) ;;
  *) echo \"TARGET_ROOT must be absolute: \${TARGET_ROOT}\" >&2; exit 2 ;;
esac
if [ \"\${TARGET_ROOT}\" != / ]; then
  \"\${BB}\" mkdir -p \"\${TARGET_ROOT}\"
  if ! \"\${BB}\" mountpoint -q \"\${TARGET_ROOT}\" 2>/dev/null; then
    [ -n \"\${TARGET_DEVICE}\" ] || { echo \"TARGET_DEVICE required when TARGET_ROOT is not mounted\" >&2; exit 2; }
    \"\${BB}\" mount \"\${TARGET_DEVICE}\" \"\${TARGET_ROOT}\"
  fi
  for mp in proc sys dev run; do
    \"\${BB}\" mkdir -p \"\${TARGET_ROOT}/\${mp}\"
    if ! \"\${BB}\" mountpoint -q \"\${TARGET_ROOT}/\${mp}\" 2>/dev/null; then
      case \"\${mp}\" in
        proc) \"\${BB}\" mount -t proc proc \"\${TARGET_ROOT}/proc\" ;;
        sys) \"\${BB}\" mount -t sysfs sysfs \"\${TARGET_ROOT}/sys\" ;;
        dev) \"\${BB}\" mount --bind /dev \"\${TARGET_ROOT}/dev\" ;;
        run) \"\${BB}\" mount --bind /run \"\${TARGET_ROOT}/run\" ;;
      esac
    fi
  done
fi
\"\${BB}\" mkdir -p \"\${TARGET_ROOT}/System/Settings/install\" \"\${TARGET_ROOT}/System/State/install/receipts\" \"\${TARGET_ROOT}/System/Logs/install\" \"\${TARGET_ROOT}/System/Tools\"
\"\${BB}\" cp '${REMOTE_STAGE}/profile.packages' \"\${TARGET_ROOT}${REMOTE_PROFILE}\"
\"\${BB}\" cp '${REMOTE_STAGE}/activate-auzix-basic-config' \"\${TARGET_ROOT}${REMOTE_ACTIVATE}\"
\"\${BB}\" cp '${REMOTE_STAGE}/hydrate-clean-workstation' \"\${TARGET_ROOT}${REMOTE_RUNNER}\"
\"\${BB}\" chmod 0755 \"\${TARGET_ROOT}${REMOTE_RUNNER}\" \"\${TARGET_ROOT}${REMOTE_ACTIVATE}\"
if [ \"\${TARGET_ROOT}\" = / ]; then
  '${REMOTE_RUNNER}' '${REPO}' '${MODE}' '${UNTIL_SECTION}'
else
  \"\${BB}\" chroot \"\${TARGET_ROOT}\" '${REMOTE_RUNNER}' '${REPO}' '${MODE}' '${UNTIL_SECTION}'
fi
"
