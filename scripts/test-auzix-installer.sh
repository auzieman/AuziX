#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
LUA_CURRENT="$(basename "$(readlink "${AUZIX_ROOT}/Programs/Lua/current")")"
INSTALLER_CURRENT="$(basename "$(readlink "${AUZIX_ROOT}/Programs/AuzixInstaller/current")")"
LUA_REAL="${AUZIX_ROOT}/Programs/Lua/${LUA_CURRENT}/Commands/lua.real"
LUA_LIBS="${AUZIX_ROOT}/Programs/Lua/${LUA_CURRENT}/Libraries"
INSTALLER_LUA="${AUZIX_ROOT}/Programs/AuzixInstaller/${INSTALLER_CURRENT}/Resources/auzix-installer.lua"
DEFAULT_PLAN="${AUZIX_ROOT}/System/Settings/installer/plans/default.json"
QUESTIONS="${AUZIX_ROOT}/System/Settings/installer/questions.json"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

for path in "${LUA_REAL}" "${INSTALLER_LUA}" "${DEFAULT_PLAN}"; do
  [[ -e "${path}" ]] || {
    printf 'Installer test prerequisite is missing: %s\n' "${path}" >&2
    exit 1
  }
done

run_installer() {
  LD_LIBRARY_PATH="${LUA_LIBS}:${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu:${AUZIX_ROOT}/System/Compatibility/lib64" \
    AUZIX_ROOT="${AUZIX_ROOT}" \
    AUZIX_JQ="$(command -v jq)" \
    AUZIX_INSTALL_EXECUTOR="${WORK_DIR}/fake-install-disk" \
    "${LUA_REAL}" "${INSTALLER_LUA}" "$@"
}

run_tui_installer() {
  LD_LIBRARY_PATH="${LUA_LIBS}:${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu:${AUZIX_ROOT}/System/Compatibility/lib64" \
    AUZIX_ROOT="${AUZIX_ROOT}" \
    AUZIX_JQ="$(command -v jq)" \
    AUZIX_DIALOG="${WORK_DIR}/fake-dialog" \
    AUZIX_INSTALLER_DISKS="/dev/vdz,/dev/vdy" \
    AUZIX_INSTALL_EXECUTOR="${WORK_DIR}/fake-install-disk" \
    "${LUA_REAL}" "${INSTALLER_LUA}" "$@"
}

cat >"${WORK_DIR}/fake-install-disk" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"${AUZIX_TEST_EXECUTOR_LOG}"
SCRIPT
chmod 0755 "${WORK_DIR}/fake-install-disk"

cat >"${WORK_DIR}/fake-dialog" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
case " $* " in
  *" Installation disk "*) printf '%s' /dev/vdz >&2 ;;
  *" Boot method "*) printf '%s' iso >&2 ;;
  *" Hostname "*) printf '%s' installer-test >&2 ;;
  *" --yesno "*) exit "${AUZIX_TEST_DIALOG_CONFIRM:-0}" ;;
  *) printf 'Unexpected dialog invocation: %s\n' "$*" >&2; exit 2 ;;
esac
SCRIPT
chmod 0755 "${WORK_DIR}/fake-dialog"

run_installer validate "${DEFAULT_PLAN}" >/dev/null

if run_installer run "${DEFAULT_PLAN}" >/dev/null 2>&1; then
  echo "Unconfirmed plan was executed." >&2
  exit 1
fi

jq '.target.disk = "not-a-device"' "${DEFAULT_PLAN}" >"${WORK_DIR}/invalid.json"
if run_installer validate "${WORK_DIR}/invalid.json" >/dev/null 2>&1; then
  echo "Invalid disk path passed validation." >&2
  exit 1
fi

jq '.unexpected = "ignored"' "${DEFAULT_PLAN}" >"${WORK_DIR}/extra-field.json"
if run_installer validate "${WORK_DIR}/extra-field.json" >/dev/null 2>&1; then
  echo "Unknown install plan field passed validation." >&2
  exit 1
fi

jq '
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

run_tui_installer tui-plan "${WORK_DIR}/tui-plan.json" >/dev/null
jq -e '
  .target.disk == "/dev/vdz"
  and .bootloader.mode == "iso"
  and .identity.hostname == "installer-test"
  and .execution.confirmed == false
  and .frontend == "tui"
' "${WORK_DIR}/tui-plan.json" >/dev/null
[[ ! -e "${WORK_DIR}/executor.log" ]] || rm -f "${WORK_DIR}/executor.log"

run_tui_installer tui "${WORK_DIR}/confirmed-tui-plan.json" >/dev/null
jq -e '.execution.confirmed == true' "${WORK_DIR}/confirmed-tui-plan.json" >/dev/null
cmp "${WORK_DIR}/expected.log" "${WORK_DIR}/executor.log"

rm -f "${WORK_DIR}/executor.log"
if AUZIX_TEST_DIALOG_CONFIRM=1 \
  run_tui_installer tui "${WORK_DIR}/cancelled-tui-plan.json" >/dev/null 2>&1; then
  echo "Cancelled TUI plan was executed." >&2
  exit 1
fi
jq -e '.execution.confirmed == false' "${WORK_DIR}/cancelled-tui-plan.json" >/dev/null
[[ ! -e "${WORK_DIR}/executor.log" ]]

jq -e '
  .format == "auzix-installer-questions-v1"
  and ([.questions[].id] | index("target_disk") != null)
  and ([.questions[].id] | index("confirmed") != null)
' "${QUESTIONS}" >/dev/null

DESKTOP_ENTRY="${AUZIX_ROOT}/System/Compatibility/usr/share/applications/auzix-installer.desktop"
grep -Fx 'Exec=/System/Tools/auzix-installer-gui' "${DESKTOP_ENTRY}" >/dev/null
grep -Fx 'Terminal=true' "${DESKTOP_ENTRY}" >/dev/null

echo "AuziX installer tests: PASS"
