#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
LUA_CURRENT="$(basename "$(readlink "${AUZIX_ROOT}/Programs/Lua/current")")"
INSTALLER_CURRENT="$(basename "$(readlink "${AUZIX_ROOT}/Programs/AuzixInstaller/current")")"
PKGTOOLS_CURRENT="$(basename "$(readlink "${AUZIX_ROOT}/Programs/AuzixPackageTools/current")")"
LUA_REAL="${AUZIX_ROOT}/Programs/Lua/${LUA_CURRENT}/Commands/lua.real"
LUA_LIBS="${AUZIX_ROOT}/Programs/Lua/${LUA_CURRENT}/Libraries"
CORE_GLIBC="${AUZIX_ROOT}/System/Libraries/Runtime/glibc"
LUA_LOADER="${CORE_GLIBC}/ld-linux-x86-64.so.2"
JQ_REAL="${AUZIX_ROOT}/Programs/AuzixPackageTools/${PKGTOOLS_CURRENT}/Commands/jq.real"
JQ_LIBS="${AUZIX_ROOT}/Programs/AuzixPackageTools/${PKGTOOLS_CURRENT}/Libraries"
JQ_LOADER="${CORE_GLIBC}/ld-linux-x86-64.so.2"
INSTALLER_LUA="${AUZIX_ROOT}/Programs/AuzixInstaller/${INSTALLER_CURRENT}/Resources/auzix-installer.lua"
PACKAGE_SETUP_LUA="${AUZIX_ROOT}/Programs/AuzixInstaller/${INSTALLER_CURRENT}/Resources/auzix-package-setup.lua"
DEFAULT_PLAN="${AUZIX_ROOT}/System/Settings/installer/plans/default.json"
QUESTIONS="${AUZIX_ROOT}/System/Settings/installer/questions.json"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

for path in "${LUA_REAL}" "${LUA_LOADER}" "${JQ_REAL}" "${JQ_LOADER}" "${INSTALLER_LUA}" "${PACKAGE_SETUP_LUA}" "${DEFAULT_PLAN}"; do
  [[ -e "${path}" ]] || {
    printf 'Installer test prerequisite is missing: %s\n' "${path}" >&2
    exit 1
  }
done

run_installer() {
    AUZIX_ROOT="${AUZIX_ROOT}" \
    AUZIX_JQ="${WORK_DIR}/jq" \
    AUZIX_INSTALL_EXECUTOR="${WORK_DIR}/fake-install-disk" \
    "${LUA_LOADER}" --library-path "${AUZIX_ROOT}/System/Libraries:${CORE_GLIBC}:${LUA_LIBS}" "${LUA_REAL}" "${INSTALLER_LUA}" "$@"
}

run_package_setup() {
  AUZIX_ROOT="${AUZIX_ROOT}" \
    TMPDIR="${WORK_DIR}/missing/package-setup-temp" \
    AUZIX_DIALOG="${WORK_DIR}/fake-dialog" \
    AUZIX_PKG="${WORK_DIR}/fake-auzix-pkg" \
    AUZIX_PKG_PREFIX="" \
    AUZIX_TEST_PACKAGE_LOG="${WORK_DIR}/package.log" \
    "${LUA_LOADER}" --library-path "${AUZIX_ROOT}/System/Libraries:${CORE_GLIBC}:${LUA_LIBS}" "${LUA_REAL}" "${PACKAGE_SETUP_LUA}" "$@"
}

run_tui_installer() {
  local temp_dir="${WORK_DIR}/missing/dialog-temp"
  AUZIX_ROOT="${AUZIX_ROOT}" \
    TMPDIR="${temp_dir}" \
    AUZIX_JQ="${WORK_DIR}/jq" \
    AUZIX_DIALOG="${WORK_DIR}/fake-dialog" \
    AUZIX_INSTALLER_DISKS="/dev/vdz,/dev/vdy" \
    AUZIX_INSTALL_EXECUTOR="${WORK_DIR}/fake-install-disk" \
    "${LUA_LOADER}" --library-path "${AUZIX_ROOT}/System/Libraries:${CORE_GLIBC}:${LUA_LIBS}" "${LUA_REAL}" "${INSTALLER_LUA}" "$@"
}

