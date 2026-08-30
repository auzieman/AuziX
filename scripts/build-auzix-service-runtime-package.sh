#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
VERSION="${AUZIX_SERVICE_RUNTIME_VERSION:-0.1.0}"
PROGRAM="${AUZIX_ROOT}/Programs/AuzixServiceRuntime/${VERSION}"
PACKAGE_DB="${AUZIX_ROOT}/System/PackageDB"
SERVICE="${AUZIX_ROOT}/Services/runtime-mounts"

mkdir -p "${PROGRAM}/Commands" "${PACKAGE_DB}" "${SERVICE}"
rm -f "${PACKAGE_DB}"/AuzixServiceRuntime-*.auzix.json

cat >"${PROGRAM}/Commands/ensure-runtime-mounts" <<'SCRIPT'
#!/Programs/BusyBox/current/Commands/busybox sh
set -eu

BB="/Programs/BusyBox/current/Commands/busybox"
ROOT="${1:-/}"
ROOT="${ROOT%/}"
[ -n "${ROOT}" ] || ROOT="/"

at_root() {
  if [ "${ROOT}" = "/" ]; then
    printf '%s\n' "$1"
  else
    printf '%s%s\n' "${ROOT}" "$1"
  fi
}

is_mounted() {
  mount_path="$1"
  [ -r /proc/mounts ] || return 1
  "${BB}" grep -q " ${mount_path} " /proc/mounts 2>/dev/null
}

mount_if_needed() {
  target="$1"
  type="$2"
  source="$3"
  options="${4:-}"
  "${BB}" mkdir -p "${target}" 2>/dev/null || true
  is_mounted "${target}" && return 0
  if [ -n "${options}" ]; then
    "${BB}" mount -t "${type}" -o "${options}" "${source}" "${target}" 2>/dev/null && return 0
  else
    "${BB}" mount -t "${type}" "${source}" "${target}" 2>/dev/null && return 0
  fi
  return 1
}

proc_path="$(at_root /proc)"
sys_path="$(at_root /sys)"
dev_path="$(at_root /dev)"
run_path="$(at_root /run)"
cgroup_path="$(at_root /sys/fs/cgroup)"
devpts_path="$(at_root /dev/pts)"
devshm_path="$(at_root /dev/shm)"

"${BB}" mkdir -p "${proc_path}" "${sys_path}" "${dev_path}" "${run_path}" \
  "${cgroup_path}" "${devpts_path}" "${devshm_path}"

mount_if_needed "${proc_path}" proc proc || echo "AuzixServiceRuntime: proc mount unavailable: ${proc_path}" >&2
mount_if_needed "${sys_path}" sysfs sysfs || echo "AuzixServiceRuntime: sysfs mount unavailable: ${sys_path}" >&2
mount_if_needed "${dev_path}" devtmpfs devtmpfs || mount_if_needed "${dev_path}" tmpfs tmpfs || echo "AuzixServiceRuntime: dev mount unavailable: ${dev_path}" >&2
mount_if_needed "${devpts_path}" devpts devpts "gid=5,mode=620,ptmxmode=666" || mount_if_needed "${devpts_path}" devpts devpts || echo "AuzixServiceRuntime: devpts mount unavailable: ${devpts_path}" >&2
mount_if_needed "${devshm_path}" tmpfs tmpfs "mode=1777,nosuid,nodev" || echo "AuzixServiceRuntime: dev shm mount unavailable: ${devshm_path}" >&2
mount_if_needed "${run_path}" tmpfs tmpfs "mode=0755,nosuid,nodev" || echo "AuzixServiceRuntime: run mount unavailable: ${run_path}" >&2
mount_if_needed "${cgroup_path}" cgroup2 cgroup2 || echo "AuzixServiceRuntime: cgroup2 mount unavailable: ${cgroup_path}" >&2

if [ "${ROOT}" = "/" ]; then
  "${BB}" chgrp tty /dev/ptmx /dev/tty /dev/tty[0-9]* 2>/dev/null || true
  "${BB}" chmod 0666 /dev/ptmx /dev/pts/ptmx /dev/tty 2>/dev/null || true
fi

if [ "${ROOT}" = "/" ] && [ -w /proc/sys/net/ipv4/ping_group_range ]; then
  echo "0 2147483647" >/proc/sys/net/ipv4/ping_group_range 2>/dev/null || true
fi

missing=""
for path in "${proc_path}" "${sys_path}" "${dev_path}" "${run_path}" "${cgroup_path}" "${devpts_path}" "${devshm_path}"; do
  if ! is_mounted "${path}"; then
    missing="${missing} ${path}"
  fi
done

if [ -n "${missing}" ]; then
  echo "AuzixServiceRuntime: runtime mounts incomplete:${missing}" >&2
  exit 1
fi

echo "AuzixServiceRuntime: runtime mounts ready at ${ROOT}"
SCRIPT

cat >"${SERVICE}/run" <<'SCRIPT'
#!/Programs/BusyBox/current/Commands/busybox sh
exec /Programs/AuzixServiceRuntime/current/Commands/ensure-runtime-mounts /
SCRIPT

chmod 0755 "${PROGRAM}/Commands/ensure-runtime-mounts" "${SERVICE}/run"
ln -sfn "/Programs/AuzixServiceRuntime/${VERSION}" "${AUZIX_ROOT}/Programs/AuzixServiceRuntime/current"

cat >"${PACKAGE_DB}/AuzixServiceRuntime-${VERSION}.auzix.json" <<EOF
{
  "name": "AuzixServiceRuntime",
  "version": "${VERSION}",
  "kind": "runtime-support",
  "migration_stage": "service-runtime-mount-contract",
  "description": "AUZiX runtime mount substrate for services and app validation: proc, sysfs, devtmpfs/devpts, tmpfs run/dev-shm, and cgroup2.",
  "depends": ["BusyBox"],
  "prefix": "/Programs/AuzixServiceRuntime/${VERSION}",
  "commands": ["/Programs/AuzixServiceRuntime/${VERSION}/Commands/ensure-runtime-mounts"],
  "service": "/Services/runtime-mounts",
  "hooks": {"post_install": "/Programs/AuzixServiceRuntime/${VERSION}/Commands/ensure-runtime-mounts /"},
  "paths": {"current": "/Programs/AuzixServiceRuntime/current"},
  "runtime_contract": {
    "mounts": [
      {"path": "/proc", "type": "proc"},
      {"path": "/sys", "type": "sysfs"},
      {"path": "/sys/fs/cgroup", "type": "cgroup2"},
      {"path": "/dev", "type": "devtmpfs"},
      {"path": "/dev/pts", "type": "devpts"},
      {"path": "/dev/shm", "type": "tmpfs"},
      {"path": "/run", "type": "tmpfs"}
    ],
    "consumers": ["Podman", "Flatpak", "LibreOffice", "GStreamer", "FFmpeg", "desktop-session"]
  },
  "validation": {
    "smoke_commands": [
      "/Programs/AuzixServiceRuntime/current/Commands/ensure-runtime-mounts /",
      "mount | grep -E ' /proc | /sys | /sys/fs/cgroup '"
    ]
  },
  "notes": "Graduates the existing AuzixServiceRuntime pseudo-package and carries the vmid135 Podman cgroup fix as an installable AUZiX runtime contract."
}
EOF

printf '[service-runtime] staged AuzixServiceRuntime %s\n' "${VERSION}"
