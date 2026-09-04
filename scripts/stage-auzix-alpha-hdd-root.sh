#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KNOWN_GOOD_HDD_IMAGE="${KNOWN_GOOD_HDD_IMAGE:-/var/lib/auzix-build/hdd-images/desktop-main-20260828-r9/auzix-desktop-main-20260828-r9.img}"
STRICT_REFERENCE_ROOT="${AUZIX_STRICT_REFERENCE_ROOT:-/root/auzix-work/AuziX/out/auzix-strict/AuzixRoot}"
IMAGE="${1:?usage: stage-auzix-alpha-hdd-root.sh IMAGE ANCHOR_ISO OUTPUT_ROOT}"
ANCHOR_ISO="${2:?usage: stage-auzix-alpha-hdd-root.sh IMAGE ANCHOR_ISO OUTPUT_ROOT}"
OUTPUT_ROOT="${3:?usage: stage-auzix-alpha-hdd-root.sh IMAGE ANCHOR_ISO OUTPUT_ROOT}"
EXPECTED_ANCHOR_SHA256="${AUZIX_ALPHA_ANCHOR_SHA256:-dbc37d309059b70cc39e37b7a5e0be7d27dae770654bf3ccf7ddf7d142c25cb6}"
KERNEL_RELEASE="${AUZIX_ALPHA_KERNEL_RELEASE:-6.1.0-48-amd64}"
XORG_HOST_RUNTIME_LIBRARIES=(
  libaudit.so.1 libbrotlicommon.so.1 libbrotlidec.so.1 libbsd.so.0
  libbz2.so.1.0 libcap-ng.so.0 libcap.so.2 libdbus-1.so.3 libdrm.so.2
  libfontenc.so.1 libfreetype.so.6 libgcrypt.so.20 libgpg-error.so.0
  liblz4.so.1 liblzma.so.5 libmd.so.0 libpciaccess.so.0 libpcre2-8.so.0
  libpixman-1.so.0 libpng16.so.16 libselinux.so.1 libsystemd.so.0
  libudev.so.1 libunwind-ptrace.so.0 libunwind-x86_64.so.8
  libunwind.so.8 libX11.so.6 libXau.so.6 libxcb.so.1 libxcvt.so.0
  libXdmcp.so.6 libXfont2.so.2 libxkbfile.so.1
  libxshmfence.so.1 libz.so.1 libzstd.so.1
)

