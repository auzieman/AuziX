#!/System/Compatibility/bin/sh
# Guard rails for the normal AUZiX disk installer.
#
# This script is intentionally not a second installer.  It verifies the live
# environment, optionally calls /System/Tools/auzix-install-disk, then checks the
# installed root while it is still mounted at /Work/InstallTarget.
#
# Safe/default mode:
#   auzix-existing-installer-preflight.sh /dev/vda
#
# Destructive install mode:
#   RUN_INSTALL=1 auzix-existing-installer-preflight.sh /dev/vda
#
# GRUB can still be bypassed while bootloader work is evolving:
#   RUN_INSTALL=1 BOOTLOADER=iso auzix-existing-installer-preflight.sh /dev/vda

set -eu

PATH=/System/Compatibility/bin:/System/Compatibility/sbin:/System/Compatibility/usr/bin:/System/Compatibility/usr/sbin:/Programs/BusyBox/current/Commands:/Programs/BusyBox/1.36.1/Commands:${PATH:-}
export PATH

BB="${BB:-}"
if [ -z "${BB}" ]; then
  for candidate in \
    /Programs/BusyBox/current/Commands/busybox \
    /Programs/BusyBox/1.36.1/Commands/busybox \
    /System/Compatibility/bin/busybox \
    busybox; do
    if command -v "${candidate}" >/dev/null 2>&1 || [ -x "${candidate}" ]; then
      BB="${candidate}"
      break
    fi
  done
fi

if [ -z "${BB}" ]; then
  echo "FAIL: busybox not found" >&2
  exit 1
fi

TARGET="${1:-/dev/vda}"
BOOTLOADER="${BOOTLOADER:-grub}"
RUN_INSTALL="${RUN_INSTALL:-0}"
REPO_URL="${REPO_URL:-https://auzix-repo.test:8443}"
INSTALLER="${INSTALLER:-/System/Tools/auzix-install-disk}"
TARGET_ROOT="${TARGET_ROOT:-/Work/InstallTarget}"

pass() { echo "PASS: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "FAIL: $*" >&2; exit 1; }

find_cmd() {
  for cmd in "$@"; do
    [ -x "${cmd}" ] && {
      printf '%s\n' "${cmd}"
      return 0
    }
    command -v "${cmd}" >/dev/null 2>&1 && {
      command -v "${cmd}"
      return 0
    }
  done
  return 1
}

is_mounted() {
  "${BB}" grep -q " $1 " /proc/mounts 2>/dev/null
}

check_live_preflight() {
  echo "== AUZiX live installer preflight =="
  [ -x "${INSTALLER}" ] || fail "installer missing or not executable: ${INSTALLER}"
  pass "installer exists: ${INSTALLER}"

  [ -b "${TARGET}" ] || fail "target block device missing: ${TARGET}"
  pass "target block device exists: ${TARGET}"

  mkfs_ext4="$(find_cmd \
    /Programs/E2fsprogs/current/Commands/mkfs.ext4 \
    /Programs/E2fsprogs/current/Commands/mke2fs \
    /System/Compatibility/usr/sbin/mkfs.ext4 \
    /System/Compatibility/sbin/mkfs.ext4 \
    /System/Compatibility/usr/sbin/mke2fs \
    /System/Compatibility/sbin/mke2fs \
    mkfs.ext4 \
    mke2fs || true)"
  [ -n "${mkfs_ext4}" ] || fail "ext4 tooling missing; install E2fsprogs before disk install"
  pass "ext4 tooling found: ${mkfs_ext4}"

  if [ -n "${AUZIX_INSTALL_PLAN:-}" ] && [ -s "${AUZIX_INSTALL_PLAN}" ] && command -v jq >/dev/null 2>&1; then
    layout="$(jq -r '.storage.layout // "whole"' "${AUZIX_INSTALL_PLAN}" 2>/dev/null || echo whole)"
    if [ "${layout}" = "user-work-programs" ]; then
      parted_cmd="$(find_cmd \
        /Programs/Parted/current/Commands/parted \
        /System/Compatibility/usr/sbin/parted \
        /System/Compatibility/sbin/parted \
        parted || true)"
      [ -n "${parted_cmd}" ] || fail "default split layout requires Parted"
      pass "split layout partitioner found: ${parted_cmd}"
    fi
  fi

  img="/Work/Temp/auzix-ext4-preflight-$$.img"
  "${BB}" mkdir -p /Work/Temp
  trap '"${BB}" rm -f "${img}"' EXIT
  "${BB}" truncate -s 8M "${img}" 2>/dev/null || "${BB}" dd if=/dev/zero of="${img}" bs=1M count=8 >/dev/null 2>&1
  case "$("${BB}" basename "${mkfs_ext4}")" in
    mke2fs) "${mkfs_ext4}" -F -t ext4 -L AUZIXTEST "${img}" >/dev/null ;;
    *) "${mkfs_ext4}" -F -L AUZIXTEST "${img}" >/dev/null ;;
  esac
  pass "ext4 scratch format smoke passed"

  if command -v auzix-pkg >/dev/null 2>&1; then
    auzix-pkg refresh "${REPO_URL}" >/dev/null 2>&1 && pass "repo refresh passed: ${REPO_URL}" || warn "repo refresh failed: ${REPO_URL}"
  else
    warn "auzix-pkg not in PATH during preflight"
  fi

  for cmd in ip sshd; do
    if find_cmd "${cmd}" >/dev/null 2>&1; then
      pass "${cmd} available"
    else
      warn "${cmd} not found; recovery/network proof may be weaker"
    fi
  done
}

