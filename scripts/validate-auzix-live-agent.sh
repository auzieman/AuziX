#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
OS_SOURCE_CONTRACT="${ROOT_DIR}/packages/auzix-os.source.json"
AGENT="${AUZIX_ROOT}/System/Tools/auzix-live-agent"
SEQUENCE="${AUZIX_ROOT}/System/Boot/StartSequence"
FINALIZER="${AUZIX_ROOT}/System/Tools/finalize-installed-root"
INSTALL_PACKAGE="${AUZIX_ROOT}/System/Tools/auzix-install-package"
INSTALL_DISK="${AUZIX_ROOT}/System/Tools/auzix-install-disk"
INSTALL_PREFLIGHT="${AUZIX_ROOT}/System/Tools/auzix-existing-installer-preflight"
PATH_CONTRACT="${AUZIX_ROOT}/System/Settings/auzix-paths.sh"
ENVIRONMENT="${AUZIX_ROOT}/System/Settings/environment.sh"
START_E="${AUZIX_ROOT}/System/Tools/start-e"
START_E_SESSION="${AUZIX_ROOT}/System/Tools/start-enlightenment-session"
LIGHTDM_WRAPPER="${AUZIX_ROOT}/System/Tools/lightdm-session-wrapper"
LIGHTDM_SESSION="${AUZIX_ROOT}/System/Tools/lightdm-auzix-session"

fail() { printf '[auzix-live-agent] FAIL: %s\n' "$*" >&2; exit 1; }

