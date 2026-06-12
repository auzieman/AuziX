#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
WORK_DIR="${ROOT_DIR}/out/auzix-packages/installer"
INSTALLER_VERSION="${AUZIX_INSTALLER_VERSION:-0.1}"
LUA_VERSION="${AUZIX_LUA_VERSION:-$(apt-cache show lua5.4 2>/dev/null | awk '/^Version:/ && !version {version=$2} END {print version}')}"
DIALOG_VERSION="${AUZIX_DIALOG_VERSION:-$(apt-cache show dialog 2>/dev/null | awk '/^Version:/ && !version {version=$2} END {print version}')}"
LUA_VERSION="${LUA_VERSION:-5.4}"
DIALOG_VERSION="${DIALOG_VERSION:-host}"
LUA_PROGRAM="${AUZIX_ROOT}/Programs/Lua/${LUA_VERSION}"
DIALOG_PROGRAM="${AUZIX_ROOT}/Programs/Dialog/${DIALOG_VERSION}"
INSTALLER_PROGRAM="${AUZIX_ROOT}/Programs/AuzixInstaller/${INSTALLER_VERSION}"
RUNTIME_LIB="${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
RUNTIME_LIB64="${AUZIX_ROOT}/System/Compatibility/lib64"

log() {
  printf '[auzix-installer] %s\n' "$*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

copy_runtime_deps() {
  local binary="$1"
  local program_root="$2"
  local dep

  ldd "${binary}" 2>/dev/null |
    awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i }' |
    sort -u |
    while IFS= read -r dep; do
      [[ -e "${dep}" ]] || continue
      case "${dep}" in
        /lib64/*)
          install -D -m 0755 "${dep}" "${RUNTIME_LIB64}/$(basename "${dep}")"
          install -D -m 0755 "${dep}" "${program_root}/Libraries/$(basename "${dep}")"
          ;;
        /lib/x86_64-linux-gnu/*|/usr/lib/x86_64-linux-gnu/*)
          install -D -m 0755 "${dep}" "${RUNTIME_LIB}/$(basename "${dep}")"
          install -D -m 0755 "${dep}" "${program_root}/Libraries/$(basename "${dep}")"
          ;;
        *)
          install -D -m 0755 "${dep}" "${AUZIX_ROOT}${dep}"
          ;;
      esac
    done
}

if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

for command_name in apt-cache apt-get dpkg-deb install ldd jq; do
  require_cmd "${command_name}"
done

rm -rf "${WORK_DIR}" "${LUA_PROGRAM}" "${DIALOG_PROGRAM}" "${INSTALLER_PROGRAM}"
mkdir -p "${WORK_DIR}/debs" "${WORK_DIR}/extract"
(
  cd "${WORK_DIR}/debs"
  apt-get download lua5.4 dialog >/dev/null
)
for deb in "${WORK_DIR}"/debs/*.deb; do
  dpkg-deb -x "${deb}" "${WORK_DIR}/extract"
done

LUA_SOURCE="${WORK_DIR}/extract/usr/bin/lua5.4"
DIALOG_SOURCE="${WORK_DIR}/extract/usr/bin/dialog"
[[ -x "${LUA_SOURCE}" ]] || {
  printf 'lua5.4 binary not found in downloaded package.\n' >&2
  exit 1
}
[[ -x "${DIALOG_SOURCE}" ]] || {
  printf 'dialog binary not found in downloaded package.\n' >&2
  exit 1
}

mkdir -p \
  "${LUA_PROGRAM}/Commands" "${LUA_PROGRAM}/Libraries" \
  "${DIALOG_PROGRAM}/Commands" "${DIALOG_PROGRAM}/Libraries" \
  "${INSTALLER_PROGRAM}/Commands" "${INSTALLER_PROGRAM}/Frontends" "${INSTALLER_PROGRAM}/Resources/plans" \
  "${RUNTIME_LIB}" "${RUNTIME_LIB64}" \
  "${AUZIX_ROOT}/System/Compatibility/bin" "${AUZIX_ROOT}/System/Compatibility/usr/bin" \
  "${AUZIX_ROOT}/System/Settings/installer/plans" "${AUZIX_ROOT}/System/State/installer" \
  "${AUZIX_ROOT}/System/PackageDB" "${AUZIX_ROOT}/System/Tools"

install -m 0755 "${LUA_SOURCE}" "${LUA_PROGRAM}/Commands/lua.real"
copy_runtime_deps "${LUA_SOURCE}" "${LUA_PROGRAM}"
cat >"${LUA_PROGRAM}/Commands/lua" <<'SCRIPT'
#!/System/Compatibility/bin/sh
export LD_LIBRARY_PATH="/Programs/Lua/current/Libraries:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
exec /Programs/Lua/current/Commands/lua.real "$@"
SCRIPT
chmod 0755 "${LUA_PROGRAM}/Commands/lua"

install -m 0755 "${DIALOG_SOURCE}" "${DIALOG_PROGRAM}/Commands/dialog.real"
copy_runtime_deps "${DIALOG_SOURCE}" "${DIALOG_PROGRAM}"
cat >"${DIALOG_PROGRAM}/Commands/dialog" <<'SCRIPT'
#!/System/Compatibility/bin/sh
export TERM="${TERM:-xterm}"
export LD_LIBRARY_PATH="/Programs/Dialog/current/Libraries:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
exec /Programs/Dialog/current/Commands/dialog.real "$@"
SCRIPT
chmod 0755 "${DIALOG_PROGRAM}/Commands/dialog"

install -m 0644 "${ROOT_DIR}/installer/auzix-installer.lua" "${INSTALLER_PROGRAM}/Resources/auzix-installer.lua"
install -m 0644 "${ROOT_DIR}/installer/install-plan.schema.json" "${INSTALLER_PROGRAM}/Resources/install-plan.schema.json"
install -m 0644 "${ROOT_DIR}/installer/questions.json" "${INSTALLER_PROGRAM}/Resources/questions.json"
install -m 0644 "${ROOT_DIR}/installer/plans/default.json" "${INSTALLER_PROGRAM}/Resources/plans/default.json"
install -m 0644 "${ROOT_DIR}/installer/install-plan.schema.json" "${AUZIX_ROOT}/System/Settings/installer/install-plan.schema.json"
install -m 0644 "${ROOT_DIR}/installer/questions.json" "${AUZIX_ROOT}/System/Settings/installer/questions.json"
install -m 0644 "${ROOT_DIR}/installer/plans/default.json" "${AUZIX_ROOT}/System/Settings/installer/plans/default.json"

cat >"${INSTALLER_PROGRAM}/Commands/auzix-installer" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -eu
PATH=/Programs/AuzixPackageTools/current/Commands:/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
exec /Programs/Lua/current/Commands/lua /Programs/AuzixInstaller/current/Resources/auzix-installer.lua "$@"
SCRIPT
chmod 0755 "${INSTALLER_PROGRAM}/Commands/auzix-installer"

cat >"${INSTALLER_PROGRAM}/Commands/auzix-installer-gui" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -eu

for frontend in \
  /Programs/AuzixInstaller/current/Frontends/efl \
  /Programs/AuzixInstaller/current/Frontends/gtk; do
  if [ -x "${frontend}" ]; then
    exec "${frontend}" \
      --questions /System/Settings/installer/questions.json \
      --schema /System/Settings/installer/install-plan.schema.json "$@"
  fi
done

echo "No graphical installer frontend is installed; starting the dialog frontend." >&2
exec /Programs/AuzixInstaller/current/Commands/auzix-installer tui "$@"
SCRIPT
chmod 0755 "${INSTALLER_PROGRAM}/Commands/auzix-installer-gui"

ln -sfn "/Programs/Lua/${LUA_VERSION}" "${AUZIX_ROOT}/Programs/Lua/current"
ln -sfn "/Programs/Dialog/${DIALOG_VERSION}" "${AUZIX_ROOT}/Programs/Dialog/current"
ln -sfn "/Programs/AuzixInstaller/${INSTALLER_VERSION}" "${AUZIX_ROOT}/Programs/AuzixInstaller/current"
ln -sfn /Programs/Lua/current/Commands/lua "${AUZIX_ROOT}/System/Compatibility/bin/lua"
ln -sfn /Programs/Dialog/current/Commands/dialog "${AUZIX_ROOT}/System/Compatibility/bin/dialog"
ln -sfn /Programs/AuzixInstaller/current/Commands/auzix-installer "${AUZIX_ROOT}/System/Tools/auzix-installer"
ln -sfn /Programs/AuzixInstaller/current/Commands/auzix-installer-gui "${AUZIX_ROOT}/System/Tools/auzix-installer-gui"

cat >"${AUZIX_ROOT}/System/PackageDB/Lua-${LUA_VERSION}.auzix.json" <<EOF
{
  "name": "Lua",
  "version": "${LUA_VERSION}",
  "kind": "program",
  "migration_stage": "stage-1-compat-install",
  "prefix": "/Programs/Lua/${LUA_VERSION}",
  "paths": {"current": "/Programs/Lua/current"},
  "commands": ["/Programs/Lua/${LUA_VERSION}/Commands/lua"],
  "notes": "Lua 5.4 runtime used by the AuziX installer orchestration layer."
}
EOF

cat >"${AUZIX_ROOT}/System/PackageDB/Dialog-${DIALOG_VERSION}.auzix.json" <<EOF
{
  "name": "Dialog",
  "version": "${DIALOG_VERSION}",
  "kind": "program",
  "migration_stage": "stage-1-compat-install",
  "prefix": "/Programs/Dialog/${DIALOG_VERSION}",
  "paths": {"current": "/Programs/Dialog/current"},
  "commands": ["/Programs/Dialog/${DIALOG_VERSION}/Commands/dialog"],
  "notes": "Terminal installer frontend. It emits the same JSON plan consumed by automation and future graphical frontends."
}
EOF

cat >"${AUZIX_ROOT}/System/PackageDB/AuzixInstaller-${INSTALLER_VERSION}.auzix.json" <<EOF
{
  "name": "AuzixInstaller",
  "version": "${INSTALLER_VERSION}",
  "kind": "program",
  "migration_stage": "stage-2-native-paths",
  "prefix": "/Programs/AuzixInstaller/${INSTALLER_VERSION}",
  "paths": {
    "current": "/Programs/AuzixInstaller/current",
    "settings": "/System/Settings/installer",
    "state": "/System/State/installer"
  },
  "commands": [
    "/Programs/AuzixInstaller/${INSTALLER_VERSION}/Commands/auzix-installer",
    "/Programs/AuzixInstaller/${INSTALLER_VERSION}/Commands/auzix-installer-gui"
  ],
  "depends": ["Lua", "Dialog", "AuzixPackageTools"],
  "notes": "JSON-plan installer with Lua sequencing, a dialog TUI, and a shared question protocol for EFL or GTK frontends."
}
EOF

LD_LIBRARY_PATH="${LUA_PROGRAM}/Libraries:${RUNTIME_LIB}:${RUNTIME_LIB64}" \
  AUZIX_JQ="$(command -v jq)" \
  "${LUA_PROGRAM}/Commands/lua.real" \
  "${INSTALLER_PROGRAM}/Resources/auzix-installer.lua" \
  validate "${INSTALLER_PROGRAM}/Resources/plans/default.json" >/dev/null

log "Lua installed at ${LUA_PROGRAM}"
log "Dialog installed at ${DIALOG_PROGRAM}"
log "Installer installed at ${INSTALLER_PROGRAM}"