fail() { printf 'alpha-hdd-stage: %s\n' "$*" >&2; exit 1; }
copy_absent_tree() {
  local source="$1" destination="$2" relative
  mkdir -p "$destination"
  while IFS= read -r -d '' relative; do
    [[ -d "$destination/$relative" ]] || mkdir -p "$destination/$relative"
  done < <(cd "$source" && find . -type d -print0)
  while IFS= read -r -d '' relative; do
    if [[ ! -e "$destination/$relative" && ! -L "$destination/$relative" ]]; then
      cp -a "$source/$relative" "$destination/$relative"
    fi
  done < <(cd "$source" && find . \( -type f -o -type l \) -print0)
}
overlay_current_program_tree() {
  local package="$1" relative="$2" destination="$3" current target source
  current="${OUTPUT_ROOT}/Programs/${package}/current"
  [[ -L "${current}" ]] || fail "current package link is absent: ${package}"
  target="$(readlink "${current}")"
  if [[ "${target}" = /* ]]; then
    source="${OUTPUT_ROOT}${target}/RootFS/${relative}"
  else
    source="$(dirname "${current}")/${target}/RootFS/${relative}"
  fi
  [[ -d "${source}" ]] || fail "current package tree is absent: ${package}:${relative}"
  mkdir -p "${destination}"
  cp -a "${source}/." "${destination}/"
}
for command_name in docker sha256sum tar xorriso unsquashfs; do
  command -v "${command_name}" >/dev/null || fail "missing command: ${command_name}"
done
test -f "${ANCHOR_ISO}" || fail "anchor ISO not found: ${ANCHOR_ISO}"
test ! -e "${OUTPUT_ROOT}" || fail "output already exists: ${OUTPUT_ROOT}"

actual_sha256="$(sha256sum "${ANCHOR_ISO}" | awk '{print $1}')"
test "${actual_sha256}" = "${EXPECTED_ANCHOR_SHA256}" ||
  fail "anchor checksum mismatch: ${actual_sha256}"
docker image inspect "${IMAGE}" >/dev/null || fail "image not found: ${IMAGE}"

mkdir -p "${OUTPUT_ROOT}"
work="$(mktemp -d "${OUTPUT_ROOT}.stage.XXXXXX")"
container="auzix-alpha-hdd-stage-$$"
cleanup() {
  if [[ -n "${known_good_mount:-}" ]]; then
    umount "${known_good_mount}" 2>/dev/null || true
    rmdir "${known_good_mount}" 2>/dev/null || true
  fi
  if [[ -n "${known_good_loop:-}" ]]; then
    losetup -d "${known_good_loop}" 2>/dev/null || true
  fi
  docker rm -f "${container}" >/dev/null 2>&1 || true
  rm -rf "${work}"
}
trap cleanup EXIT INT TERM

# Start the image so its runtime entrypoint materializes the real /etc account
# databases required by shadow-utils, then export that exact validated state.
docker create --name "${container}" "${IMAGE}" >/dev/null
docker start "${container}" >/dev/null
docker export "${container}" | tar -xpf - -C "${OUTPUT_ROOT}"

xorriso -osirrox on -indev "${ANCHOR_ISO}" \
  -extract /boot/vmlinuz "${work}/vmlinuz" \
  -extract /live/auzix-root.squashfs "${work}/root.squashfs" >/dev/null 2>&1
unsquashfs -f -d "${work}/anchor-root" "${work}/root.squashfs" \
  System/Boot "System/Drivers/${KERNEL_RELEASE}" \
  System/Drivers/Xorg System/Settings/X11/xkb \
  System/Settings/X11/Xwrapper.config \
  Programs/Xorg/host System/Compatibility/usr/lib/xorg \
  System/Compatibility/usr/lib/x86_64-linux-gnu \
  System/Compatibility/usr/bin/xkbcomp \
  System/Compatibility/usr/share/dbus-1 \
  System/Compatibility/usr/share/icons \
  System/Compatibility/usr/share/X11/xkb \
  System/Compatibility/usr/share/elementary \
  System/Compatibility/usr/share/enlightenment \
  System/Compatibility/etc/X11/Xwrapper.config \
  System/Compatibility/lib/x86_64-linux-gnu \
  System/Tools/finalize-installed-root System/Tools/auzix-hw-detect \
  System/Tools/auzix-live-agent System/Tools/auzix-load-module \
  System/Tools/generate-lightdm-config System/Tools/lightdm-session-wrapper \
  System/Tools/prepare-livecd-state System/Tools/repair-e-state \
  System/Tools/reset-e-theme-state System/Tools/start-e \
  System/Tools/start-e-supervisor System/Tools/start-enlightenment-session \
  System/Tools/start-gui-stage System/Tools/start-lightdm-stage \
  Users/auzix/.e Users/auzix/.elementary Users/auzix/.config \
  Users/auzix/.local >/dev/null

mkdir -p "${OUTPUT_ROOT}/boot" "${OUTPUT_ROOT}/System/Drivers" \
  "${OUTPUT_ROOT}/System/Tools"
cp -a "${work}/anchor-root/System/Boot" "${OUTPUT_ROOT}/System/"
cp -a "${work}/anchor-root/System/Drivers/${KERNEL_RELEASE}" \
  "${OUTPUT_ROOT}/System/Drivers/"
cp -a "${work}/anchor-root/System/Drivers/Xorg" \
  "${OUTPUT_ROOT}/System/Drivers/"
mkdir -p "${OUTPUT_ROOT}/System/Settings/X11" \
  "${OUTPUT_ROOT}/System/Compatibility/etc/X11" \
  "${OUTPUT_ROOT}/System/Compatibility/lib/x86_64-linux-gnu" \
  "${OUTPUT_ROOT}/System/Compatibility/usr/lib" \
  "${OUTPUT_ROOT}/System/Compatibility/usr/bin" \
  "${OUTPUT_ROOT}/System/Compatibility/usr/share/X11" \
  "${OUTPUT_ROOT}/Programs/Xorg" "${OUTPUT_ROOT}/etc/X11"
cp -a "${work}/anchor-root/System/Settings/X11/xkb" \
  "${OUTPUT_ROOT}/System/Settings/X11/"
cp -a "${work}/anchor-root/System/Settings/X11/Xwrapper.config" \
  "${OUTPUT_ROOT}/System/Settings/X11/"
cp -a "${work}/anchor-root/System/Compatibility/etc/X11/Xwrapper.config" \
  "${OUTPUT_ROOT}/System/Compatibility/etc/X11/"
cp -a "${work}/anchor-root/System/Compatibility/etc/X11/Xwrapper.config" \
  "${OUTPUT_ROOT}/etc/X11/"
cp -a "${work}/anchor-root/System/Compatibility/usr/lib/xorg" \
  "${OUTPUT_ROOT}/System/Compatibility/usr/lib/"
cp -a "${work}/anchor-root/System/Compatibility/usr/bin/xkbcomp" \
  "${OUTPUT_ROOT}/System/Compatibility/usr/bin/"
cp -a "${work}/anchor-root/System/Compatibility/usr/share/X11/xkb" \
  "${OUTPUT_ROOT}/System/Compatibility/usr/share/X11/"

# The APK workstation is authoritative. Fill only absent graphical host-spine
# payloads (EFL engines/modules/data and their established runtime libraries)
# from the proven live root; never replace an existing APK-owned path here.
copy_absent_tree \
  "${work}/anchor-root/System/Compatibility/lib/x86_64-linux-gnu" \
  "${OUTPUT_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
copy_absent_tree \
  "${work}/anchor-root/System/Compatibility/usr/lib/x86_64-linux-gnu" \
  "${OUTPUT_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu"
mkdir -p "${OUTPUT_ROOT}/System/Compatibility/usr/share"
mkdir -p "${OUTPUT_ROOT}/System/Compatibility/usr/share/icons"
cp -a "${work}/anchor-root/System/Compatibility/usr/share/icons/." \
  "${OUTPUT_ROOT}/System/Compatibility/usr/share/icons/"
mkdir -p "${OUTPUT_ROOT}/System/Compatibility/usr/share/dbus-1"
for dbus_config in system.conf session.conf; do
  install -m 0644 \
    "${work}/anchor-root/System/Compatibility/usr/share/dbus-1/${dbus_config}" \
    "${OUTPUT_ROOT}/System/Compatibility/usr/share/dbus-1/${dbus_config}"
done
for dbus_dir in system.d system-services; do
  if [[ -d "${work}/anchor-root/System/Compatibility/usr/share/dbus-1/${dbus_dir}" &&
        ! -e "${OUTPUT_ROOT}/System/Compatibility/usr/share/dbus-1/${dbus_dir}" ]]; then
    cp -a "${work}/anchor-root/System/Compatibility/usr/share/dbus-1/${dbus_dir}" \
      "${OUTPUT_ROOT}/System/Compatibility/usr/share/dbus-1/"
  fi
done
cp -an "${work}/anchor-root/System/Compatibility/usr/share/elementary" \
  "${work}/anchor-root/System/Compatibility/usr/share/enlightenment" \
  "${OUTPUT_ROOT}/System/Compatibility/usr/share/"

# Executable EFL modules are versioned runtime code, not fallback data.  The
# anchor may fill genuinely absent host-spine paths, but it must never leave its
# v1.26 modules ahead of the APK workstation's v1.28 generation.  Overlay the
# current package-owned trees and remove the stale ABI directories explicitly.
for module_root in evas ecore_evas edje ecore_imf elementary; do
  find "${OUTPUT_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/${module_root}" \
    -type d -name v-1.26 -prune -exec rm -rf {} + 2>/dev/null || true
done
for provider in Libevas1 Libevas1EnginesDrm Libevas1EnginesWayland Libevas1EnginesX; do
  overlay_current_program_tree "${provider}" \
    usr/lib/x86_64-linux-gnu/evas \
    "${OUTPUT_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/evas"
done
overlay_current_program_tree LibecoreEvas1 \
  usr/lib/x86_64-linux-gnu/ecore_evas \
  "${OUTPUT_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/ecore_evas"
for provider in LibedjeBin Libelementary1 Libemotion1; do
  overlay_current_program_tree "${provider}" \
    usr/lib/x86_64-linux-gnu/edje \
    "${OUTPUT_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/edje"
done
overlay_current_program_tree LibecoreImf1 \
  usr/lib/x86_64-linux-gnu/ecore_imf \
  "${OUTPUT_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/ecore_imf"
overlay_current_program_tree Libelementary1 \
  usr/lib/x86_64-linux-gnu/elementary \
  "${OUTPUT_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/elementary"
overlay_current_program_tree Enlightenment \
  usr/lib/x86_64-linux-gnu/enlightenment \
  "${OUTPUT_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment"
for module_root in evas ecore_evas edje ecore_imf elementary; do
  find "${OUTPUT_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/${module_root}" \
    -type f -name '*.so' -exec chmod 0755 {} +
done
for helper in enlightenment_system enlightenment_sys enlightenment_ckpasswd; do
  helper_path="${OUTPUT_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/utils/${helper}"
  [[ ! -e "${helper_path}" ]] || chmod 4755 "${helper_path}"
done
# Xorg-host's privileged wrapper ignores LD_LIBRARY_PATH. Restore its finite,
# proven secure-loader closure, while deliberately leaving libc, libm and the
# dynamic loader under the validated alpha root's ownership.
for library in "${XORG_HOST_RUNTIME_LIBRARIES[@]}"; do
  rm -f "${OUTPUT_ROOT}/System/Compatibility/lib/x86_64-linux-gnu/${library}"
  cp -a "${work}/anchor-root/System/Compatibility/lib/x86_64-linux-gnu/${library}" \
    "${OUTPUT_ROOT}/System/Compatibility/lib/x86_64-linux-gnu/"
done
cp -a "${work}/anchor-root/Programs/Xorg/host" \
  "${OUTPUT_ROOT}/Programs/Xorg/"

# Keep the DBus executable and Libdbus13 private ABI from the same release.
# The older ISO anchor carries a 1.14.10 daemon, while the APK workstation and
# the last proven graphical HDD carry Libdbus13 1.16.2. Restore the matching
# 1.16.2 daemon from that immutable proof image until DBusDaemon is emitted as
# its own APK dependency.
test -f "${KNOWN_GOOD_HDD_IMAGE}"
test -f "${STRICT_REFERENCE_ROOT}/System/Compatibility/lib/x86_64-linux-gnu/libsystemd-shared-257.so"
test -f "${STRICT_REFERENCE_ROOT}/System/Compatibility/usr/lib/udev/rules.d/60-input-id.rules"
test -f "${STRICT_REFERENCE_ROOT}/System/Settings/X11/xorg.conf.d/40-libinput.conf"
known_good_mount="$(mktemp -d)"
known_good_loop="$(losetup --find --show --partscan --read-only "${KNOWN_GOOD_HDD_IMAGE}")"
mount -o ro,noload "${known_good_loop}p1" "${known_good_mount}"
install -m 0755 \
  "${known_good_mount}/Programs/DBus/host/Commands/dbus-daemon" \
  "${OUTPUT_ROOT}/Programs/DBus/host/Commands/dbus-daemon"
umount "${known_good_mount}"
rmdir "${known_good_mount}"
known_good_mount=""
losetup -d "${known_good_loop}"
known_good_loop=""

# The APK udev payload currently exports the daemon without its adjacent
# private library, rules, and hwdb. Reuse the already-built strict-root closure
# so Xorg/libinput receive ID_INPUT_* tags on an installed-system boot.
install -m 0755 \
  "${STRICT_REFERENCE_ROOT}/System/Compatibility/lib/x86_64-linux-gnu/libsystemd-shared-257.so" \
  "${OUTPUT_ROOT}/System/Compatibility/lib/x86_64-linux-gnu/libsystemd-shared-257.so"
mkdir -p "${OUTPUT_ROOT}/System/Compatibility/usr/lib/udev" \
  "${OUTPUT_ROOT}/System/Compatibility/lib/udev"
cp -a "${STRICT_REFERENCE_ROOT}/System/Compatibility/usr/lib/udev/." \
  "${OUTPUT_ROOT}/System/Compatibility/usr/lib/udev/"
cp -a "${STRICT_REFERENCE_ROOT}/System/Compatibility/lib/udev/." \
  "${OUTPUT_ROOT}/System/Compatibility/lib/udev/"
mkdir -p "${OUTPUT_ROOT}/etc/X11/xorg.conf.d" \
  "${OUTPUT_ROOT}/System/Settings/X11/xorg.conf.d"
install -m 0644 \
  "${STRICT_REFERENCE_ROOT}/System/Settings/X11/xorg.conf.d/40-libinput.conf" \
  "${OUTPUT_ROOT}/etc/X11/xorg.conf.d/40-libinput.conf"
install -m 0644 \
  "${STRICT_REFERENCE_ROOT}/System/Settings/X11/xorg.conf.d/40-libinput.conf" \
  "${OUTPUT_ROOT}/System/Settings/X11/xorg.conf.d/40-libinput.conf"
cp -a "${work}/anchor-root/System/Tools/finalize-installed-root" \
  "${OUTPUT_ROOT}/System/Tools/"
for boot_tool in \
  auzix-hw-detect auzix-live-agent auzix-load-module \
  generate-lightdm-config lightdm-session-wrapper prepare-livecd-state \
  repair-e-state reset-e-theme-state start-e start-e-supervisor \
  start-enlightenment-session start-gui-stage start-lightdm-stage; do
  cp -a "${work}/anchor-root/System/Tools/${boot_tool}" \
    "${OUTPUT_ROOT}/System/Tools/"
done
cp -a "${work}/vmlinuz" "${OUTPUT_ROOT}/boot/vmlinuz-${KERNEL_RELEASE}"
cp -a "${OUTPUT_ROOT}/System/Boot/InstalledInit" "${OUTPUT_ROOT}/init"
mkdir -p "${OUTPUT_ROOT}/Users/auzix/.cache"
for profile_path in .e .elementary .config .local; do
  test ! -e "${work}/anchor-root/Users/auzix/${profile_path}" ||
    cp -an "${work}/anchor-root/Users/auzix/${profile_path}" \
      "${OUTPUT_ROOT}/Users/auzix/"
done
# Reapply the committed AUZiX desktop profile after the anchor fills absent
# state.  The anchor is not authoritative for user configuration: dced00a
# locked the packaged profile, Foggy Trees background, module selection, and
# host-state exclusion as the reproducible desktop contract.
AUZIX_DEFAULTS_HOME= \
AUZIX_IMPORT_HOST_E_DEFAULTS=0 \
  "${ROOT_DIR}/scripts/stage-auzix-user-defaults.sh" "${OUTPUT_ROOT}"
chown -R 1000:1000 "${OUTPUT_ROOT}/Users/auzix"

if [[ -n "${AUZIX_ALPHA_AUTHORIZED_KEY_FILE:-}" ]]; then
  test -s "${AUZIX_ALPHA_AUTHORIZED_KEY_FILE}" ||
    fail "authorized key file is absent: ${AUZIX_ALPHA_AUTHORIZED_KEY_FILE}"
  for account_home in Users/root Users/auzix; do
    install -d -m 0700 "${OUTPUT_ROOT}/${account_home}/.ssh"
    install -m 0600 "${AUZIX_ALPHA_AUTHORIZED_KEY_FILE}" \
      "${OUTPUT_ROOT}/${account_home}/.ssh/authorized_keys"
  done
  chown -R 0:0 "${OUTPUT_ROOT}/Users/root/.ssh"
  chown -R 1000:1000 "${OUTPUT_ROOT}/Users/auzix/.ssh"
fi

# Font packages remain owned under /Programs.  Fontconfig's upstream default
# configuration scans /usr/share/fonts, so publish a finite compatibility view
# instead of copying or rediscovering the already-packaged payloads.
mkdir -p "${OUTPUT_ROOT}/System/Compatibility/usr/share/fonts/auzix"
for font_package in FontsDejavuCore FontsDejavuMono FontsOpensymbol FontsUrwBase35; do
  font_root="$(find "${OUTPUT_ROOT}/Programs/${font_package}" -mindepth 3 -maxdepth 5 \
    -type d -path '*/RootFS/usr/share/fonts' -print -quit 2>/dev/null || true)"
  [[ -n "${font_root}" ]] || fail "installed font payload is absent: ${font_package}"
  ln -sfn "/Programs/${font_package}/current/RootFS/usr/share/fonts" \
    "${OUTPUT_ROOT}/System/Compatibility/usr/share/fonts/auzix/${font_package}"
done

# The preserved ISO is a payload anchor, not the owner of the current boot and
# desktop-session contract. Disk boots need a real /run mountpoint, then the
# current generator must refresh PID1, runtime mounts, PTYs, DBus and E state.
if [[ -L "${OUTPUT_ROOT}/run" ]]; then
  unlink "${OUTPUT_ROOT}/run"
fi
mkdir -p "${OUTPUT_ROOT}/run"
ln -sfn /run "${OUTPUT_ROOT}/System/State/run"
mkdir -p "${OUTPUT_ROOT}/System/Settings/acpi/events"
mkdir -p "${OUTPUT_ROOT}/System/State/log"
chmod 0755 "${OUTPUT_ROOT}/run" "${OUTPUT_ROOT}/proc" "${OUTPUT_ROOT}/sys"
"${ROOT_DIR}/scripts/add-auzix-live-tools.sh" "${OUTPUT_ROOT}"

# The exported APK workstation currently carries user-facing accounts but can
# omit adjacent service accounts. Preserve the established IDs used by the
# boot scripts and make sshd's volatile home agree with the runtime contract.
sed -i 's#^sshd:[^:]*:74:74:[^:]*:[^:]*:#sshd:x:74:74:sshd privilege separation:/run/sshd:#' \
  "${OUTPUT_ROOT}/System/Settings/passwd"
grep -q '^messagebus:' "${OUTPUT_ROOT}/System/Settings/passwd" ||
  printf '%s\n' 'messagebus:x:101:101:DBus message bus:/run/dbus:/System/Compatibility/bin/false' \
    >>"${OUTPUT_ROOT}/System/Settings/passwd"
grep -q '^lightdm:' "${OUTPUT_ROOT}/System/Settings/passwd" ||
  printf '%s\n' 'lightdm:x:102:102:LightDM display manager:/System/State/lightdm:/System/Compatibility/bin/false' \
    >>"${OUTPUT_ROOT}/System/Settings/passwd"
grep -q '^messagebus:' "${OUTPUT_ROOT}/System/Settings/group" ||
  printf '%s\n' 'messagebus:x:101:' >>"${OUTPUT_ROOT}/System/Settings/group"
grep -q '^lightdm:' "${OUTPUT_ROOT}/System/Settings/group" ||
  printf '%s\n' 'lightdm:x:102:' >>"${OUTPUT_ROOT}/System/Settings/group"
cp -a "${OUTPUT_ROOT}/System/Settings/passwd" "${OUTPUT_ROOT}/etc/passwd"
cp -a "${OUTPUT_ROOT}/System/Settings/group" "${OUTPUT_ROOT}/etc/group"
# Key-only SSH still requires an account that is not marked locked.  Use an
# invalid password hash (not an empty password) so password authentication
# remains impossible while authorized_keys works for the alpha recovery lane.
sed -i -E 's/^(root|auzix):!:/\1:x:/' "${OUTPUT_ROOT}/System/Settings/shadow"
cp -a "${OUTPUT_ROOT}/System/Settings/shadow" "${OUTPUT_ROOT}/etc/shadow"

# Docker creates a real /etc in exported images.  Recreate the two package and
# trust views that the AUZiX filesystem contract normally publishes there.
rm -rf "${OUTPUT_ROOT}/etc/apk" "${OUTPUT_ROOT}/etc/ssl"
ln -s /System/Settings/apk "${OUTPUT_ROOT}/etc/apk"
ln -s /System/Compatibility/etc/ssl "${OUTPUT_ROOT}/etc/ssl"
# Hardware discovery and xorg.conf.d own the default path. Do not promote the
# old diagnostic monolithic configuration into a portable HDD image.
rm -f "${OUTPUT_ROOT}/System/Settings/X11/xorg.conf" \
  "${OUTPUT_ROOT}/etc/X11/xorg.conf"

# Docker ENV metadata does not survive a filesystem export. Persist the same
# validated AUZiX runtime contract for PID 1 and interactive login shells.
cat >"${OUTPUT_ROOT}/System/Settings/auzix-runtime-env" <<'EOF'
export PATH=/Programs/Midori/current/Commands:/Programs/AbiWord/current/Commands:/Programs/Flatpak/current/Commands:/Programs/LibreOfficeWriter/current/Commands:/Programs/LibreOfficeCalc/current/Commands:/Programs/LibreOfficeImpress/current/Commands:/Programs/Terminology/current/Commands:/Programs/Enlightenment/current/Commands:/Programs/Glances/current/Commands:/Programs/Htop/current/Commands:/Programs/Python313Minimal/current/Commands:/System/Compatibility/bin:/System/Compatibility/usr/bin:/System/Compatibility/sbin:/System/Compatibility/usr/sbin:/Programs/BusyBox/current/Commands
export LD_LIBRARY_PATH=/Libraries:/System/Libraries:/System/Libraries/Runtime/glibc:/Programs/Flatpak/current/Libraries:/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64
export SSL_CERT_DIR=/System/Settings/ssl/certs
export SSL_CERT_FILE=/System/Settings/ssl/certs/ca-certificates.crt
export CURL_CA_BUNDLE=/System/Settings/ssl/certs/ca-certificates.crt
export REQUESTS_CA_BUNDLE=/System/Settings/ssl/certs/ca-certificates.crt
export FONTCONFIG_FILE=/Programs/FontconfigConfig/current/RootFS/etc/fonts/fonts.conf
export PYTHONHOME=/Programs/Libpython313Minimal/current/RootFS/usr
export PYTHONPATH=/Programs/Libpython313Stdlib/current/RootFS/usr/lib/python3.13:/Programs/Libpython313Stdlib/current/RootFS/usr/lib/python3.13/lib-dynload:/Programs/Libpython313Minimal/current/RootFS/usr/lib/python3.13:/Programs/Libpython313Minimal/current/RootFS/usr/lib/python3.13/lib-dynload
export AUZIX_GUI_AUTOSTART=1
EOF
sed -i '/^export PATH$/a\
[ ! -r /System/Settings/auzix-runtime-env ] || . /System/Settings/auzix-runtime-env' \
  "${OUTPUT_ROOT}/System/Boot/StartSequence"
cat >"${OUTPUT_ROOT}/etc/profile" <<'EOF'
[ ! -r /System/Settings/auzix-runtime-env ] || . /System/Settings/auzix-runtime-env
case "$(id -u 2>/dev/null)" in
  0) HOME=/Users/root ;;
  *) HOME="/Users/$(id -un 2>/dev/null || echo auzix)" ;;
esac
export HOME
EOF

# Privileged launchers such as Xorg.wrap intentionally ignore LD_LIBRARY_PATH.
# Publish AUZiX-owned library names in the conventional secure-loader path.
mkdir -p "${OUTPUT_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
for library in "${OUTPUT_ROOT}"/Libraries/*.so*; do
  [[ -e "${library}" || -L "${library}" ]] || continue
  name="${library##*/}"
  compatibility_library="${OUTPUT_ROOT}/System/Compatibility/lib/x86_64-linux-gnu/${name}"
  [[ ! -e "${compatibility_library}" && ! -L "${compatibility_library}" ]] || continue
  ln -sfn "/Libraries/${name}" \
    "${compatibility_library}"
