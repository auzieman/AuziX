#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
WORK_DIR="${ROOT_DIR}/out/auzix-packages/installer"
INSTALLER_VERSION="${AUZIX_INSTALLER_VERSION:-0.2}"
LUA_VERSION="${AUZIX_LUA_VERSION:-$(apt-cache show lua5.4 2>/dev/null | awk '/^Version:/ && !version {version=$2} END {print version}' || true)}"
DIALOG_VERSION="${AUZIX_DIALOG_VERSION:-$(apt-cache show dialog 2>/dev/null | awk '/^Version:/ && !version {version=$2} END {print version}' || true)}"
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

ensure_apt_candidate() {
  local package="$1"
  if ! apt-cache policy "${package}" 2>/dev/null | awk '/^[[:space:]]*Candidate:/ && $2 != "(none)" {found=1} END {exit found ? 0 : 1}'; then
    log "Refreshing apt metadata; ${package} has no candidate in this builder image"
    apt-get update >/dev/null
  fi
}

ensure_apt_candidate lua5.4
ensure_apt_candidate dialog

rm -rf \
  "${WORK_DIR}" \
  "${AUZIX_ROOT}/Programs/Lua" \
  "${AUZIX_ROOT}/Programs/Dialog" \
  "${AUZIX_ROOT}/Programs/AuzixInstaller"
rm -f \
  "${AUZIX_ROOT}"/System/PackageDB/Lua-*.auzix.json \
  "${AUZIX_ROOT}"/System/PackageDB/Dialog-*.auzix.json \
  "${AUZIX_ROOT}"/System/PackageDB/AuzixInstaller-*.auzix.json
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
  "${INSTALLER_PROGRAM}/Commands" "${INSTALLER_PROGRAM}/Frontends" "${INSTALLER_PROGRAM}/Resources/plans" "${INSTALLER_PROGRAM}/Resources/theme" \
  "${RUNTIME_LIB}" "${RUNTIME_LIB64}" \
  "${AUZIX_ROOT}/System/Compatibility/bin" "${AUZIX_ROOT}/System/Compatibility/usr/bin" \
  "${AUZIX_ROOT}/System/Compatibility/usr/share/applications" \
  "${AUZIX_ROOT}/System/Settings/installer/plans" "${AUZIX_ROOT}/System/Settings/installer/theme" "${AUZIX_ROOT}/System/State/installer" \
  "${AUZIX_ROOT}/System/PackageDB" "${AUZIX_ROOT}/System/Tools"

install -m 0755 "${LUA_SOURCE}" "${LUA_PROGRAM}/Commands/lua.real"
copy_runtime_deps "${LUA_SOURCE}" "${LUA_PROGRAM}"
cat >"${LUA_PROGRAM}/Commands/lua" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
exec /Programs/Lua/current/Libraries/ld-linux-x86-64.so.2 \
  --library-path /Programs/Lua/current/Libraries \
  /Programs/Lua/current/Commands/lua.real "$@"
SCRIPT
chmod 0755 "${LUA_PROGRAM}/Commands/lua"

install -m 0755 "${DIALOG_SOURCE}" "${DIALOG_PROGRAM}/Commands/dialog.real"
copy_runtime_deps "${DIALOG_SOURCE}" "${DIALOG_PROGRAM}"
cat >"${DIALOG_PROGRAM}/Commands/dialog" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
[ -r /System/Settings/auzix-paths.sh ] && . /System/Settings/auzix-paths.sh
export TERM="${TERM:-xterm}"
export LD_LIBRARY_PATH="/Programs/Dialog/current/Libraries:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
exec /Programs/Dialog/current/Commands/dialog.real "$@"
SCRIPT
chmod 0755 "${DIALOG_PROGRAM}/Commands/dialog"