run_existing_installer() {
  [ "${RUN_INSTALL}" = "1" ] || {
    echo "RUN_INSTALL is not 1; preflight only. Existing installer not invoked."
    return 0
  }
  echo "== Running existing AUZiX installer =="
  "${INSTALLER}" --force --bootloader "${BOOTLOADER}" "${TARGET}"
}

check_installed_root() {
  echo "== AUZiX installed-root sanity =="
  if ! is_mounted "${TARGET_ROOT}"; then
    warn "${TARGET_ROOT} is not mounted; post-install checks skipped"
    return 0
  fi

  [ -x "${TARGET_ROOT}/init" ] || fail "installed root lacks executable /init"
  pass "installed /init executable"

  [ -f "${TARGET_ROOT}/System/Boot/InstalledInit" ] || fail "InstalledInit missing"
  pass "InstalledInit exists"

  [ -f "${TARGET_ROOT}/System/Settings/fstab" ] || fail "fstab missing"
  if "${BB}" grep -q 'LABEL=AUZIXROOT / ext4 ' "${TARGET_ROOT}/System/Settings/fstab"; then
    pass "fstab uses ext4 root"
  else
    fail "fstab does not declare normal ext4 AUZIXROOT"
  fi

  [ -x "${TARGET_ROOT}/System/Tools/finalize-installed-root" ] || fail "finalize-installed-root missing"
  pass "finalizer present"

  [ -d "${TARGET_ROOT}/System/PackageDB" ] || fail "PackageDB missing"
  pass "PackageDB present"

  poison_symlink="$(
    "${BB}" find "${TARGET_ROOT}" -xdev -type l -print 2>/dev/null | while IFS= read -r link_path; do
      link_target="$("${BB}" readlink "${link_path}" 2>/dev/null || true)"
      case "${link_target}" in
        "${TARGET_ROOT}"/*)
          printf '%s -> %s\n' "${link_path}" "${link_target}"
          break
          ;;
      esac
    done
  )"
  [ -z "${poison_symlink}" ] || fail "installed root has mount-prefixed symlink: ${poison_symlink}"
  pass "installed root symlinks are root-internal"

  sh_link="$("${BB}" readlink "${TARGET_ROOT}/System/Compatibility/bin/sh" 2>/dev/null || true)"
  case "${sh_link}" in
    /Programs/*|/System/*)
      pass "installed shell link is root-internal: ${sh_link}"
      ;;
    *)
      fail "installed shell link is not root-internal: ${sh_link:-missing}"
      ;;
  esac

  for group in auzix lightdm input video audio render tty users; do
    if "${BB}" grep -q "^${group}:" "${TARGET_ROOT}/System/Settings/group" 2>/dev/null || \
       "${BB}" grep -q "^${group}:" "${TARGET_ROOT}/etc/group" 2>/dev/null; then
      pass "group present: ${group}"
    else
      warn "group missing: ${group}"
    fi
  done

  for user in auzix lightdm; do
    if "${BB}" grep -q "^${user}:" "${TARGET_ROOT}/System/Settings/passwd" 2>/dev/null || \
       "${BB}" grep -q "^${user}:" "${TARGET_ROOT}/etc/passwd" 2>/dev/null; then
      pass "user present: ${user}"
    else
      warn "user missing: ${user}"
    fi
  done

  for surface in \
    System/Settings/fstab \
    System/Settings/install/boot-note.txt \
    System/State/install/installed-at.txt; do
    [ -e "${TARGET_ROOT}/${surface}" ] && pass "surface present: /${surface}" || warn "surface missing: /${surface}"
  done
}

check_live_preflight
run_existing_installer
check_installed_root

echo "AUZiX installer guard completed."
