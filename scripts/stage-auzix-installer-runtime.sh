#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="${1:?usage: stage-auzix-installer-runtime.sh PACKAGE_STAGE}"
PROGRAM="${STAGE}/Programs/AuzixInstaller/0.2"
TEMPLATE="${PROGRAM}/Resources/installed-root"

# Generate the existing installed-root contract on the builder. The installed
# demo must not need gcc, a source checkout, or access to the lab filesystem.
mkdir -p "${TEMPLATE}" "${STAGE}/System/Tools" "${STAGE}/System/Settings/install/apk-installer"
AUZIX_DISPLAY_AUTOSTART=manual bash "${ROOT_DIR}/scripts/add-auzix-live-tools.sh" "${TEMPLATE}"
test -x "${TEMPLATE}/System/Boot/InstalledInit"
test -x "${TEMPLATE}/System/Tools/auzix-run-as-uid"
install -m 0755 "${ROOT_DIR}/scripts/auzix-install-root-from-repo-profile.sh" \
  "${STAGE}/System/Tools/auzix-install-root-from-repo-profile"
install -m 0644 "${ROOT_DIR}/profiles/packages/auzix-alpha-installer.apk.list" \
  "${STAGE}/System/Settings/install/apk-installer/10-alpha-minimal.list"
printf 'installer runtime staged: %s\n' "${PROGRAM}"