cat >"${WORK_DIR}/fake-install-disk" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"${AUZIX_TEST_EXECUTOR_LOG}"
printf '%s\n' "${AUZIX_INSTALL_PLAN:-}" >"${AUZIX_TEST_EXECUTOR_LOG}.plan"
SCRIPT
chmod 0755 "${WORK_DIR}/fake-install-disk"

cat >"${WORK_DIR}/jq" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
exec "${JQ_LOADER}" --library-path "${AUZIX_ROOT}/System/Libraries:${CORE_GLIBC}:${JQ_LIBS}" "${JQ_REAL}" "\$@"
SCRIPT
chmod 0755 "${WORK_DIR}/jq"

cat >"${WORK_DIR}/fake-dialog" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
case " $* " in
  *" Installation disk "*) printf '%s' /dev/vdz >&2 ;;
  *" Boot method "*) printf '%s' iso >&2 ;;
  *" Hostname "*) printf '%s' installer-test >&2 ;;
  *" Available packages "*) printf '%s' Gnumeric >&2 ;;
  *" --msgbox "*) exit 0 ;;
  *" --yesno "*) exit "${AUZIX_TEST_DIALOG_CONFIRM:-0}" ;;
  *) printf 'Unexpected dialog invocation: %s\n' "$*" >&2; exit 2 ;;
esac
SCRIPT
chmod 0755 "${WORK_DIR}/fake-dialog"

cat >"${WORK_DIR}/fake-auzix-pkg" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${AUZIX_TEST_PACKAGE_LOG}"
case "${1:-}" in
  refresh) ;;
  list)
    [[ "${2:-}" == "available" ]]
    printf 'Gnumeric\t1.12.57\tprogram\t28.0 MiB\n'
    printf 'AbiWord\t3.0.6\tprogram\t56.0 MiB\n'
    ;;
  install) [[ "${2:-}" == "Gnumeric" ]] ;;
  *) exit 2 ;;
esac
SCRIPT
chmod 0755 "${WORK_DIR}/fake-auzix-pkg"

run_installer validate "${DEFAULT_PLAN}" >/dev/null

if run_installer run "${DEFAULT_PLAN}" >/dev/null 2>&1; then
  echo "Unconfirmed plan was executed." >&2
  exit 1
fi

"${WORK_DIR}/jq" '.target.disk = "not-a-device"' "${DEFAULT_PLAN}" >"${WORK_DIR}/invalid.json"
if run_installer validate "${WORK_DIR}/invalid.json" >/dev/null 2>&1; then
  echo "Invalid disk path passed validation." >&2
  exit 1
fi

"${WORK_DIR}/jq" '.unexpected = "ignored"' "${DEFAULT_PLAN}" >"${WORK_DIR}/extra-field.json"
if run_installer validate "${WORK_DIR}/extra-field.json" >/dev/null 2>&1; then
  echo "Unknown install plan field passed validation." >&2
  exit 1
fi

"${WORK_DIR}/jq" '
  .target.disk = "/dev/vdz"
  | .bootloader.mode = "iso"
  | .execution.confirmed = true
  | .frontend = "automation"
' "${DEFAULT_PLAN}" >"${WORK_DIR}/confirmed.json"

export AUZIX_TEST_EXECUTOR_LOG="${WORK_DIR}/executor.log"
run_installer run "${WORK_DIR}/confirmed.json" >/dev/null
cat >"${WORK_DIR}/expected.log" <<'EOF'
--force
--bootloader
iso
/dev/vdz
EOF
cmp "${WORK_DIR}/expected.log" "${WORK_DIR}/executor.log"
grep -Fx "${WORK_DIR}/confirmed.json" "${WORK_DIR}/executor.log.plan" >/dev/null

run_tui_installer tui-plan "${WORK_DIR}/tui-plan.json" >/dev/null
"${WORK_DIR}/jq" -e '
  .target.disk == "/dev/vdz"
  and .bootloader.mode == "iso"
  and .identity.hostname == "installer-test"
  and .execution.confirmed == false
  and .frontend == "tui"
' "${WORK_DIR}/tui-plan.json" >/dev/null

run_tui_installer plan "${WORK_DIR}/graphical-plan.json" /dev/vda grub auzix graphical >/dev/null
"${WORK_DIR}/jq" -e '
  .execution.confirmed == false
  and .frontend == "graphical"
  and .target.disk == "/dev/vda"
  and .bootloader.mode == "grub"
  and .identity.hostname == "auzix"
' "${WORK_DIR}/graphical-plan.json" >/dev/null
[[ ! -e "${WORK_DIR}/executor.log" ]] || rm -f "${WORK_DIR}/executor.log"