install -m 0644 "${ROOT_DIR}/installer/auzix-installer.lua" "${INSTALLER_PROGRAM}/Resources/auzix-installer.lua"
install -m 0644 "${ROOT_DIR}/installer/auzix-package-setup.lua" "${INSTALLER_PROGRAM}/Resources/auzix-package-setup.lua"
install -m 0644 "${ROOT_DIR}/installer/install-plan.schema.json" "${INSTALLER_PROGRAM}/Resources/install-plan.schema.json"
install -m 0644 "${ROOT_DIR}/installer/questions.json" "${INSTALLER_PROGRAM}/Resources/questions.json"
for plan in "${ROOT_DIR}"/installer/plans/*.json; do
  install -m 0644 "${plan}" "${INSTALLER_PROGRAM}/Resources/plans/$(basename "${plan}")"
done
install -m 0644 "${ROOT_DIR}/installer/install-plan.schema.json" "${AUZIX_ROOT}/System/Settings/installer/install-plan.schema.json"
install -m 0644 "${ROOT_DIR}/installer/questions.json" "${AUZIX_ROOT}/System/Settings/installer/questions.json"
for plan in "${ROOT_DIR}"/installer/plans/*.json; do
  install -m 0644 "${plan}" "${AUZIX_ROOT}/System/Settings/installer/plans/$(basename "${plan}")"
done
if [[ -d "${ROOT_DIR}/installer/theme" ]]; then
  find "${ROOT_DIR}/installer/theme" -maxdepth 2 -type f | while IFS= read -r theme_file; do
    rel="${theme_file#"${ROOT_DIR}/installer/theme/"}"
    case "${rel}" in
      assets/*)
        install -D -m 0644 "${theme_file}" "${INSTALLER_PROGRAM}/Resources/theme/$(basename "${theme_file}")"
        install -D -m 0644 "${theme_file}" "${AUZIX_ROOT}/System/Settings/installer/theme/$(basename "${theme_file}")"
        ;;
      *)
        install -D -m 0644 "${theme_file}" "${INSTALLER_PROGRAM}/Resources/theme/${rel}"
        install -D -m 0644 "${theme_file}" "${AUZIX_ROOT}/System/Settings/installer/theme/${rel}"
        ;;
    esac
  done
fi

cat >"${INSTALLER_PROGRAM}/Commands/auzix-installer" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -eu
PATH=/Programs/AuzixPackageTools/current/Commands:/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
exec /Programs/Lua/current/Commands/lua /Programs/AuzixInstaller/current/Resources/auzix-installer.lua "$@"
SCRIPT
chmod 0755 "${INSTALLER_PROGRAM}/Commands/auzix-installer"

cat >"${INSTALLER_PROGRAM}/Commands/auzix-package-setup" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -eu
PATH=/Programs/AuzixPackageTools/current/Commands:/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
exec /Programs/Lua/current/Commands/lua /Programs/AuzixInstaller/current/Resources/auzix-package-setup.lua "$@"
SCRIPT
chmod 0755 "${INSTALLER_PROGRAM}/Commands/auzix-package-setup"

cat >"${INSTALLER_PROGRAM}/Commands/auzix-installer-gui" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -eu

[ -r /System/Settings/auzix-paths.sh ] && . /System/Settings/auzix-paths.sh

case "${AUZIX_INSTALLER_FRONTEND:-safe}" in
  efl)
    frontend=/Programs/AuzixInstaller/current/Frontends/efl
    if [ -x "${frontend}" ]; then
      exec "${frontend}" \
        --questions /System/Settings/installer/questions.json \
        --schema /System/Settings/installer/install-plan.schema.json "$@"
    fi
    echo "Requested EFL installer frontend is not installed; falling back to TUI." >&2
    ;;
  gtk)
    frontend=/Programs/AuzixInstaller/current/Frontends/gtk
    if [ -x "${frontend}" ]; then
      exec "${frontend}" \
        --questions /System/Settings/installer/questions.json \
        --schema /System/Settings/installer/install-plan.schema.json "$@"
    fi
    echo "Requested GTK installer frontend is not installed; falling back to TUI." >&2
    ;;
  auto)
    for frontend in \
      /Programs/AuzixInstaller/current/Frontends/efl \
      /Programs/AuzixInstaller/current/Frontends/gtk; do
      if [ -x "${frontend}" ]; then
        exec "${frontend}" \
          --questions /System/Settings/installer/questions.json \
          --schema /System/Settings/installer/install-plan.schema.json "$@"
      fi
    done
    ;;
  safe|tui|"")
    ;;
  *)
    echo "Unknown AUZIX_INSTALLER_FRONTEND=${AUZIX_INSTALLER_FRONTEND}; falling back to TUI." >&2
    ;;
esac

echo "No graphical installer frontend is installed; starting the dialog frontend." >&2
exec /Programs/AuzixInstaller/current/Commands/auzix-installer tui "$@"
SCRIPT
chmod 0755 "${INSTALLER_PROGRAM}/Commands/auzix-installer-gui"

cat >"${INSTALLER_PROGRAM}/Commands/launch-auzix-installer" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -eu

[ -r /System/Settings/auzix-paths.sh ] && . /System/Settings/auzix-paths.sh
PATH=/Programs/BusyBox/current/Commands:/Programs/XTerm/current/Commands:/Programs/Terminology/current/Commands:/Programs/AuzixInstaller/current/Commands:${PATH:-}
export PATH
export AUZIX_INSTALLER_FRONTEND="${AUZIX_INSTALLER_FRONTEND:-auto}"
export ECORE_EVAS_ENGINE="${ECORE_EVAS_ENGINE:-software_x11}"
export ELM_ENGINE="${ELM_ENGINE:-software_x11}"
export ELM_ACCEL="${ELM_ACCEL:-none}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"

if [ "${1:-}" = "--autostart" ]; then
  shift
  sleep "${AUZIX_INSTALLER_AUTOSTART_DELAY:-3}"
fi

log_dir=/System/Logs/installer
mkdir -p "${log_dir}" 2>/dev/null || true
log_file="${log_dir}/installer-launch.log"

if [ -n "${DISPLAY:-}" ]; then
  if [ -x /Programs/AuzixInstaller/current/Frontends/efl ]; then
    exec /System/Tools/auzix-installer-gui "$@" >>"${log_file}" 2>&1
  fi
  if command -v xterm >/dev/null 2>&1; then
    exec xterm -T "Install AuziX" -e /System/Tools/auzix-installer-gui "$@" >>"${log_file}" 2>&1
  fi
  if command -v terminology >/dev/null 2>&1; then
    exec terminology -e /System/Tools/auzix-installer-gui "$@" >>"${log_file}" 2>&1
  fi
fi

exec /System/Tools/auzix-installer-gui "$@" >>"${log_file}" 2>&1
SCRIPT
chmod 0755 "${INSTALLER_PROGRAM}/Commands/launch-auzix-installer"

cat >"${AUZIX_ROOT}/System/Compatibility/usr/share/applications/auzix-installer.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Install AuziX
Comment=Install AuziX using the guided installer
Exec=/System/Tools/launch-auzix-installer
Icon=drive-harddisk
Terminal=false
Categories=System;Settings;
Keywords=install;disk;system;
EOF

cat >"${AUZIX_ROOT}/System/Compatibility/usr/share/applications/auzix-package-setup.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=AuziX Package Setup
Comment=Install software from the AuziX repository
Exec=/System/Tools/auzix-package-setup
Icon=system-software-install
Terminal=true
Categories=System;Settings;
Keywords=packages;software;install;
EOF

ln -sfn "/Programs/Lua/${LUA_VERSION}" "${AUZIX_ROOT}/Programs/Lua/current"
ln -sfn "/Programs/Dialog/${DIALOG_VERSION}" "${AUZIX_ROOT}/Programs/Dialog/current"
ln -sfn "/Programs/AuzixInstaller/${INSTALLER_VERSION}" "${AUZIX_ROOT}/Programs/AuzixInstaller/current"
ln -sfn /Programs/Lua/current/Commands/lua "${AUZIX_ROOT}/System/Compatibility/bin/lua"
ln -sfn /Programs/Dialog/current/Commands/dialog "${AUZIX_ROOT}/System/Compatibility/bin/dialog"
ln -sfn /Programs/AuzixInstaller/current/Commands/auzix-installer "${AUZIX_ROOT}/System/Tools/auzix-installer"
ln -sfn /Programs/AuzixInstaller/current/Commands/auzix-installer-gui "${AUZIX_ROOT}/System/Tools/auzix-installer-gui"
ln -sfn /Programs/AuzixInstaller/current/Commands/launch-auzix-installer "${AUZIX_ROOT}/System/Tools/launch-auzix-installer"
ln -sfn /Programs/AuzixInstaller/current/Commands/auzix-package-setup "${AUZIX_ROOT}/System/Tools/auzix-package-setup"

cat >"${AUZIX_ROOT}/System/PackageDB/Lua-${LUA_VERSION}.auzix.json" <<EOF
{
  "name": "Lua",
  "version": "${LUA_VERSION}",
  "kind": "program",
  "migration_stage": "stage-1-compat-install",
  "prefix": "/Programs/Lua/${LUA_VERSION}",
  "paths": {"current": "/Programs/Lua/current"},
  "commands": ["/Programs/Lua/${LUA_VERSION}/Commands/lua"],
  "compatibility_exports": ["/System/Compatibility/bin/lua"],
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
  "compatibility_exports": ["/System/Compatibility/bin/dialog"],
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
    "/Programs/AuzixInstaller/${INSTALLER_VERSION}/Commands/auzix-installer-gui",
    "/Programs/AuzixInstaller/${INSTALLER_VERSION}/Commands/launch-auzix-installer",
    "/Programs/AuzixInstaller/${INSTALLER_VERSION}/Commands/auzix-package-setup"
  ],
  "theme": {
    "settings": "/System/Settings/installer/theme/installer-theme.json",
    "mark": "/System/Settings/installer/theme/mark-shield-swords.png",
    "fallback": "Text-only dark theme when artwork is absent"
  },
  "compatibility_exports": [
    "/System/Tools/auzix-installer",
    "/System/Tools/auzix-installer-gui",
    "/System/Tools/launch-auzix-installer",
    "/System/Tools/auzix-package-setup",
    "/System/Compatibility/usr/share/applications/auzix-installer.desktop",
    "/System/Compatibility/usr/share/applications/auzix-package-setup.desktop"
  ],
  "depends": ["Lua", "Dialog", "AuzixPackageTools"],
  "notes": "JSON-plan installer plus a Lua/Dialog package setup frontend that delegates transactions to auzix-pkg."
}
EOF

if [[ "${AUZIX_SKIP_INSTALLER_SELFTEST:-0}" != "1" ]]; then
  # This smoke test is valid only when the builder's jq ABI matches the staged
  # compatibility runtime. Cross-era package builders should run the dedicated
  # target-root test instead of loading host jq with staged libjq.
  LD_LIBRARY_PATH="${LUA_PROGRAM}/Libraries:${RUNTIME_LIB}:${RUNTIME_LIB64}" \
    AUZIX_JQ="$(command -v jq)" \
    "${LUA_PROGRAM}/Commands/lua.real" \
    "${INSTALLER_PROGRAM}/Resources/auzix-installer.lua" \
    validate "${INSTALLER_PROGRAM}/Resources/plans/default.json" >/dev/null
fi

log "Lua installed at ${LUA_PROGRAM}"
log "Dialog installed at ${DIALOG_PROGRAM}"
log "Installer installed at ${INSTALLER_PROGRAM}"