root_path() {
  local path="$1"
  local resolved target
  resolved="${AUZIX_ROOT}${path}"
  if [[ -L "${resolved}" ]]; then
    target="$(readlink "${resolved}")"
    case "${target}" in
      /System/*|/Programs/*|/Services/*|/Users/*|/Work/*|/Network/*)
        resolved="${AUZIX_ROOT}${target}"
        ;;
      *)
        resolved="$(dirname "${resolved}")/${target}"
        ;;
    esac
  fi
  printf '%s\n' "${resolved}"
}

MIDORI_PROGRAM="$(root_path /Programs/Midori/current)"
PARTED_PROGRAM="$(root_path /Programs/Parted/current)"
INSTALLER_EFL_PROGRAM="$(root_path /Programs/AuzixInstallerEfl/current)"
INSTALLER_EFL_SOURCE="${INSTALLER_EFL_PROGRAM}/Resources/auzix-installer-efl.c"
PACKAGE_MANAGER_EFL_PROGRAM="$(root_path /Programs/AuzixPackageManagerEfl/current)"
PACKAGE_MANAGER_EFL_SOURCE="${PACKAGE_MANAGER_EFL_PROGRAM}/Resources/auzix-package-manager-efl.c"

if [[ -x "${ROOT_DIR}/scripts/validate-auzix-os-source-contract.sh" ]]; then
  "${ROOT_DIR}/scripts/validate-auzix-os-source-contract.sh" "${OS_SOURCE_CONTRACT}" "${AUZIX_ROOT}" >/dev/null ||
    fail "OS source contract validation failed"
fi

[[ -x "${AGENT}" ]] || fail "missing executable ${AGENT}"
[[ -x "${SEQUENCE}" ]] || fail "missing executable ${SEQUENCE}"
[[ -x "${FINALIZER}" ]] || fail "missing executable ${FINALIZER}"
[[ -x "${INSTALL_PACKAGE}" ]] || fail "missing executable ${INSTALL_PACKAGE}"
[[ -x "${INSTALL_DISK}" ]] || fail "missing executable ${INSTALL_DISK}"
[[ -x "${INSTALL_PREFLIGHT}" ]] || fail "missing executable ${INSTALL_PREFLIGHT}"
[[ -x "${PARTED_PROGRAM}/Commands/parted" ]] || fail "missing Parted command-suite parted"
[[ -x "${PARTED_PROGRAM}/Commands/partprobe" ]] || fail "missing Parted command-suite partprobe"
[[ -r "${PATH_CONTRACT}" ]] || fail "missing canonical bootstrap path contract ${PATH_CONTRACT}"
[[ -r "${ENVIRONMENT}" ]] || fail "missing interactive environment shim ${ENVIRONMENT}"
grep -Fq '. /System/Settings/auzix-paths.sh' "${ENVIRONMENT}" || fail "environment.sh does not source canonical AUZiX paths"
grep -Fq 'AUZIX_COMPAT_USR' "${PATH_CONTRACT}" || fail "path contract lacks AUZiX compatibility root definitions"
grep -Fq 'LD_LIBRARY_PATH=' "${PATH_CONTRACT}" || fail "path contract lacks canonical library path"
grep -Fq 'XDG_DATA_DIRS=' "${PATH_CONTRACT}" || fail "path contract lacks canonical XDG data path"
grep -Fq 'E_PREFIX=' "${PATH_CONTRACT}" || fail "path contract lacks Enlightenment prefix"
grep -Fq 'GCONV_PATH=' "${PATH_CONTRACT}" || fail "path contract lacks glibc conversion path"
grep -Fq 'SSL_CERT_DIR="${SSL_CERT_DIR:-/System/Compatibility/etc/ssl/certs}"' "${PATH_CONTRACT}" || fail "path contract lacks canonical AUZiX CA cert dir"
grep -Fq 'SSL_CERT_FILE="${SSL_CERT_FILE:-/System/Compatibility/etc/ssl/certs/ca-certificates.crt}"' "${PATH_CONTRACT}" || fail "path contract lacks canonical AUZiX CA bundle"
[[ -s "${AUZIX_ROOT}/System/Compatibility/etc/ssl/certs/ca-certificates.crt" ]] || fail "canonical AUZiX CA bundle is missing"
[[ -e "${AUZIX_ROOT}/System/Settings/ssl" || -L "${AUZIX_ROOT}/System/Settings/ssl" ]] ||
  fail "/System/Settings/ssl alias for hardwired /etc/ssl callers is missing"
settings_ssl_target="$(readlink "${AUZIX_ROOT}/System/Settings/ssl" 2>/dev/null || true)"
if [[ "${settings_ssl_target}" == /System/* ]]; then
  [[ -s "${AUZIX_ROOT}${settings_ssl_target}/certs/ca-certificates.crt" ]] ||
    fail "/System/Settings/ssl AUZiX absolute alias does not resolve inside staged root"
else
  [[ -s "${AUZIX_ROOT}/System/Settings/ssl/certs/ca-certificates.crt" ]] || fail "/System/Settings/ssl CA alias does not resolve"
fi
for script in "${SEQUENCE}" "${START_E}" "${START_E_SESSION}" "${LIGHTDM_WRAPPER}" "${LIGHTDM_SESSION}"; do
  [[ -e "${script}" ]] || continue
  grep -Fq '/System/Settings/auzix-paths.sh' "${script}" || fail "${script#${AUZIX_ROOT}} does not source canonical AUZiX paths"
done
grep -Fq 'AUZIX_STAGE_E_CONFIG:-0' "${SEQUENCE}" && fail "StartSequence disables E config staging by default"
for script in "${SEQUENCE}" "${START_E}" "${START_E_SESSION}" "${LIGHTDM_WRAPPER}" "${LIGHTDM_SESSION}"; do
  [[ -e "${script}" ]] || continue
  grep -Fq 'mv "${module_root}/${module}"' "${script}" && fail "${script#${AUZIX_ROOT}} physically moves Enlightenment module payloads"
  grep -Fq 'mv "${wizard_dir}"' "${script}" && fail "${script#${AUZIX_ROOT}} physically moves the Enlightenment wizard module"
  grep -Fq 'mv "/System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/modules/${module}"' "${script}" &&
    fail "${script#${AUZIX_ROOT}} physically moves Enlightenment module payloads"
done
[[ -s "${AUZIX_ROOT}/Users/auzix/.e/e/config/profile.cfg" ]] || fail "live auzix user lacks preseeded Enlightenment profile"
[[ -s "${AUZIX_ROOT}/Users/auzix/.e/e/config/standard/e.cfg" ]] || fail "live auzix user lacks preseeded standard Enlightenment config"
[[ -d "${AUZIX_ROOT}/Users/auzix/.elementary/config" ]] || fail "live auzix user lacks preseeded Elementary config"
[[ ! -e "${AUZIX_ROOT}/Users/auzix/.e/e/config/standard/module.wizard.cfg" ]] || fail "live profile still asks for first-run wizard"
[[ -s "${AUZIX_ROOT}/System/Compatibility/usr/share/enlightenment/data/backgrounds/Foggy-Trees.edj" ]] ||
  fail "Foggy Trees background is missing from the Enlightenment background catalog"
if command -v eet >/dev/null 2>&1; then
  e_dump="$(mktemp)"
  if eet -d "${AUZIX_ROOT}/Users/auzix/.e/e/config/standard/e.cfg" config "${e_dump}" 2>/dev/null; then
    grep -Fq 'value "desktop_default_background" string: "/System/Compatibility/usr/share/enlightenment/data/backgrounds/Foggy-Trees.edj";' "${e_dump}" ||
      fail "live standard E profile does not select Foggy Trees"
  fi
  rm -f "${e_dump}"
fi
if [[ -s "${AUZIX_ROOT}/Users/auzix/.config/autostart/auzix-installer.desktop" ]]; then
  grep -Fq 'Hidden=false' "${AUZIX_ROOT}/Users/auzix/.config/autostart/auzix-installer.desktop" ||
    fail "installer autostart entry is hidden"
  grep -Fq 'X-GNOME-Autostart-enabled=true' "${AUZIX_ROOT}/Users/auzix/.config/autostart/auzix-installer.desktop" ||
    fail "installer autostart entry is disabled"
else
  fail "missing live installer autostart entry"
fi
if [[ -s "${AUZIX_ROOT}/Users/auzix/.config/autostart/auzix-browser.desktop" ]]; then
  grep -Fq '/System/Tools/launch-auzix-browser' "${AUZIX_ROOT}/Users/auzix/.config/autostart/auzix-browser.desktop" ||
    fail "browser autostart does not use the AUZiX browser launcher"
else
  fail "missing live browser autostart entry"
fi
[[ -x "${AUZIX_ROOT}/System/Tools/launch-auzix-browser" ]] || fail "missing live browser launcher"
[[ -s "${AUZIX_ROOT}/Users/auzix/.e/e/applications/startup/.order" ]] ||
  fail "missing native Enlightenment startup app order"
grep -Fxq 'auzix-installer.desktop' "${AUZIX_ROOT}/Users/auzix/.e/e/applications/startup/.order" ||
  fail "native Enlightenment startup omits installer"
grep -Fxq 'auzix-browser.desktop' "${AUZIX_ROOT}/Users/auzix/.e/e/applications/startup/.order" ||
  fail "native Enlightenment startup omits browser"
grep -Fq '/System/Tools/launch-auzix-installer --autostart' "${AUZIX_ROOT}/Users/auzix/.e/e/applications/startup/auzix-installer.desktop" ||
  fail "native Enlightenment installer startup does not use AUZiX launcher"
grep -Fq '/System/Tools/launch-auzix-browser' "${AUZIX_ROOT}/Users/auzix/.e/e/applications/startup/auzix-browser.desktop" ||
  fail "native Enlightenment browser startup does not use AUZiX launcher"
[[ -s "${AUZIX_ROOT}/System/Settings/browser/midori-start-pages" ]] || fail "Midori start pages are missing"
grep -Fq 'https://auzietek.com' "${AUZIX_ROOT}/System/Settings/browser/midori-start-pages" ||
  fail "Midori start pages omit auzietek.com"
[[ -s "${MIDORI_PROGRAM}/Resources/midori/distribution/policies.json" ]] ||
  fail "Midori browser-native policy file is missing"
grep -Fq '"ImportEnterpriseRoots": true' "${MIDORI_PROGRAM}/Resources/midori/distribution/policies.json" ||
  fail "Midori policy does not import enterprise/system roots"
[[ -s "${MIDORI_PROGRAM}/Resources/midori/defaults/pref/auzix-cert-policy.js" ]] ||
  fail "Midori AUZiX certificate preference file is missing"
grep -Fq 'security.enterprise_roots.enabled' "${MIDORI_PROGRAM}/Resources/midori/defaults/pref/auzix-cert-policy.js" ||
  fail "Midori AUZiX certificate preferences omit enterprise roots"
[[ -s "${AUZIX_ROOT}/System/Settings/browser/midori-default-profile/user.js" ]] ||
  fail "Midori default AUZiX profile preferences are missing"
grep -Fq 'NSS_DEFAULT_DB_TYPE' "${MIDORI_PROGRAM}/Commands/midori" ||
  fail "Midori launcher does not set NSS database mode"
grep -Fq 'set -- --profile "${HOME}/.midori" "$@"' "${MIDORI_PROGRAM}/Commands/midori" ||
  fail "Midori launcher does not force the AUZiX NSS/default profile"
grep -Fq 'auzix-live-agent collect boot' "${SEQUENCE}" || fail "StartSequence does not collect a boot receipt"
grep -Fq 'opens no listener' "${AGENT}" || fail "agent safety contract missing"
grep -Fq 'https://example.com' "${AGENT}" || fail "agent lacks HTTPS validation probe"
grep -Fq 'command -v curl' "${AGENT}" || fail "agent does not prefer the packaged curl probe"
grep -Fq 'finalized-installed-root=' "${FINALIZER}" || fail "installer finalizer marker is missing"
grep -Fq '/Users/auzix/.midori' "${FINALIZER}" || fail "installer finalizer omits Midori state"
grep -Fq '/Programs/Sudo/host/Commands/sudo' "${FINALIZER}" || fail "installer finalizer omits sudo"
grep -Fq '/System/Compatibility/usr/lib/xorg/Xorg.wrap' "${FINALIZER}" || fail "installer finalizer omits Xorg wrapper"
grep -Fq 'normalize_target_symlinks' "${FINALIZER}" || fail "installer finalizer does not normalize alternate-target symlinks"
grep -Fq 'ensure_program_current_links' "${FINALIZER}" || fail "installer finalizer does not promote missing /Programs/*/current links"
grep -Fq 'disable_live_installer_autostart' "${FINALIZER}" || fail "installer finalizer does not strip live-only installer autostart"
grep -Fq 'link_source="${source_path#${target_prefix}}"' "${FINALIZER}" ||
  fail "installer finalizer does not create root-internal links for alternate targets"
grep -Fq '${target_root%/}/System/Tools/finalize-installed-root" "${target_root}"' "${INSTALL_PACKAGE}" || fail "package install handoff omits finalizer"
[[ -x "${AUZIX_ROOT}/System/Tools/auzix-install-root-from-repo-profile" ]] ||
  fail "live root omits package-profile disk installer"
grep -Fq 'auzix-install-root-from-repo-profile' "${INSTALL_DISK}" ||
  fail "disk installer does not delegate --profile installs to package-profile backend"
grep -Fq '/Work/InstallTarget/System/Tools/finalize-installed-root /Work/InstallTarget' "${INSTALL_DISK}" || fail "disk install handoff omits finalizer"
grep -Fq 'AUZIX_ALLOW_EXT2_FALLBACK' "${INSTALL_DISK}" || fail "disk install allows ext2 fallback without explicit guard"
grep -Fq 'INSTALL_STAGE step=' "${INSTALL_DISK}" || fail "disk installer does not emit machine-readable progress stages"
grep -Fq 'install_stage 11' "${AUZIX_ROOT}/System/Tools/auzix-install-root-from-repo-profile" ||
  fail "package-profile installer does not emit full progress stages"
grep -Fq 'INSTALL_DONE root=' "${INSTALL_DISK}" || fail "disk installer does not emit machine-readable completion"
grep -Fq -- '--repo)' "${INSTALL_DISK}" || fail "disk installer does not accept EFL repository argument"
grep -Fq -- '--profile)' "${INSTALL_DISK}" || fail "disk installer does not accept EFL profile argument"
grep -Fq 'RUN_INSTALL is not 1; preflight only' "${INSTALL_PREFLIGHT}" || fail "installer preflight is not safe by default"
grep -Fq 'fstab uses ext4 root' "${INSTALL_PREFLIGHT}" || fail "installer preflight lacks installed ext4 sanity gate"
grep -Fq 'mount-prefixed symlink' "${INSTALL_PREFLIGHT}" ||
  fail "installer preflight does not reject target mount-prefixed symlinks"
grep -Fq 'installed shell link is root-internal' "${INSTALL_PREFLIGHT}" ||
  fail "installer preflight does not assert root-internal shell link"
[[ -d "${AUZIX_ROOT}/System/Logs/installer" ]] || fail "installer log directory is missing"
installer_log_mode="$(stat -c %a "${AUZIX_ROOT}/System/Logs/installer" 2>/dev/null || true)"
[[ "${installer_log_mode}" == "775" || "${installer_log_mode}" == "0775" ]] ||
  fail "installer log directory is not writable by the live desktop group"
grep -Fq 'sudo -n sh -c' "${INSTALLER_EFL_SOURCE}" ||
  fail "EFL installer preflight does not use sudo for privileged checks"
grep -Fq 'mkdir -p /System/Logs/installer' "${INSTALLER_EFL_SOURCE}" ||
  fail "EFL installer preflight does not prepare installer logs"
grep -Fq 'auzix-existing-installer-preflight' "${INSTALLER_EFL_SOURCE}" ||
  fail "EFL installer omits disk preflight"
grep -Fq 'auzix-install-root-from-repo-profile --preflight' "${INSTALLER_EFL_SOURCE}" ||
  fail "EFL installer omits signed APK repository preflight"
grep -Fq 'auzix-install-root-from-repo-profile --force --repo' "${INSTALLER_EFL_SOURCE}" ||
  fail "EFL installer install action does not invoke the APK backend directly"
grep -Fq 'elm_radio_value_set(whole, 1)' "${INSTALLER_EFL_SOURCE}" ||
  fail "EFL installer no longer defaults to the AUZiX split storage intent"
grep -Fq 'user-work-programs' "${INSTALLER_EFL_SOURCE}" ||
  fail "EFL installer lacks default split storage contract"
grep -Fq 'Continue to install options' "${INSTALLER_EFL_SOURCE}" ||
  fail "EFL installer validated-plan popup lacks a continue/close action"
grep -Fq 'INSTALL_STAGE ' "${INSTALLER_EFL_SOURCE}" ||
  fail "EFL installer progress parser does not consume disk install stages"
[[ -r "${PACKAGE_MANAGER_EFL_SOURCE}" ]] || fail "missing package-manager EFL source"
grep -Fq 'sudo -n /System/Tools/auzix-pkg refresh' "${PACKAGE_MANAGER_EFL_SOURCE}" ||
  fail "EFL package manager refresh does not use sudo"
grep -Fq 'repo_entry' "${PACKAGE_MANAGER_EFL_SOURCE}" ||
  fail "EFL package manager lacks repository selector"
grep -Fq 'https://auzix.auzietek.com/repo' "${PACKAGE_MANAGER_EFL_SOURCE}" ||
  fail "EFL package manager lacks public AUZiX repository toggle"
printf '[auzix-live-agent] PASS: diagnostic agent is wired into the live boot path\n'