if run_installer run "${WORK_DIR}/graphical-plan.json" >/dev/null 2>&1; then
  echo "Unconfirmed graphical plan was executed." >&2
  exit 1
fi
"${WORK_DIR}/jq" '.execution.confirmed = true' \
  "${WORK_DIR}/graphical-plan.json" >"${WORK_DIR}/graphical-confirmed.json"
run_installer run "${WORK_DIR}/graphical-confirmed.json" >/dev/null
cat >"${WORK_DIR}/expected-graphical.log" <<'EOF'
--force
--bootloader
grub
/dev/vda
EOF
cmp "${WORK_DIR}/expected-graphical.log" "${WORK_DIR}/executor.log"
grep -Fx "${WORK_DIR}/graphical-confirmed.json" "${WORK_DIR}/executor.log.plan" >/dev/null
rm -f "${WORK_DIR}/executor.log"

"${WORK_DIR}/jq" '
  .packages.selected = ["Gnumeric"]
  | .execution.confirmed = true
' "${WORK_DIR}/graphical-plan.json" >"${WORK_DIR}/graphical-packages-confirmed.json"
run_installer run "${WORK_DIR}/graphical-packages-confirmed.json" >/dev/null
cmp "${WORK_DIR}/expected-graphical.log" "${WORK_DIR}/executor.log"
grep -Fx "${WORK_DIR}/graphical-packages-confirmed.json" "${WORK_DIR}/executor.log.plan" >/dev/null
rm -f "${WORK_DIR}/executor.log"

run_tui_installer tui "${WORK_DIR}/confirmed-tui-plan.json" >/dev/null
"${WORK_DIR}/jq" -e '.execution.confirmed == true' "${WORK_DIR}/confirmed-tui-plan.json" >/dev/null
cmp "${WORK_DIR}/expected.log" "${WORK_DIR}/executor.log"

rm -f "${WORK_DIR}/executor.log"
if AUZIX_TEST_DIALOG_CONFIRM=1 \
  run_tui_installer tui "${WORK_DIR}/cancelled-tui-plan.json" >/dev/null 2>&1; then
  echo "Cancelled TUI plan was executed." >&2
  exit 1
fi
"${WORK_DIR}/jq" -e '.execution.confirmed == false' "${WORK_DIR}/cancelled-tui-plan.json" >/dev/null
[[ ! -e "${WORK_DIR}/executor.log" ]]

"${WORK_DIR}/jq" -e '
  .format == "auzix-installer-questions-v1"
  and ([.questions[].id] | index("target_disk") != null)
  and ([.questions[].id] | index("confirmed") != null)
' "${QUESTIONS}" >/dev/null

DESKTOP_ENTRY="${AUZIX_ROOT}/System/Compatibility/usr/share/applications/auzix-installer.desktop"
grep -Fx 'Exec=/System/Tools/launch-auzix-installer' "${DESKTOP_ENTRY}" >/dev/null
grep -Fx 'Terminal=false' "${DESKTOP_ENTRY}" >/dev/null
test -L "${AUZIX_ROOT}/System/Tools/launch-auzix-installer"
installer_current="$(readlink "${AUZIX_ROOT}/Programs/AuzixInstaller/current")"
grep -F '/System/Tools/auzix-installer-gui "$@"' \
  "${AUZIX_ROOT}${installer_current}/Commands/launch-auzix-installer" >/dev/null

run_package_setup tui >/dev/null
cat >"${WORK_DIR}/expected-package.log" <<'EOF'
refresh
list available
install Gnumeric
EOF
cmp "${WORK_DIR}/expected-package.log" "${WORK_DIR}/package.log"
grep -F 'sudo") .. " -n"' "${PACKAGE_SETUP_LUA}" >/dev/null

PACKAGE_DESKTOP_ENTRY="${AUZIX_ROOT}/System/Compatibility/usr/share/applications/auzix-package-setup.desktop"
grep -Fx 'Exec=/System/Tools/auzix-package-setup' "${PACKAGE_DESKTOP_ENTRY}" >/dev/null
grep -Fx 'Terminal=true' "${PACKAGE_DESKTOP_ENTRY}" >/dev/null

# The finalizer and install handoff tools are generated by the later
# live-tools stage. Their integration is validated after that stage.

echo "AuziX installer tests: PASS"
