#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
BUILD_DIR="${ROOT_DIR}/out/auzix-packages/installer-efl"
SOURCE="${ROOT_DIR}/installer/efl/auzix-installer-efl.c"
LAUNCHER_SOURCE="${ROOT_DIR}/installer/efl/launch-auzix-installer"
BIN="${AUZIX_EFL_INSTALLER_BINARY:-${BUILD_DIR}/auzix-installer-efl}"
PROGRAM="${AUZIX_ROOT}/Programs/AuzixInstallerEfl/0.1"
INSTALLER_FRONTENDS="${AUZIX_ROOT}/Programs/AuzixInstaller/0.2/Frontends"

[[ -d "${AUZIX_ROOT}/System" ]] || { echo "Missing AuziX root: ${AUZIX_ROOT}" >&2; exit 1; }
mkdir -p "${BUILD_DIR}" "${PROGRAM}/Commands" "${PROGRAM}/Resources" "${INSTALLER_FRONTENDS}" "${AUZIX_ROOT}/System/PackageDB"

if [[ ! -x "${BIN}" || "${SOURCE}" -nt "${BIN}" ]]; then
  command -v gcc >/dev/null || { echo "Build this package in the disposable EFL builder (gcc missing)." >&2; exit 1; }
  command -v pkg-config >/dev/null || { echo "Build this package in the disposable EFL builder (pkg-config missing)." >&2; exit 1; }
  pkg-config --exists elementary || { echo "Build this package in the disposable EFL builder (elementary headers missing)." >&2; exit 1; }
  # Elementary headers expose POSIX APIs such as strdup behind their feature
  # declarations.  Make that contract explicit so the disposable builder and
  # future build images compile the same source deterministically.
  gcc -D_GNU_SOURCE -O2 -Wall -Wextra -Werror -o "${BIN}" "${SOURCE}" $(pkg-config --cflags --libs elementary)
fi

install -m 0755 "${BIN}" "${PROGRAM}/Commands/efl.real"
cat >"${PROGRAM}/Commands/efl" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
export LD_LIBRARY_PATH="/Programs/AuzixInstallerEfl/current/Libraries:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
exec /Programs/AuzixInstallerEfl/current/Commands/efl.real "$@"
SCRIPT
chmod 0755 "${PROGRAM}/Commands/efl"
install -m 0755 "${LAUNCHER_SOURCE}" "${PROGRAM}/Commands/launch-auzix-installer"
install -m 0644 "${SOURCE}" "${PROGRAM}/Resources/auzix-installer-efl.c"
ln -sfn /Programs/AuzixInstallerEfl/0.1 "${AUZIX_ROOT}/Programs/AuzixInstallerEfl/current"
ln -sfn /Programs/AuzixInstallerEfl/current/Commands/efl "${INSTALLER_FRONTENDS}/efl"
ln -sfn /Programs/AuzixInstallerEfl/current/Commands/launch-auzix-installer \
  "${AUZIX_ROOT}/System/Tools/launch-auzix-installer"
cat >"${AUZIX_ROOT}/System/PackageDB/AuzixInstallerEfl-0.1.auzix.json" <<'EOF'
{
  "name": "AuzixInstallerEfl",
  "version": "0.1",
  "kind": "program",
  "state": "first-pass",
  "prefix": "/Programs/AuzixInstallerEfl/0.1",
  "depends": ["AuzixInstaller", "Enlightenment"],
  "notes": "Native Elementary frontend. It emits only an unconfirmed validated install plan; the core executor retains the destructive gate."
}
EOF
echo "[auzix-installer-efl] installed ${PROGRAM}"
