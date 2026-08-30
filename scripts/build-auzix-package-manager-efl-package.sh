#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
BUILD_DIR="${ROOT_DIR}/out/auzix-packages/package-manager-efl"
SOURCE="${ROOT_DIR}/installer/efl/auzix-package-manager-efl.c"
BIN="${AUZIX_EFL_PACKAGE_MANAGER_BINARY:-${BUILD_DIR}/auzix-package-manager-efl}"
PROGRAM="${AUZIX_ROOT}/Programs/AuzixPackageManagerEfl/0.1"

[[ -d "${AUZIX_ROOT}/System" ]] || { echo "Missing AuziX root: ${AUZIX_ROOT}" >&2; exit 1; }
mkdir -p "${BUILD_DIR}" "${PROGRAM}/Commands" "${PROGRAM}/Resources" \
  "${AUZIX_ROOT}/System/Compatibility/usr/share/applications" \
  "${AUZIX_ROOT}/System/PackageDB" "${AUZIX_ROOT}/System/Tools"

if [[ ! -x "${BIN}" || "${SOURCE}" -nt "${BIN}" ]]; then
  command -v gcc >/dev/null || { echo "Build in the disposable EFL builder (gcc missing)." >&2; exit 1; }
  pkg-config --exists elementary || { echo "Build in the disposable EFL builder (Elementary headers missing)." >&2; exit 1; }
  gcc -D_GNU_SOURCE -O2 -Wall -Wextra -Werror -o "${BIN}" "${SOURCE}" \
    $(pkg-config --cflags --libs elementary)
fi

install -m 0755 "${BIN}" "${PROGRAM}/Commands/efl.real"
cat >"${PROGRAM}/Commands/efl" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
export LD_LIBRARY_PATH="/Programs/AuzixPackageManagerEfl/current/Libraries:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
exec /Programs/AuzixPackageManagerEfl/current/Commands/efl.real "$@"
SCRIPT
chmod 0755 "${PROGRAM}/Commands/efl"
install -m 0644 "${SOURCE}" "${PROGRAM}/Resources/auzix-package-manager-efl.c"
ln -sfn /Programs/AuzixPackageManagerEfl/0.1 "${AUZIX_ROOT}/Programs/AuzixPackageManagerEfl/current"
ln -sfn /Programs/AuzixPackageManagerEfl/current/Commands/efl "${AUZIX_ROOT}/System/Tools/auzix-package-manager"

cat >"${AUZIX_ROOT}/System/Compatibility/usr/share/applications/auzix-package-manager.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=AuziX Package Manager
Comment=Browse and install software from the AuziX repository
Exec=/System/Tools/auzix-package-manager
Icon=system-software-install
Terminal=false
Categories=System;Settings;
Keywords=packages;software;install;
EOF

cat >"${AUZIX_ROOT}/System/PackageDB/AuzixPackageManagerEfl-0.1.auzix.json" <<'EOF'
{
  "name": "AuzixPackageManagerEfl",
  "version": "0.1",
  "kind": "program",
  "state": "first-pass",
  "prefix": "/Programs/AuzixPackageManagerEfl/0.1",
  "depends": ["AuzixPackageTools", "Enlightenment"],
  "notes": "Thin native EFL frontend; repository and transaction semantics remain in auzix-pkg."
}
EOF

echo "[auzix-package-manager-efl] installed ${PROGRAM}"