done

# Secure-execution helpers ignore LD_LIBRARY_PATH.  The anchor's glibc 2.36
# compatibility files cannot load current Trixie E/EFL binaries, which require
# GLIBC_2.38+ and are installed with Libc6 2.41.  VM135 established the
# contract: the loader, libc and libm must come from the same active Libc6
# substrate.  Replace these names even when the anchor already populated them.
mkdir -p "${OUTPUT_ROOT}/System/Compatibility/lib64" \
  "${OUTPUT_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
for runtime_name in ld-linux-x86-64.so.2 libc.so.6 libm.so.6; do
  runtime_path="${OUTPUT_ROOT}/Libraries/${runtime_name}"
  if [[ -L "${runtime_path}" ]]; then
    runtime_target="$(readlink "${runtime_path}")"
    if [[ "${runtime_target}" = /* ]]; then
      test -e "${OUTPUT_ROOT}${runtime_target}" ||
        fail "active Libc6 runtime target is absent: ${runtime_target}"
    else
      test -e "$(dirname "${runtime_path}")/${runtime_target}" ||
        fail "active Libc6 runtime target is absent: ${runtime_target}"
    fi
  else
    test -e "${runtime_path}" ||
      fail "active Libc6 runtime is absent: /Libraries/${runtime_name}"
  fi
done
ln -sfn /Libraries/ld-linux-x86-64.so.2 \
  "${OUTPUT_ROOT}/System/Compatibility/lib64/ld-linux-x86-64.so.2"
ln -sfn /Libraries/libc.so.6 \
  "${OUTPUT_ROOT}/System/Compatibility/lib/x86_64-linux-gnu/libc.so.6"
ln -sfn /Libraries/libm.so.6 \
  "${OUTPUT_ROOT}/System/Compatibility/lib/x86_64-linux-gnu/libm.so.6"

for session_tool in start-e start-enlightenment-session start-e-supervisor; do
  sed -i '/^set -u$/a\
[ ! -r /System/Settings/auzix-runtime-env ] || . /System/Settings/auzix-runtime-env' \
    "${OUTPUT_ROOT}/System/Tools/${session_tool}"
done

test -x "${OUTPUT_ROOT}/System/Boot/InstalledInit"
test -x "${OUTPUT_ROOT}/System/Boot/StartSequence"
test -x "${OUTPUT_ROOT}/System/Tools/finalize-installed-root"
test -s "${OUTPUT_ROOT}/boot/vmlinuz-${KERNEL_RELEASE}"
test -d "${OUTPUT_ROOT}/System/Drivers/${KERNEL_RELEASE}"
grep -Fq '. /System/Settings/auzix-runtime-env' \
  "${OUTPUT_ROOT}/System/Boot/StartSequence"
test -s "${OUTPUT_ROOT}/System/Compatibility/lib/x86_64-linux-gnu/libsystemd-shared-257.so"
test -s "${OUTPUT_ROOT}/System/Compatibility/usr/lib/udev/rules.d/60-input-id.rules"
test -s "${OUTPUT_ROOT}/etc/X11/xorg.conf.d/40-libinput.conf"
test -s "${OUTPUT_ROOT}/System/Compatibility/usr/share/icons/hicolor/index.theme"
test -s "${OUTPUT_ROOT}/System/Compatibility/usr/share/icons/hicolor/128x128/apps/elementary.png"
test -s "${OUTPUT_ROOT}/System/Compatibility/usr/share/icons/hicolor/128x128/apps/terminology.png"
test -s "${OUTPUT_ROOT}/Users/auzix/.e/e/config/profile.cfg"
test -s "${OUTPUT_ROOT}/Users/auzix/.e/e/config/standard/e.cfg"
cmp -s "${ROOT_DIR}/assets/display/config/profile.cfg" \
  "${OUTPUT_ROOT}/Users/auzix/.e/e/config/profile.cfg"
test "$(readlink "${OUTPUT_ROOT}/System/Compatibility/lib64/ld-linux-x86-64.so.2")" = \
  /Libraries/ld-linux-x86-64.so.2
test "$(readlink "${OUTPUT_ROOT}/System/Compatibility/lib/x86_64-linux-gnu/libc.so.6")" = \
  /Libraries/libc.so.6
test "$(readlink "${OUTPUT_ROOT}/System/Compatibility/lib/x86_64-linux-gnu/libm.so.6")" = \
  /Libraries/libm.so.6
cmp -s \
  "${OUTPUT_ROOT}/Programs/Enlightenment/current/RootFS/usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_system" \
  "${OUTPUT_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_system"
test -x \
  "${OUTPUT_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/evas/modules/engines/software_x11/v-1.28/module.so"
test -x \
  "${OUTPUT_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/ecore_evas/engines/x/v-1.28/module.so"
test -z "$(find "${OUTPUT_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu" \
  -type d -name v-1.26 -print -quit)"
test "$(readlink "${OUTPUT_ROOT}/etc/apk")" = /System/Settings/apk
test "$(readlink "${OUTPUT_ROOT}/etc/ssl")" = /System/Compatibility/etc/ssl
grep -Eq '^root:[^!*:]' "${OUTPUT_ROOT}/etc/shadow"
grep -Eq '^auzix:[^!*:]' "${OUTPUT_ROOT}/etc/shadow"
test -s "${OUTPUT_ROOT}/System/State/apk/db/installed"
test "$(find "${OUTPUT_ROOT}/System/Compatibility/usr/share/icons" -type f | wc -l)" -ge 40
test -L "${OUTPUT_ROOT}/System/Compatibility/usr/share/fonts/auzix/FontsDejavuCore"
test -L "${OUTPUT_ROOT}/System/Compatibility/usr/share/fonts/auzix/FontsUrwBase35"
grep -Fq 'ln -sfn /run/resolv.conf /etc/resolv.conf' \
  "${OUTPUT_ROOT}/System/Boot/StartSequence"
mkdir -p "${OUTPUT_ROOT}/run/sshd"
chroot "${OUTPUT_ROOT}" /bin/sh -lc 'dbus-daemon --version >/dev/null && sshd -t'
chroot "${OUTPUT_ROOT}" /bin/sh -lc '
  fc-list | grep -q "DejaVu Sans" && fc-list | grep -q "Nimbus Sans"
'
rmdir "${OUTPUT_ROOT}/run/sshd"

image_id="$(docker image inspect -f '{{.Id}}' "${IMAGE}")"
cat >"${OUTPUT_ROOT}/System/State/alpha-hdd-stage.receipt" <<EOF
format=auzix-alpha-hdd-stage-v1
image=${IMAGE}
image_id=${image_id}
anchor_iso=${ANCHOR_ISO}
anchor_sha256=${actual_sha256}
strict_reference_root=${STRICT_REFERENCE_ROOT}
kernel_release=${KERNEL_RELEASE}
assembly=validated-container-userspace-plus-known-good-boot-spine
EOF
printf 'alpha-hdd-stage: PASS image=%s root=%s kernel=%s\n' \
  "${IMAGE}" "${OUTPUT_ROOT}" "${KERNEL_RELEASE}"
