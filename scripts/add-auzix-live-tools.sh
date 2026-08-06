#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"

log() {
  printf '[auzix-live-tools] %s\n' "$*" >&2
}

mkdir -p \
  "${AUZIX_ROOT}/System/Boot" \
  "${AUZIX_ROOT}/System/Tools" \
  "${AUZIX_ROOT}/System/Settings/display" \
  "${AUZIX_ROOT}/System/Settings/install" \
  "${AUZIX_ROOT}/System/State/display" \
  "${AUZIX_ROOT}/System/Logs/display" \
  "${AUZIX_ROOT}/Services"

cat > "${AUZIX_ROOT}/System/Settings/mdev.conf" <<'EOF'
null 0:0 0666
random 0:0 0666
urandom 0:0 0666
EOF

cat > "${AUZIX_ROOT}/System/Boot/StartSequence" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -u

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox

log() {
  echo "[StartSequence] $*"
}

console_note() {
  msg="[StartSequence] $*"
  echo "${msg}"
  [ -c /dev/tty1 ] && echo "${msg}" >/dev/tty1 2>/dev/null || true
  [ -c /dev/ttyS0 ] && echo "${msg}" >/dev/ttyS0 2>/dev/null || true
}

is_mounted() {
  "${BB}" grep -q " $1 " /proc/mounts 2>/dev/null
}

prepare_live_runtime_state() {
  # The ISO remains mounted at /run/live/iso after switch_root. The former
  # raw AuzixRoot directory is intentionally absent from a SquashFS layout.
  [ -d /run/live/iso ] || return 0

  "${BB}" mkdir -p /run/auzix-state-seed /run/auzix-log-seed 2>/dev/null || true
  if [ -d /System/State/ssh ] && [ ! -d /run/auzix-state-seed/ssh ]; then
    "${BB}" mkdir -p /run/auzix-state-seed/ssh 2>/dev/null || true
    "${BB}" cp -a /System/State/ssh/. /run/auzix-state-seed/ssh/ 2>/dev/null || true
  fi

  "${BB}" mkdir -p /System/State /System/Logs 2>/dev/null || true
  if ! is_mounted /System/State; then
    "${BB}" mount -t tmpfs tmpfs /System/State 2>/dev/null || true
  fi
  if ! is_mounted /System/Logs; then
    "${BB}" mount -t tmpfs tmpfs /System/Logs 2>/dev/null || true
  fi

  "${BB}" mkdir -p /System/State/ssh /System/State/dbus /System/State/display /System/Logs/display 2>/dev/null || true
  if [ -d /run/auzix-state-seed/ssh ]; then
    "${BB}" cp -a /run/auzix-state-seed/ssh/. /System/State/ssh/ 2>/dev/null || true
  fi
  "${BB}" chown -R 0:0 /System/State/ssh 2>/dev/null || true
  "${BB}" chmod 0755 /System/State /System/State/dbus /System/Logs /System/Logs/display 2>/dev/null || true
  "${BB}" chmod 0700 /System/State/ssh 2>/dev/null || true
  "${BB}" chmod 0600 /System/State/ssh/ssh_host_*_key 2>/dev/null || true
  "${BB}" chmod 0644 /System/State/ssh/ssh_host_*_key.pub 2>/dev/null || true
}

mount_runtime() {
  is_mounted /proc || "${BB}" mount -t proc proc /proc 2>/dev/null || true
  is_mounted /sys || "${BB}" mount -t sysfs sysfs /sys 2>/dev/null || true
  if [ -w /proc/sys/net/ipv4/ping_group_range ]; then
    echo "0 2147483647" >/proc/sys/net/ipv4/ping_group_range 2>/dev/null || true
  fi
  is_mounted /dev || "${BB}" mount -t devtmpfs devtmpfs /dev 2>/dev/null || "${BB}" mount -t tmpfs tmpfs /dev 2>/dev/null || true
  "${BB}" mkdir -p /dev/pts /dev/shm
  is_mounted /dev/pts || "${BB}" mount -t devpts devpts /dev/pts -o gid=5,mode=620,ptmxmode=666 2>/dev/null || "${BB}" mount -t devpts devpts /dev/pts 2>/dev/null || true
  is_mounted /dev/shm || "${BB}" mount -t tmpfs tmpfs /dev/shm -o mode=1777,nosuid,nodev 2>/dev/null || true
  "${BB}" mkdir -p /run
  is_mounted /run || "${BB}" mount -t tmpfs tmpfs /run 2>/dev/null || true
  prepare_live_runtime_state
  if ! is_mounted /run; then
    "${BB}" rm -rf /run/user /run/dbus /run/sshd 2>/dev/null || true
  fi
  "${BB}" rm -f /tmp/.X*-lock /tmp/.X11-unix/X* 2>/dev/null || true
  "${BB}" mkdir -p /run /run/lock /run/user /tmp /tmp/.X11-unix /dev/shm /var/cache /var/lib /var/log /Work/Temp /System/State /System/Logs /Network/DNS
  "${BB}" touch /var/log/lastlog 2>/dev/null || true
  "${BB}" ln -sfn /run/resolv.conf /System/Settings/resolv.conf 2>/dev/null || true
  if [ -d /System/Compatibility/etc/ssl ]; then
    "${BB}" ln -sfn /System/Compatibility/etc/ssl /System/Settings/ssl 2>/dev/null || true
    "${BB}" mkdir -p /System/Compatibility/usr/lib 2>/dev/null || true
    "${BB}" ln -sfn /System/Compatibility/etc/ssl /System/Compatibility/usr/lib/ssl 2>/dev/null || true
    if [ -s /System/Compatibility/etc/ssl/certs/ca-certificates.crt ]; then
      "${BB}" ln -sfn /System/Compatibility/etc/ssl/certs/ca-certificates.crt /System/Compatibility/etc/ssl/cert.pem 2>/dev/null || true
      "${BB}" ln -sfn /System/Compatibility/etc/ssl/certs/ca-certificates.crt /System/Compatibility/usr/lib/ssl/cert.pem 2>/dev/null || true
    fi
  fi
  if [ "$("${BB}" hostname 2>/dev/null || echo "(none)")" = "(none)" ]; then
    "${BB}" hostname auzix-live 2>/dev/null || true
  fi
  if [ ! -s /System/Settings/fstab ]; then
    cat > /System/Settings/fstab <<'FSTAB'
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
devtmpfs /dev devtmpfs defaults 0 0
devpts /dev/pts devpts gid=5,mode=620,ptmxmode=666 0 0
tmpfs /dev/shm tmpfs mode=1777,nosuid,nodev 0 0
tmpfs /run tmpfs defaults 0 0
FSTAB
  fi
  [ -e /var/tmp ] || "${BB}" ln -s /Work/Temp /var/tmp 2>/dev/null || true
  [ -e /var/run ] || "${BB}" ln -s /run /var/run 2>/dev/null || true
  [ -e /var/lock ] || "${BB}" ln -s /run/lock /var/lock 2>/dev/null || true
  [ -e /opt ] || "${BB}" ln -s /Programs /opt 2>/dev/null || true
  if [ -d /root ] && [ ! -L /root ]; then
    "${BB}" rmdir /root 2>/dev/null || true
  fi
  [ -e /root ] || "${BB}" ln -s /Users/root /root 2>/dev/null || true
  "${BB}" chown 0:0 /usr/local 2>/dev/null || true
  if [ -e /Programs/Sudo/host/Commands/sudo ]; then
    "${BB}" chown root:root /Programs/Sudo/host/Commands/sudo 2>/dev/null || true
    "${BB}" chmod 4755 /Programs/Sudo/host/Commands/sudo 2>/dev/null || true
  fi
  if [ -e /System/Compatibility/usr/lib/xorg/Xorg.wrap ]; then
    "${BB}" chown root:root /System/Compatibility/usr/lib/xorg/Xorg.wrap 2>/dev/null || true
    "${BB}" chmod 4755 /System/Compatibility/usr/lib/xorg/Xorg.wrap 2>/dev/null || true
  fi
  if [ -e /System/Settings/sudoers ]; then
    "${BB}" chown root:root /System/Settings/sudoers /System/Settings/sudo.conf 2>/dev/null || true
    "${BB}" chmod 0440 /System/Settings/sudoers 2>/dev/null || true
  fi
  if [ -d /System/Settings/sudoers.d ]; then
    "${BB}" chown -R root:root /System/Settings/sudoers.d 2>/dev/null || true
  fi
  if [ -d /System/Compatibility/usr/libexec/sudo ]; then
    "${BB}" chown -R root:root /System/Compatibility/usr/libexec/sudo 2>/dev/null || true
  fi
  "${BB}" chmod 1777 /tmp /tmp/.X11-unix /dev/shm /Work/Temp 2>/dev/null || true
  [ -e /dev/console ] || "${BB}" mknod /dev/console c 5 1
  [ -e /dev/null ] || "${BB}" mknod /dev/null c 1 3
  [ -e /dev/tty1 ] || "${BB}" mknod /dev/tty1 c 4 1
  [ -e /dev/tty2 ] || "${BB}" mknod /dev/tty2 c 4 2
  [ -e /dev/tty7 ] || "${BB}" mknod /dev/tty7 c 4 7
  [ -e /dev/ttyS0 ] || "${BB}" mknod /dev/ttyS0 c 4 64
  "${BB}" mdev -s 2>/dev/null || true
  "${BB}" chmod 0666 /dev/null 2>/dev/null || true
  "${BB}" chmod 0666 /dev/random /dev/urandom 2>/dev/null || true
  "${BB}" chmod 0666 /dev/ptmx /dev/pts/ptmx 2>/dev/null || true
}

repair_live_user_home() {
  "${BB}" mkdir -p /System/Settings /Users/root 2>/dev/null || true
  if ! "${BB}" grep -q '^auzix:' /System/Settings/passwd 2>/dev/null; then
    cat > /System/Settings/passwd <<'EOF'
root:x:0:0:root:/Users/root:/System/Compatibility/bin/sh
auzix:x:1000:1000:Auzix User:/Users/auzix:/System/Compatibility/bin/sh
sshd:x:74:74:sshd privilege separation:/run/sshd:/System/Compatibility/bin/false
messagebus:x:101:101:DBus message bus:/run/dbus:/System/Compatibility/bin/false
lightdm:x:102:102:LightDM display manager:/System/State/lightdm:/System/Compatibility/bin/false
EOF
  fi
  if ! "${BB}" grep -q '^auzix:' /System/Settings/group 2>/dev/null; then
    cat > /System/Settings/group <<'EOF'
root:x:0:
tty:x:5:
auzix:x:1000:
sshd:x:74:
messagebus:x:101:
lightdm:x:102:
sudo:x:27:auzix
wheel:x:10:root,auzix
input:x:104:root,auzix
video:x:44:root,auzix
render:x:105:root,auzix
audio:x:29:root,auzix
EOF
  fi
  if [ ! -s /System/Settings/shadow ]; then
    cat > /System/Settings/shadow <<'EOF'
root:*:19700:0:99999:7:::
auzix:*:19700:0:99999:7:::
sshd:*:19700:0:99999:7:::
messagebus:*:19700:0:99999:7:::
lightdm:*:19700:0:99999:7:::
EOF
  fi
  if [ ! -s /System/Settings/shells ]; then
    cat > /System/Settings/shells <<'EOF'
/System/Compatibility/bin/sh
/System/Compatibility/bin/bash
EOF
  fi
  if [ ! -s /System/Settings/nsswitch.conf ]; then
    cat > /System/Settings/nsswitch.conf <<'EOF'
passwd: files
group: files
shadow: files
hosts: files dns
networks: files
protocols: files
services: files
ethers: files
rpc: files
EOF
  fi
  if [ ! -s /System/Settings/hosts ]; then
    cat > /System/Settings/hosts <<'EOF'
127.0.0.1 localhost auzix auzix-live
::1 localhost ip6-localhost ip6-loopback
EOF
  fi
  "${BB}" chmod 0600 /System/Settings/shadow 2>/dev/null || true

  "${BB}" mkdir -p \
    /Users \
    /Users/auzix \
    /Users/auzix/.cache \
    /Users/auzix/.cache/efreet \
    /Users/auzix/.config \
    /Users/auzix/.local/share \
    /Users/auzix/.e/e \
    /Users/auzix/.elementary/config/standard \
    /Users/root 2>/dev/null || true
  "${BB}" chown root:root /Users /Users/root 2>/dev/null || true
  "${BB}" chmod 0755 /Users /Users/root 2>/dev/null || true
  "${BB}" chown 1000:1000 \
    /Users/auzix \
    /Users/auzix/.cache \
    /Users/auzix/.cache/efreet \
    /Users/auzix/.config \
    /Users/auzix/.local \
    /Users/auzix/.local/share \
    /Users/auzix/.e \
    /Users/auzix/.e/e \
    /Users/auzix/.elementary \
    /Users/auzix/.elementary/config \
    /Users/auzix/.elementary/config/standard 2>/dev/null || true
  "${BB}" chmod 0755 /Users/auzix 2>/dev/null || true
  "${BB}" chown -R 1000:1000 \
    /Users/auzix/.cache \
    /Users/auzix/.config \
    /Users/auzix/.local 2>/dev/null || true
  "${BB}" chmod -R u+rwX \
    /Users/auzix/.cache \
    /Users/auzix/.config \
    /Users/auzix/.local 2>/dev/null || true
  "${BB}" chmod u+rwx \
    /Users/auzix/.e \
    /Users/auzix/.e/e \
    /Users/auzix/.elementary \
    /Users/auzix/.elementary/config \
    /Users/auzix/.elementary/config/standard 2>/dev/null || true
}

start_network() {
  console_note "network: starting DHCP"
  cat > /run/auzix-udhcpc.script <<'NETSCRIPT'
#!/System/Compatibility/bin/sh
BB=/Programs/BusyBox/1.36.1/Commands/busybox

case "$1" in
  deconfig)
    "${BB}" ifconfig "${interface}" 0.0.0.0 2>/dev/null || true
    ;;
  bound|renew)
    "${BB}" ifconfig "${interface}" "${ip}" netmask "${subnet}" ${broadcast:+broadcast "${broadcast}"} up
    for route in ${router}; do
      "${BB}" route add default gw "${route}" dev "${interface}" 2>/dev/null || true
    done
    "${BB}" mkdir -p /run /Network/DNS
    : > /run/resolv.conf
    for server in ${dns}; do
      echo "nameserver ${server}" >> /run/resolv.conf
    done
    "${BB}" cp /run/resolv.conf /Network/DNS/resolv.conf 2>/dev/null || true
    "${BB}" ln -sfn /run/resolv.conf /System/Settings/resolv.conf 2>/dev/null || true
    echo "dhcp-lease=${interface} ip=${ip} router=${router} dns=${dns}"
    ;;
esac
NETSCRIPT
  "${BB}" chmod 0755 /run/auzix-udhcpc.script

  for iface in $("${BB}" ls /sys/class/net 2>/dev/null); do
    case "${iface}" in
      lo) "${BB}" ifconfig lo 127.0.0.1 up 2>/dev/null || true ;;
      *)
        "${BB}" ip link set "${iface}" up 2>/dev/null || true
        "${BB}" udhcpc -i "${iface}" -s /run/auzix-udhcpc.script -t 5 -T 3 -q -b \
          >/System/Logs/udhcpc-"${iface}".log 2>&1 || true
        ;;
    esac
  done
}

report_network_status() {
  console_note "network: interface summary follows"
  for iface in $("${BB}" ls /sys/class/net 2>/dev/null); do
    [ "${iface}" = "lo" ] && continue
    ipv4="$("${BB}" ip -4 addr show dev "${iface}" 2>/dev/null | "${BB}" awk '/inet / {print $2}' | "${BB}" head -n 1)"
    mac="$("${BB}" cat "/sys/class/net/${iface}/address" 2>/dev/null || true)"
    state="$("${BB}" cat "/sys/class/net/${iface}/operstate" 2>/dev/null || true)"
    console_note "network: ${iface} state=${state:-unknown} mac=${mac:-unknown} ipv4=${ipv4:-none}"
  done
  if [ -s /run/resolv.conf ]; then
    dns="$("${BB}" tr '\n' ' ' </run/resolv.conf 2>/dev/null || true)"
    console_note "network: dns=${dns}"
  fi
}

start_hardware() {
  if [ -x /System/Tools/auzix-hw-detect ]; then
    /System/Tools/auzix-hw-detect boot >/System/Logs/display/hardware-boot.log 2>&1 || true
  fi
}

live_media_ready() {
  [ -d /run/auzix-iso/live ] || [ -d /run/auzix-iso/LIVE ] || [ -d /run/auzix-iso/boot ]
}

unmount_live_media() {
  while is_mounted /run/auzix-iso; do
    "${BB}" umount /run/auzix-iso 2>/dev/null && continue
    "${BB}" umount -l /run/auzix-iso 2>/dev/null || break
  done
}

mount_live_media() {
  "${BB}" mkdir -p /run/auzix-iso

  if is_mounted /run/auzix-iso; then
    live_media_ready && return 0
    unmount_live_media
  fi

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    for dev in /dev/sr0 /dev/cdrom /dev/disk/by-label/AUZIXLIVE /dev/disk/by-label/ISOIMAGE; do
      [ -e "${dev}" ] || continue
      if "${BB}" mount -t iso9660 -o ro "${dev}" /run/auzix-iso 2>/dev/null; then
        if live_media_ready; then
          log "live media mounted from ${dev}"
          return 0
        fi
        unmount_live_media
      fi
    done
    "${BB}" sleep 1
  done

  return 0
}

find_live_assets() {
  for path in \
    /run/auzix-iso/live/assets \
    /run/auzix-iso/LIVE/ASSETS \
    /run/auzix-iso/AuzixAssets \
    /run/auzix-iso/AuzixAss \
    /run/auzix-iso/AUZIXASS
  do
    [ -d "${path}" ] || continue
    printf '%s\n' "${path}"
    return 0
  done

  return 1
}

prepare_enlightenment_background_path() {
  asset_dir="${1:-}"
  e_background_dir=/System/Compatibility/usr/share/enlightenment/data/backgrounds
  e_theme_dir=/System/Compatibility/usr/share/enlightenment/themes

  "${BB}" mkdir -p "${e_background_dir}" "${e_theme_dir}" 2>/dev/null || true
  [ -n "${asset_dir}" ] || return 0
  if [ -d "${asset_dir}/backgrounds" ]; then
    for item in "${asset_dir}"/backgrounds/*; do
      [ -f "${item}" ] || continue
      "${BB}" ln -sfn "${item}" "${e_background_dir}/$("${BB}" basename "${item}")" 2>/dev/null || true
    done
  fi
  if [ -d "${asset_dir}/themes" ]; then
    for item in "${asset_dir}"/themes/*.edj; do
      [ -f "${item}" ] || continue
      "${BB}" ln -sfn "${item}" "${e_theme_dir}/$("${BB}" basename "${item}")" 2>/dev/null || true
    done
  fi
}

stage_live_assets() {
  mount_live_media
  asset_dir="$(find_live_assets || true)"
  [ -n "${asset_dir}" ] || return 0

  "${BB}" mkdir -p /System/Settings/display/assets
  if ! is_mounted /System/Settings/display/assets; then
    "${BB}" mount --bind "${asset_dir}" /System/Settings/display/assets 2>/dev/null || true
  fi
  prepare_enlightenment_background_path "${asset_dir}"
  log "live display assets ready from ${asset_dir}"
}

stage_enlightenment_user_assets() {
  asset_dir="$(find_live_assets || true)"
  [ -n "${asset_dir}" ] || return 0
  prepare_enlightenment_background_path "${asset_dir}"

  "${BB}" mkdir -p \
    /Users/auzix/.e/e/config 2>/dev/null || true

  if [ "${AUZIX_STAGE_E_CONFIG:-0}" = "1" ] && [ -f "${asset_dir}/config/profile.cfg" ]; then
    "${BB}" cp -f "${asset_dir}/config/profile.cfg" /Users/auzix/.e/e/config/profile.cfg 2>/dev/null || true
  fi
  if [ "${AUZIX_STAGE_E_CONFIG:-0}" = "1" ]; then
  for profile in standard default; do
    [ -d "${asset_dir}/config/${profile}" ] || continue
    "${BB}" mkdir -p "/Users/auzix/.e/e/config/${profile}" 2>/dev/null || true
    "${BB}" cp -a "${asset_dir}/config/${profile}/." "/Users/auzix/.e/e/config/${profile}/" 2>/dev/null || true
  done
  fi

  "${BB}" chmod -R u+rwX /Users/auzix/.e/e/config 2>/dev/null || true
  "${BB}" chown -R 1000:1000 /Users/auzix/.e 2>/dev/null || true
  log "enlightenment live defaults staged from ${asset_dir}"
}

fix_session_permissions() {
  repair_live_user_home
  "${BB}" mkdir -p \
    /Users/auzix/.cache \
    /Users/auzix/.cache/efreet \
    /Users/auzix/.config \
    /Users/auzix/.e/e \
    /Users/auzix/.elementary/config/standard \
    /Users/root
  if [ ! -s /Users/auzix/.e/e/config/standard/e.cfg ] &&
     [ -d /usr/share/enlightenment/data/config/standard ]; then
    "${BB}" mkdir -p /Users/auzix/.e/e/config
    "${BB}" cp -a /usr/share/enlightenment/data/config/standard /Users/auzix/.e/e/config/ 2>/dev/null || true
  fi
	  if [ ! -s /Users/auzix/.e/e/config/profile.cfg ] &&
	     command -v eet >/dev/null 2>&1; then
	    printf standard > /Users/auzix/.cache/auzix-e-profile
	    eet -i /Users/auzix/.e/e/config/profile.cfg config /Users/auzix/.cache/auzix-e-profile 0 2>/dev/null || true
	    "${BB}" rm -f /Users/auzix/.cache/auzix-e-profile 2>/dev/null || true
	  fi
	  if [ "${AUZIX_FORCE_E_PROFILE:-standard}" = "standard" ] &&
	     command -v eet >/dev/null 2>&1; then
	    printf standard > /Users/auzix/.cache/auzix-e-profile
	    eet -i /Users/auzix/.e/e/config/profile.cfg config /Users/auzix/.cache/auzix-e-profile 0 2>/dev/null || true
	    "${BB}" rm -f /Users/auzix/.cache/auzix-e-profile 2>/dev/null || true
	  fi
  repair_live_user_home
  stage_enlightenment_user_assets
  "${BB}" chown root:root /Users /Users/root 2>/dev/null || true
  "${BB}" chmod 0755 /Users /Users/root 2>/dev/null || true
  for helper in \
    /usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_system \
    /usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_sys \
    /usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_ckpasswd; do
    [ -e "${helper}" ] || continue
    "${BB}" chown root:root "${helper}" 2>/dev/null || true
    "${BB}" chmod 4755 "${helper}" 2>/dev/null || true
  done
  if [ -d /usr/lib/x86_64-linux-gnu/enlightenment ] && [ ! -e /usr/lib/enlightenment ]; then
    "${BB}" mkdir -p /usr/lib
    "${BB}" ln -s /usr/lib/x86_64-linux-gnu/enlightenment /usr/lib/enlightenment 2>/dev/null || true
  fi
  "${BB}" mkdir -p /run/user/1000
  "${BB}" chown 1000:1000 /run/user/1000 2>/dev/null || true
  "${BB}" chmod 0700 /run/user/1000 2>/dev/null || true
  "${BB}" mkdir -p /System/Logs/display
  "${BB}" touch \
    /System/Logs/display/start-e.log \
    /System/Logs/display/openvt.log \
    /System/Logs/display/hardware-display.log \
    /System/Logs/display/e-module-tuning.log 2>/dev/null || true
  "${BB}" chown -R 1000:1000 /System/Logs/display 2>/dev/null || true
  "${BB}" chmod 0755 /System/Logs/display 2>/dev/null || true
  "${BB}" chown 1000:1000 \
    /System/Logs/display/start-e.log \
    /System/Logs/display/openvt.log \
    /System/Logs/display/hardware-display.log \
    /System/Logs/display/e-module-tuning.log 2>/dev/null || true
}

ensure_dbus_machine_id() {
  "${BB}" mkdir -p /System/State/dbus /var/lib/dbus /etc 2>/dev/null || true
  if [ ! -d /System/State/dbus ]; then
    "${BB}" mkdir -p /run/dbus-state 2>/dev/null || true
    [ -e /System/State/dbus ] || "${BB}" ln -s /run/dbus-state /System/State/dbus 2>/dev/null || true
  fi

  machine_id=""
  if [ -s /etc/machine-id ]; then
    machine_id="$("${BB}" head -n 1 /etc/machine-id 2>/dev/null || true)"
  elif [ -s /var/lib/dbus/machine-id ]; then
    machine_id="$("${BB}" head -n 1 /var/lib/dbus/machine-id 2>/dev/null || true)"
  elif [ -s /System/State/dbus/machine-id ]; then
    machine_id="$("${BB}" head -n 1 /System/State/dbus/machine-id 2>/dev/null || true)"
  fi

  if [ -z "${machine_id}" ] && [ -r /proc/sys/kernel/random/uuid ]; then
    machine_id="$("${BB}" tr -d '-' </proc/sys/kernel/random/uuid 2>/dev/null || true)"
  fi
  if [ -z "${machine_id}" ]; then
    machine_id="$(date +%s 2>/dev/null || echo 0)$("${BB}" cat /proc/sys/kernel/random/boot_id 2>/dev/null | "${BB}" tr -d '-' 2>/dev/null || true)"
    machine_id="$(printf '%s' "${machine_id}" | "${BB}" tr -cd '0123456789abcdef' | "${BB}" cut -c1-32)"
  fi
  [ -n "${machine_id}" ] || machine_id=00000000000000000000000000000000

  dbus_state_dir=/System/State/dbus
  if ! ( : >"${dbus_state_dir}/.write-test" ) 2>/dev/null; then
    dbus_state_dir=/run/dbus-state
    "${BB}" mkdir -p "${dbus_state_dir}" 2>/dev/null || true
  else
    "${BB}" rm -f "${dbus_state_dir}/.write-test" 2>/dev/null || true
  fi

  printf '%s\n' "${machine_id}" >"${dbus_state_dir}/machine-id" 2>/dev/null || true
  "${BB}" cp -f "${dbus_state_dir}/machine-id" /etc/machine-id 2>/dev/null || true
  "${BB}" cp -f "${dbus_state_dir}/machine-id" /var/lib/dbus/machine-id 2>/dev/null || true
  "${BB}" chmod 0444 /etc/machine-id 2>/dev/null || true
  "${BB}" chmod 0644 /var/lib/dbus/machine-id "${dbus_state_dir}/machine-id" 2>/dev/null || true
}

start_system_bus() {
  command -v dbus-daemon >/dev/null 2>&1 || return 0
  ensure_dbus_machine_id
  "${BB}" mkdir -p /run/dbus
  if [ -S /run/dbus/system_bus_socket ] &&
     "${BB}" ps | "${BB}" grep "dbus-daemon --system" | "${BB}" grep -v grep >/dev/null 2>&1; then
    return 0
  fi
  "${BB}" rm -f /run/dbus/system_bus_socket 2>/dev/null || true
  dbus-daemon --system --fork --nopidfile >/System/Logs/dbus-system.log 2>&1 || true
}

first_event_for_name() {
  pattern="$1"
  "${BB}" awk -v pat="${pattern}" '
    /^N: Name=/ { name=$0 }
    /^H: Handlers=/ && name ~ pat {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^event[0-9]+$/) {
          print "/dev/input/" $i
          exit
        }
      }
    }
  ' /proc/bus/input/devices 2>/dev/null
}

first_relative_pointer_event() {
  "${BB}" awk '
    /^N: Name=/ { name=$0; event=""; has_rel=0; has_abs=0 }
    /^H: Handlers=/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^event[0-9]+$/) event="/dev/input/" $i
      }
    }
    /^B: REL=/ && $3 != "0" { has_rel=1 }
    /^B: ABS=/ && $3 != "0" { has_abs=1 }
    /^$/ {
      if (event != "" && has_rel && !has_abs) {
        print event
        exit
      }
    }
  ' /proc/bus/input/devices 2>/dev/null
}

append_input_device() {
  ident="$1"
  event="$2"
  core_opt="$3"
  [ -n "${event}" ] || return 0
  cat >> /System/Settings/X11/xorg.conf <<EOF

Section "InputDevice"
    Identifier "${ident}"
    Driver "evdev"
    Option "Device" "${event}"
    Option "${core_opt}" "true"
EndSection
EOF
}

write_xorg_config() {
  keyboard_event="$(first_event_for_name "AT Translated Set 2 keyboard")"
  tablet_event="$(first_event_for_name "QEMU QEMU USB Tablet")"
  mouse_event="$(first_relative_pointer_event)"
  [ -n "${mouse_event}" ] || mouse_event="$(first_event_for_name "VirtualPS/2 VMware VMMouse")"
  [ -n "${tablet_event}" ] || tablet_event="${mouse_event}"
  [ -n "${keyboard_event}" ] || keyboard_event=/dev/input/event0
  [ -n "${mouse_event}" ] || mouse_event=/dev/input/event2

  "${BB}" mkdir -p /System/Settings/X11
  if [ -e /System/Compatibility/usr/lib/xorg/modules/input/libinput_drv.so ]; then
    cat > /System/Settings/X11/xorg.conf <<EOF
Section "Files"
    ModulePath "/System/Drivers/Xorg/modules"
    ModulePath "/System/Compatibility/usr/lib/xorg/modules"
    FontPath "/System/Fonts/X11/misc"
    FontPath "/System/Fonts/X11/Type1"
    FontPath "/System/Fonts/X11/75dpi"
    FontPath "/System/Fonts/X11/100dpi"
    FontPath "/System/Fonts/truetype/dejavu"
EndSection

Section "ServerFlags"
    Option "AutoAddDevices" "true"
    Option "AutoEnableDevices" "true"
    Option "AllowMouseOpenFail" "true"
EndSection

Section "Device"
    Identifier "AuzixVideo"
    Driver "modesetting"
    Option "AccelMethod" "none"
    Option "DRI" "false"
EndSection

Section "Screen"
    Identifier "AuzixScreen"
    Device "AuzixVideo"
EndSection

Section "ServerLayout"
    Identifier "AuzixLayout"
    Screen "AuzixScreen"
EndSection
EOF
    log "xorg input=libinput-auto keyboard=${keyboard_event} tablet=${tablet_event} pointer=${mouse_event}"
    return 0
  fi

  cat > /System/Settings/X11/xorg.conf <<EOF
Section "Files"
    ModulePath "/System/Drivers/Xorg/modules"
    ModulePath "/System/Compatibility/usr/lib/xorg/modules"
    FontPath "/System/Fonts/X11/misc"
    FontPath "/System/Fonts/X11/Type1"
    FontPath "/System/Fonts/X11/75dpi"
    FontPath "/System/Fonts/X11/100dpi"
    FontPath "/System/Fonts/truetype/dejavu"
EndSection

Section "ServerFlags"
    Option "AutoAddDevices" "false"
    Option "AutoEnableDevices" "false"
    Option "AllowMouseOpenFail" "true"
EndSection

Section "InputDevice"
    Identifier "AuzixKeyboard"
    Driver "evdev"
    Option "Device" "${keyboard_event}"
    Option "CoreKeyboard" "true"
EndSection
EOF

  append_input_device "AuzixTablet" "${tablet_event}" "CorePointer"
  layout_extra=""
  if [ "${mouse_event}" != "${tablet_event}" ]; then
    append_input_device "AuzixPointer" "${mouse_event}" "SendCoreEvents"
    layout_extra='    InputDevice "AuzixPointer" "SendCoreEvents"'
  fi

  cat >> /System/Settings/X11/xorg.conf <<EOF

Section "Device"
    Identifier "AuzixVideo"
    Driver "modesetting"
    Option "AccelMethod" "none"
    Option "DRI" "false"
EndSection

Section "Screen"
    Identifier "AuzixScreen"
    Device "AuzixVideo"
EndSection

Section "ServerLayout"
    Identifier "AuzixLayout"
    Screen "AuzixScreen"
    InputDevice "AuzixKeyboard" "CoreKeyboard"
    InputDevice "AuzixTablet" "CorePointer"
${layout_extra}
EndSection
EOF
  log "xorg input=evdev-explicit keyboard=${keyboard_event} tablet=${tablet_event} pointer=${mouse_event}"
}

start_services() {
  for runner in /Services/*/run; do
    [ -x "${runner}" ] || continue
    service="${runner%/run}"
    service="${service##*/}"
    [ "${service}" = "udev" ] && continue
    log "starting service ${service}"
    "${runner}" >/System/Logs/"${service}".log 2>&1 &
  done
}

report_service_status() {
  console_note "services: process summary follows"
  "${BB}" ps | "${BB}" grep -E "sshd|dbus-daemon|acpid|udevd|Xorg|enlightenment|start-e" | "${BB}" grep -v grep | while IFS= read -r line; do
    console_note "services: ${line}"
  done
  if command -v nc >/dev/null 2>&1; then
    nc -z 127.0.0.1 22 >/dev/null 2>&1 &&
      console_note "services: ssh tcp/22 listening" ||
      console_note "services: ssh tcp/22 not listening"
  fi
}

start_device_manager() {
  [ -x /Services/udev/run ] || return 0
  log "starting udev"
  /Services/udev/run >/System/Logs/udev.log 2>&1 || true
}

start_display() {
  [ -e /System/Settings/display/autostart ] || return 0
  [ -x /System/Tools/start-e ] || return 0
  display_mode="$("${BB}" head -n 1 /System/Settings/display/autostart 2>/dev/null || echo manual)"
  [ "${display_mode}" = "manual" ] && return 0
  if "${BB}" ps | "${BB}" grep -E "enlightenment|start-e" | "${BB}" grep -v grep >/dev/null 2>&1; then
    return 0
  fi

  "${BB}" mkdir -p /System/Logs/display
  "${BB}" chmod 0666 /dev/ptmx /dev/pts/ptmx 2>/dev/null || true
  delay="${AUZIX_GUI_DELAY:-15}"
  if [ "${delay}" -gt 0 ] 2>/dev/null; then
    console_note "gui: starting in ${delay}s; run 'touch /run/auzix-skip-gui' from rescue shell to stop autostart"
    while [ "${delay}" -gt 0 ]; do
      [ -e /run/auzix-skip-gui ] && {
        console_note "gui: autostart skipped by /run/auzix-skip-gui"
        return 0
      }
      "${BB}" sleep 1
      delay=$((delay - 1))
    done
  fi
  [ -e /run/auzix-skip-gui ] && {
    console_note "gui: autostart skipped by /run/auzix-skip-gui"
    return 0
  }
  log "starting display on tty7"
  [ -n "${display_mode}" ] || display_mode=x11
  case "${display_mode}" in
    wayland)
      display_env="HOME=/Users/auzix XDG_RUNTIME_DIR=/run/user/1000 AUZIX_E_MODE=wayland AUZIX_X_VT=7 E_WL_FORCE=drm"
      ;;
    auto)
      display_env="HOME=/Users/auzix XDG_RUNTIME_DIR=/run/user/1000 AUZIX_E_MODE=x11 AUZIX_X_VT=7"
      ;;
    *)
      display_env="HOME=/Users/auzix XDG_RUNTIME_DIR=/run/user/1000 AUZIX_E_MODE=${display_mode} AUZIX_X_VT=7"
      ;;
  esac
  "${BB}" openvt -c 7 -s -- "${BB}" su auzix -c "${display_env} /System/Tools/start-e" \
    >/System/Logs/display/openvt.log 2>&1 &
}

console_note "stage: mounting runtime filesystems"
mount_runtime
console_note "stage: repairing live user home"
repair_live_user_home
console_note "stage: starting udev"
start_device_manager
console_note "stage: staging live assets"
stage_live_assets
console_note "stage: detecting hardware"
start_hardware
write_xorg_config
console_note "stage: fixing session permissions"
fix_session_permissions
console_note "stage: starting dbus"
start_system_bus
console_note "stage: starting network"
start_network
report_network_status
console_note "stage: starting declared services"
start_services
report_service_status
console_note "stage: recording live diagnostic receipt"
/System/Tools/auzix-live-agent collect boot >/System/Logs/live-agent.log 2>&1 || \
  console_note "diagnostics: receipt collection failed; inspect /System/Logs/live-agent.log"
display_autostart="$("${BB}" head -n 1 /System/Settings/display/autostart 2>/dev/null || echo manual)"
if [ "${AUZIX_GUI_AUTOSTART:-0}" = "1" ] || [ "${display_autostart}" != "manual" ]; then
  console_note "stage: starting display"
  start_display
else
  console_note "gui: autostart disabled; run /System/Tools/start-gui-stage or AUZIX_GUI_AUTOSTART=1 /System/Boot/StartSequence"
fi
console_note "stage: complete"
SCRIPT

chmod 0755 "${AUZIX_ROOT}/System/Boot/StartSequence"

cat > "${AUZIX_ROOT}/System/Tools/auzix-live-agent" <<'SCRIPT'
#!/System/Compatibility/bin/sh
# Auzix live diagnostic agent: local evidence collection only.
# It opens no listener, changes no network state, and carries no credentials.
set -u

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox
STATE=/System/State/agent
LOGS=/System/Logs/agent

usage() {
  echo "usage: auzix-live-agent {collect [phase]|status|midori-check}"
}

prepare() {
  "${BB}" mkdir -p "${STATE}" "${LOGS}" 2>/dev/null || true
}

mounted() {
  "${BB}" grep -q " $1 " /proc/mounts 2>/dev/null
}

writable() {
  marker="$1/.auzix-write-test.$$"
  ( : > "${marker}" ) 2>/dev/null && {
    "${BB}" rm -f "${marker}" 2>/dev/null || true
    echo writable
    return
  }
  echo readonly-or-unavailable
}

emit_receipt() {
  phase="${1:-manual}"
  receipt="${LOGS}/receipt-${phase}.log"
  {
    echo "Auzix live diagnostic receipt"
    echo "phase=${phase}"
    echo "timestamp=$("${BB}" date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
    echo "kernel=$("${BB}" uname -r 2>/dev/null || true)"
    echo "cmdline=$("${BB}" tr '\n' ' ' </proc/cmdline 2>/dev/null || true)"
    echo
    echo "[mounts]"
    "${BB}" mount 2>/dev/null || true
    echo
    echo "[writable-path-contract]"
    for path in /run /tmp /Users /Work /System/State /System/Logs /Network/DNS; do
      [ -d "${path}" ] || "${BB}" mkdir -p "${path}" 2>/dev/null || true
      echo "${path}: $(writable "${path}")"
    done
    echo
    echo "[network]"
    "${BB}" ip -brief address 2>/dev/null || "${BB}" ifconfig -a 2>/dev/null || true
    "${BB}" ip route 2>/dev/null || true
    echo "resolv.conf:"
    "${BB}" cat /run/resolv.conf 2>/dev/null || "${BB}" cat /System/Settings/resolv.conf 2>/dev/null || true
    echo
    echo "[services]"
    "${BB}" ps 2>/dev/null | "${BB}" grep -E "sshd|dbus-daemon|acpid|udevd|Xorg|enlightenment|start-e" | "${BB}" grep -v grep || true
    echo
    echo "[midori]"
    /System/Tools/auzix-live-agent midori-check
  } >"${receipt}" 2>&1
  "${BB}" cp "${receipt}" "${LOGS}/latest.log" 2>/dev/null || true
  echo "receipt=${receipt}"
}

midori_check() {
  executable=/Programs/Midori/current/Resources/midori/midori
  wrapper=/Programs/Midori/current/Commands/midori
  ca=/System/Compatibility/etc/ssl/certs/ca-certificates.crt
  echo "wrapper=$([ -x "${wrapper}" ] && echo ready || echo missing)"
  echo "executable=$([ -x "${executable}" ] && echo ready || echo missing)"
  echo "ca_bundle=$([ -s "${ca}" ] && echo ready || echo missing)"
  echo "dns_config=$([ -s /run/resolv.conf ] && echo ready || echo missing)"
  if [ -x "${executable}" ] && command -v ldd >/dev/null 2>&1; then
    echo "loader_check:"
    ldd "${executable}" 2>&1 | "${BB}" grep -E 'not found|=> ' || true
  fi
  if command -v curl >/dev/null 2>&1; then
    echo "https_probe:"
    curl -fsS --connect-timeout 8 --max-time 12 -o /dev/null https://example.com 2>&1 && echo ok || echo failed
  elif command -v wget >/dev/null 2>&1; then
    echo "https_probe:"
    wget -q -T 12 -O /dev/null https://example.com 2>&1 && echo ok || echo failed
  else
    echo "https_probe=unavailable-no-curl-or-wget"
  fi
}

case "${1:-status}" in
  collect) prepare; emit_receipt "${2:-manual}" ;;
  status) prepare; [ -f "${LOGS}/latest.log" ] && "${BB}" tail -n 80 "${LOGS}/latest.log" || echo "no receipt yet" ;;
  midori-check) midori_check ;;
  *) usage; exit 2 ;;
esac
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/auzix-live-agent"

cat > "${AUZIX_ROOT}/System/Tools/prepare-livecd-state" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -u

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox

is_mounted() {
  "${BB}" grep -q " $1 " /proc/mounts 2>/dev/null
}

live_media_ready() {
  [ -d /run/auzix-iso/live ] || [ -d /run/auzix-iso/LIVE ] || [ -d /run/auzix-iso/boot ]
}

unmount_live_media() {
  while is_mounted /run/auzix-iso; do
    "${BB}" umount /run/auzix-iso 2>/dev/null && continue
    "${BB}" umount -l /run/auzix-iso 2>/dev/null || break
  done
}

find_live_assets() {
  for path in \
    /run/auzix-iso/live/assets \
    /run/auzix-iso/LIVE/ASSETS \
    /run/auzix-iso/AuzixAssets \
    /run/auzix-iso/AuzixAss \
    /run/auzix-iso/AUZIXASS
  do
    [ -d "${path}" ] || continue
    printf '%s\n' "${path}"
    return 0
  done

  return 1
}

prepare_enlightenment_background_path() {
  asset_dir="${1:-}"
  e_background_dir=/System/Compatibility/usr/share/enlightenment/data/backgrounds
  e_theme_dir=/System/Compatibility/usr/share/enlightenment/themes

  "${BB}" mkdir -p "${e_background_dir}" "${e_theme_dir}" 2>/dev/null || true
  [ -n "${asset_dir}" ] || return 0
  if [ -d "${asset_dir}/backgrounds" ]; then
    for item in "${asset_dir}"/backgrounds/*; do
      [ -f "${item}" ] || continue
      "${BB}" ln -sfn "${item}" "${e_background_dir}/$("${BB}" basename "${item}")" 2>/dev/null || true
    done
  fi
  if [ -d "${asset_dir}/themes" ]; then
    for item in "${asset_dir}"/themes/*.edj; do
      [ -f "${item}" ] || continue
      "${BB}" ln -sfn "${item}" "${e_theme_dir}/$("${BB}" basename "${item}")" 2>/dev/null || true
    done
  fi
}

"${BB}" mkdir -p /run/auzix-iso /System/Settings/display/assets /System/Logs/display /System/State/display /Work/Temp
if is_mounted /run/auzix-iso && ! live_media_ready; then
  unmount_live_media
fi
if ! is_mounted /run/auzix-iso; then
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    for dev in /dev/sr0 /dev/cdrom /dev/disk/by-label/AUZIXLIVE /dev/disk/by-label/ISOIMAGE; do
      [ -e "${dev}" ] || continue
      "${BB}" mount -t iso9660 -o ro "${dev}" /run/auzix-iso 2>/dev/null || continue
      live_media_ready && break 2
      unmount_live_media
    done
    "${BB}" sleep 1
  done
fi

asset_dir="$(find_live_assets || true)"
if [ -n "${asset_dir}" ] && ! is_mounted /System/Settings/display/assets; then
  "${BB}" mount --bind "${asset_dir}" /System/Settings/display/assets 2>/dev/null || true
fi
if [ -n "${asset_dir}" ]; then
  prepare_enlightenment_background_path "${asset_dir}"
  "${BB}" mkdir -p /Users/auzix/.e/e/config 2>/dev/null || true
  if [ "${AUZIX_STAGE_E_CONFIG:-0}" = "1" ] && [ -f "${asset_dir}/config/profile.cfg" ]; then
    "${BB}" cp -f "${asset_dir}/config/profile.cfg" /Users/auzix/.e/e/config/profile.cfg 2>/dev/null || true
  fi
  if [ "${AUZIX_STAGE_E_CONFIG:-0}" = "1" ]; then
  for profile in standard default; do
    [ -d "${asset_dir}/config/${profile}" ] || continue
    "${BB}" mkdir -p "/Users/auzix/.e/e/config/${profile}" 2>/dev/null || true
    "${BB}" cp -a "${asset_dir}/config/${profile}/." "/Users/auzix/.e/e/config/${profile}/" 2>/dev/null || true
  done
  fi
  "${BB}" chmod -R u+rwX /Users/auzix/.e/e/config 2>/dev/null || true
  "${BB}" chown -R 1000:1000 /Users/auzix/.e 2>/dev/null || true
fi

if command -v pulseaudio >/dev/null 2>&1 || command -v pipewire >/dev/null 2>&1; then
  disabled_dir=/System/State/desktop/enlightenment/disabled-modules
  for module in mixer music-control; do
    if [ -d "${disabled_dir}/${module}" ] &&
       [ ! -e "/System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/modules/${module}" ]; then
      "${BB}" mv "${disabled_dir}/${module}" "/System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/modules/${module}" 2>/dev/null || true
    fi
  done
elif [ "${AUZIX_MASK_NOAUDIO_MODULES:-1}" = "1" ]; then
  disabled_dir=/System/State/desktop/enlightenment/disabled-modules
  "${BB}" mkdir -p "${disabled_dir}" 2>/dev/null || true
  for module in mixer music-control; do
    if [ -d "/System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/modules/${module}" ]; then
      "${BB}" mv "/System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/modules/${module}" "${disabled_dir}/${module}" 2>/dev/null || true
    fi
    "${BB}" rm -f "/Users/auzix/.e/e/config/standard/module.${module}.cfg" 2>/dev/null || true
  done
  "${BB}" chown -R 1000:1000 "${disabled_dir}" /Users/auzix/.e 2>/dev/null || true
fi

"${BB}" touch /System/Logs/display/start-e.log /System/Logs/display/openvt.log /System/Logs/display/hardware-display.log 2>/dev/null || true
"${BB}" chown 1000:1000 /System/Logs/display/start-e.log /System/Logs/display/openvt.log /System/Logs/display/hardware-display.log 2>/dev/null || true
"${BB}" chmod 0666 /dev/ptmx /dev/pts/ptmx 2>/dev/null || true
"${BB}" mkdir -p /run/user/1000
"${BB}" chown 1000:1000 /run/user/1000 2>/dev/null || true
"${BB}" chmod 0700 /run/user/1000 2>/dev/null || true
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/prepare-livecd-state"

cat > "${AUZIX_ROOT}/System/Tools/repair-e-state" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -u

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands:/Programs/EFL/1.28.1/Commands:/System/Compatibility/usr/bin
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox
HOME_DIR="${1:-/Users/auzix}"
USER_NAME="${2:-auzix}"

"${BB}" mkdir -p \
  /dev/shm \
  /Work/Temp \
  "${HOME_DIR}/.cache/efreet" \
  "${HOME_DIR}/.config" \
  "${HOME_DIR}/.local/share" \
  "${HOME_DIR}/.e/e/themes" \
  "${HOME_DIR}/.e/e/backgrounds" \
  "${HOME_DIR}/.e/e/config" \
  "${HOME_DIR}/.elementary/themes" \
  "${HOME_DIR}/.elementary/config/standard" 2>/dev/null || true

mount | "${BB}" grep -q " /dev/shm " 2>/dev/null ||
  "${BB}" mount -t tmpfs tmpfs /dev/shm -o mode=1777,nosuid,nodev 2>/dev/null || true

"${BB}" chmod 1777 /dev/shm /Work/Temp /tmp 2>/dev/null || true
"${BB}" chown -R 1000:1000 \
  "${HOME_DIR}/.cache" \
  "${HOME_DIR}/.config" \
  "${HOME_DIR}/.local" \
  "${HOME_DIR}/.e" \
  "${HOME_DIR}/.elementary" 2>/dev/null || true
"${BB}" chmod -R u+rwX \
  "${HOME_DIR}/.cache" \
  "${HOME_DIR}/.config" \
  "${HOME_DIR}/.local" \
  "${HOME_DIR}/.e" \
  "${HOME_DIR}/.elementary" 2>/dev/null || true

if [ "${AUZIX_CLEAR_EFREET_CACHE:-0}" = "1" ]; then
  "${BB}" rm -f "${HOME_DIR}/.cache/efreet/"* 2>/dev/null || true
fi

if [ "${AUZIX_SAFE_E_THEMES:-1}" = "1" ]; then
  for theme_dir in \
    "${HOME_DIR}/.e/e/themes" \
    "${HOME_DIR}/.elementary/themes"
  do
    [ -d "${theme_dir}" ] || continue
    quarantine="${theme_dir}-incompatible"
    "${BB}" mkdir -p "${quarantine}" 2>/dev/null || true
    for pattern in '*E22*.edj' '*NightBling*.edj'; do
      for item in "${theme_dir}"/${pattern}; do
        [ -e "${item}" ] || continue
        "${BB}" mv -f "${item}" "${quarantine}/" 2>/dev/null || true
      done
    done
  done
fi

if [ "${AUZIX_RESET_E_THEME_STATE:-0}" = "1" ] &&
   [ -s /System/Compatibility/usr/share/enlightenment/data/config/standard/e.cfg ]; then
  profile_dir="${HOME_DIR}/.e/e/config/standard"
  "${BB}" mkdir -p "${profile_dir}" "${HOME_DIR}/.e/e/config/recovery" 2>/dev/null || true
  if [ -s "${profile_dir}/e.cfg" ]; then
    stamp="$(date +%Y%m%d%H%M%S 2>/dev/null || echo now)"
    "${BB}" cp -f "${profile_dir}/e.cfg" "${HOME_DIR}/.e/e/config/recovery/e.cfg.broken-${stamp}" 2>/dev/null || true
  fi
  "${BB}" cp -f /System/Compatibility/usr/share/enlightenment/data/config/standard/e.cfg "${profile_dir}/e.cfg" 2>/dev/null || true
fi

if command -v eet >/dev/null 2>&1 &&
   [ -s "${HOME_DIR}/.e/e/config/standard/e_comp.cfg" ]; then
  comp_txt="${HOME_DIR}/.cache/e_comp.cfg.txt"
  comp_new="${HOME_DIR}/.cache/e_comp.cfg.new"
  if eet -d "${HOME_DIR}/.e/e/config/standard/e_comp.cfg" config "${comp_txt}" 2>/dev/null; then
    "${BB}" sed \
      -e 's/value "engine" int: [0-9][0-9]*;/value "engine" int: 1;/' \
      -e 's/value "vsync" uchar: [0-9][0-9]*;/value "vsync" uchar: 0;/' \
      -e 's/value "smooth_windows" uchar: [0-9][0-9]*;/value "smooth_windows" uchar: 0;/' \
      "${comp_txt}" > "${comp_txt}.safe" 2>/dev/null || true
    if [ -s "${comp_txt}.safe" ] &&
       eet -e "${comp_new}" config "${comp_txt}.safe" 0 2>/dev/null; then
      "${BB}" cp -f "${comp_new}" "${HOME_DIR}/.e/e/config/standard/e_comp.cfg" 2>/dev/null || true
      "${BB}" rm -f "${comp_new}" 2>/dev/null || true
    fi
  fi
  "${BB}" rm -f "${comp_txt}" "${comp_txt}.safe" "${comp_new}" 2>/dev/null || true
fi

echo "E state repaired for ${USER_NAME} at ${HOME_DIR}"
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/repair-e-state"

cat > "${AUZIX_ROOT}/System/Tools/reset-e-theme-state" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -u

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands:/System/Compatibility/usr/bin
export PATH

AUZIX_RESET_E_THEME_STATE=1 AUZIX_SAFE_E_THEMES=1 /System/Tools/repair-e-state /Users/auzix auzix
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/reset-e-theme-state"

cat > "${AUZIX_ROOT}/System/Tools/start-e-supervisor" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -u

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands:/System/Compatibility/usr/bin
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox

mode="${AUZIX_E_MODE:-x11}"
vt="${AUZIX_X_VT:-7}"
stop_flag=/System/State/display/stop-gui
log=/System/Logs/display/supervisor.log

"${BB}" mkdir -p /System/State/display /System/Logs/display 2>/dev/null || true
"${BB}" rm -f "${stop_flag}" 2>/dev/null || true

echo "supervisor=starting mode=${mode} vt=${vt}" >>"${log}"

restart_count=0
while [ ! -e "${stop_flag}" ]; do
  started="$(date +%s 2>/dev/null || echo 0)"
  echo "supervisor=session-start count=${restart_count}" >>"${log}"

  HOME=/Users/auzix \
  XDG_RUNTIME_DIR=/run/user/1000 \
  AUZIX_E_MODE="${mode}" \
  AUZIX_X_VT="${vt}" \
  /System/Tools/start-e
  rc=$?

  ended="$(date +%s 2>/dev/null || echo 0)"
  runtime=0
  if [ "${started}" != 0 ] && [ "${ended}" != 0 ]; then
    runtime=$((ended - started))
  fi
  echo "supervisor=session-exit rc=${rc} runtime=${runtime}" >>"${log}"

  [ -e "${stop_flag}" ] && break

  "${BB}" killall efreetd enlightenment Xorg xinit 2>/dev/null || true
  "${BB}" sleep 2

  if [ "${runtime}" -lt 8 ]; then
    restart_count=$((restart_count + 1))
  else
    restart_count=0
  fi

  if [ "${restart_count}" -gt "${AUZIX_GUI_MAX_FAST_RESTARTS:-5}" ]; then
    echo "supervisor=fast-restart-backoff count=${restart_count}" >>"${log}"
    "${BB}" sleep 10
  fi
done

echo "supervisor=stopped" >>"${log}"
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/start-e-supervisor"

cat > "${AUZIX_ROOT}/System/Tools/start-lightdm-stage" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -u

PATH=/System/Compatibility/sbin:/System/Compatibility/bin:/System/Compatibility/usr/sbin:/System/Compatibility/usr/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox
log=/System/Logs/lightdm/start-lightdm-stage.log

ensure_dbus_machine_id() {
  "${BB}" mkdir -p /System/State/dbus /var/lib/dbus /etc 2>/dev/null || true

  machine_id=""
  if [ -s /etc/machine-id ]; then
    machine_id="$("${BB}" head -n 1 /etc/machine-id 2>/dev/null || true)"
  elif [ -s /var/lib/dbus/machine-id ]; then
    machine_id="$("${BB}" head -n 1 /var/lib/dbus/machine-id 2>/dev/null || true)"
  elif [ -s /System/State/dbus/machine-id ]; then
    machine_id="$("${BB}" head -n 1 /System/State/dbus/machine-id 2>/dev/null || true)"
  fi

  if [ -z "${machine_id}" ] && [ -r /proc/sys/kernel/random/uuid ]; then
    machine_id="$("${BB}" tr -d '-' </proc/sys/kernel/random/uuid 2>/dev/null || true)"
  fi
  [ -n "${machine_id}" ] || machine_id=00000000000000000000000000000000

  dbus_state_dir=/System/State/dbus
  if ! ( : >"${dbus_state_dir}/.write-test" ) 2>/dev/null; then
    dbus_state_dir=/run/dbus-state
    "${BB}" mkdir -p "${dbus_state_dir}" 2>/dev/null || true
  else
    "${BB}" rm -f "${dbus_state_dir}/.write-test" 2>/dev/null || true
  fi

  printf '%s\n' "${machine_id}" >"${dbus_state_dir}/machine-id" 2>/dev/null || true
  "${BB}" cp -f "${dbus_state_dir}/machine-id" /etc/machine-id 2>/dev/null || true
  "${BB}" cp -f "${dbus_state_dir}/machine-id" /var/lib/dbus/machine-id 2>/dev/null || true
  "${BB}" chmod 0444 /etc/machine-id 2>/dev/null || true
  "${BB}" chmod 0644 /var/lib/dbus/machine-id "${dbus_state_dir}/machine-id" 2>/dev/null || true
}

start_system_bus() {
  command -v dbus-daemon >/dev/null 2>&1 || return 0
  ensure_dbus_machine_id
  "${BB}" mkdir -p /run/dbus 2>/dev/null || true
  if [ -S /run/dbus/system_bus_socket ] &&
     "${BB}" ps | "${BB}" grep "dbus-daemon --system" | "${BB}" grep -v grep >/dev/null 2>&1; then
    return 0
  fi
  "${BB}" rm -f /run/dbus/system_bus_socket 2>/dev/null || true
  dbus-daemon --system --fork --nopidfile >/System/Logs/lightdm/dbus-system.log 2>&1 || true
}

"${BB}" mkdir -p /System/Logs/lightdm /System/State/lightdm/cache /run/lightdm /run/user /System/State/display 2>/dev/null || true
start_system_bus

if "${BB}" ps | "${BB}" grep -E "[/]lightdm( |$)|[l]ightdm-gtk-greeter" >/dev/null 2>&1; then
  echo "lightdm-stage=already-running"
  exit 0
fi

"${BB}" touch /System/State/display/stop-gui 2>/dev/null || true
"${BB}" killall efreetd enlightenment enlightenment_start Xorg xinit start-e-supervisor 2>/dev/null || true
for attempt in 1 2 3 4 5; do
  "${BB}" ps | "${BB}" grep -E "[X]org|[x]init|[e]nlightenment|[s]tart-e-supervisor" >/dev/null 2>&1 || break
  "${BB}" sleep 1
done
"${BB}" rm -f /tmp/.X*-lock /tmp/.X11-unix/X* /run/lightdm/* 2>/dev/null || true

if [ -x /System/Tools/generate-lightdm-config ]; then
  /System/Tools/generate-lightdm-config
fi

if [ "${AUZIX_LIGHTDM_AUTOLOGIN:-0}" = "1" ] &&
   [ -s /System/Settings/lightdm/lightdm-autologin.conf.template ]; then
  "${BB}" cp -f /System/Settings/lightdm/lightdm-autologin.conf.template /System/Settings/lightdm/lightdm.conf 2>/dev/null || true
fi

"${BB}" chown -R lightdm:lightdm /System/State/lightdm /System/Logs/lightdm /run/lightdm 2>/dev/null || true
"${BB}" chmod 0755 /System/State/lightdm /System/Logs/lightdm /run/lightdm 2>/dev/null || true

echo "lightdm-stage=starting" >>"${log}"
exec /System/Compatibility/sbin/lightdm --config /System/Settings/lightdm/lightdm.conf --debug >>"${log}" 2>&1
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/start-lightdm-stage"

cat > "${AUZIX_ROOT}/System/Tools/start-gui-stage" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -u

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox

ensure_dbus_machine_id() {
  "${BB}" mkdir -p /System/State/dbus /var/lib/dbus /etc 2>/dev/null || true

  machine_id=""
  if [ -s /etc/machine-id ]; then
    machine_id="$("${BB}" head -n 1 /etc/machine-id 2>/dev/null || true)"
  elif [ -s /var/lib/dbus/machine-id ]; then
    machine_id="$("${BB}" head -n 1 /var/lib/dbus/machine-id 2>/dev/null || true)"
  elif [ -s /System/State/dbus/machine-id ]; then
    machine_id="$("${BB}" head -n 1 /System/State/dbus/machine-id 2>/dev/null || true)"
  fi

  if [ -z "${machine_id}" ] && [ -r /proc/sys/kernel/random/uuid ]; then
    machine_id="$("${BB}" tr -d '-' </proc/sys/kernel/random/uuid 2>/dev/null || true)"
  fi
  [ -n "${machine_id}" ] || machine_id=00000000000000000000000000000000

  printf '%s\n' "${machine_id}" >/System/State/dbus/machine-id 2>/dev/null || true
  "${BB}" cp -f /System/State/dbus/machine-id /etc/machine-id 2>/dev/null || true
  "${BB}" cp -f /System/State/dbus/machine-id /var/lib/dbus/machine-id 2>/dev/null || true
  "${BB}" chmod 0444 /etc/machine-id 2>/dev/null || true
  "${BB}" chmod 0644 /var/lib/dbus/machine-id /System/State/dbus/machine-id 2>/dev/null || true
}

ensure_dbus_machine_id
/System/Tools/prepare-livecd-state

manager="${AUZIX_DISPLAY_MANAGER:-}"
if [ -z "${manager}" ] && [ -s /System/Settings/display/autostart ]; then
  manager="$("${BB}" head -n 1 /System/Settings/display/autostart 2>/dev/null || true)"
fi
[ -n "${manager}" ] || manager=x11

if [ "${manager}" = "lightdm" ]; then
  if "${BB}" ps | "${BB}" grep -E "[/]lightdm( |$)|[l]ightdm-gtk-greeter" >/dev/null 2>&1; then
    echo "gui-stage=already-running manager=lightdm"
    exit 0
  fi
  /System/Tools/start-lightdm-stage >/System/Logs/lightdm/start-lightdm-stage.outer.log 2>&1 &
  echo "gui-stage=starting manager=lightdm"
  exit 0
fi

if "${BB}" pidof start-e-supervisor enlightenment enlightenment_start Xorg xinit >/dev/null 2>&1; then
  echo "gui-stage=already-running"
  exit 0
fi

mode="${AUZIX_E_MODE:-x11}"
vt="${AUZIX_X_VT:-7}"
"${BB}" rm -f /System/State/display/stop-gui 2>/dev/null || true
env="HOME=/Users/auzix XDG_RUNTIME_DIR=/run/user/1000 AUZIX_E_MODE=${mode} AUZIX_X_VT=${vt}"
"${BB}" openvt -c "${vt}" -s -- "${BB}" su auzix -c "${env} /System/Tools/start-e-supervisor" \
  >/System/Logs/display/openvt.log 2>&1 &
echo "gui-stage=starting mode=${mode} vt=${vt}"
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/start-gui-stage"

cat > "${AUZIX_ROOT}/System/Boot/InstalledInit" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -u

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox

/System/Boot/StartSequence

echo
echo "Auzix installed-root shell"
echo "startup=/System/Boot/StartSequence"
echo "gui=/System/Tools/start-gui-stage"
echo

if [ -c /dev/tty1 ]; then
  "${BB}" setsid "${BB}" sh -c 'echo "Auzix console shell. Run /System/Tools/start-gui-stage for desktop." >/dev/tty1; exec /Programs/BusyBox/1.36.1/Commands/busybox sh </dev/tty1 >/dev/tty1 2>&1' &
fi

if [ -c /dev/ttyS0 ]; then
  "${BB}" setsid "${BB}" sh -c 'exec /Programs/BusyBox/1.36.1/Commands/busybox sh </dev/ttyS0 >/dev/ttyS0 2>&1' &
fi

if [ -e /System/Settings/display/autostart ] &&
   [ "$(cat /System/Settings/display/autostart 2>/dev/null)" != "manual" ]; then
  exec "${BB}" sh -c 'while true; do sleep 3600; done'
fi

exec "${BB}" cttyhack "${BB}" sh
SCRIPT

chmod 0755 "${AUZIX_ROOT}/System/Boot/InstalledInit"
cp "${AUZIX_ROOT}/System/Boot/InstalledInit" "${AUZIX_ROOT}/init"
chmod 0755 "${AUZIX_ROOT}/init"
cat > "${AUZIX_ROOT}/System/Settings/display/autostart" <<'TXT'
x11
TXT

cat > "${AUZIX_ROOT}/System/Tools/auzix-load-module" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -u

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox
KREL="$(uname -r)"
BASE="/System/Drivers/${KREL}"
DEPS="${BASE}/modules.dep"
"${BB}" mkdir -p /run

module_key() {
  local path
  path="$1"
  "${BB}" basename "${path}" .ko | "${BB}" tr '-' '_'
}

is_loaded() {
  local key
  key="$(module_key "$1")"
  "${BB}" grep -q "^${key} " /proc/modules 2>/dev/null
}

line_for_module() {
  local module first second third
  module="$1"
  first="${module}.ko"
  second="$(echo "${module}" | "${BB}" tr '_' '-').ko"
  third="$(echo "${module}" | "${BB}" tr '-' '_').ko"

  "${BB}" grep -m 1 "/${first}:" "${DEPS}" 2>/dev/null && return 0
  if [ "${second}" != "${first}" ]; then
    "${BB}" grep -m 1 "/${second}:" "${DEPS}" 2>/dev/null && return 0
  fi
  if [ "${third}" != "${first}" ]; then
    "${BB}" grep -m 1 "/${third}:" "${DEPS}" 2>/dev/null && return 0
  fi
  return 1
}

load_path() {
  local rel path key deps reversed dep_line dep err
  rel="$1"
  path="${BASE}/${rel}"
  key="$(module_key "${rel}")"
  deps=""
  reversed=""

  is_loaded "${rel}" && return 0

  dep_line=""
  if [ -f "${DEPS}" ]; then
    dep_line="$("${BB}" grep -m 1 "^${rel}:" "${DEPS}" 2>/dev/null || true)"
  fi
  if [ -n "${dep_line}" ]; then
    deps="${dep_line#*:}"
    for dep in ${deps}; do
      reversed="${dep} ${reversed}"
    done
    for dep in ${reversed}; do
      [ -n "${dep}" ] || continue
      load_path "${dep}" || true
    done
  fi

  if [ -f "${path}" ]; then
    err="/run/auzix-insmod.err"
    : > "${err}"
    if "${BB}" insmod "${path}" 2>"${err}"; then
      return 0
    fi
    if "${BB}" grep -q "File exists" "${err}" 2>/dev/null; then
      return 0
    fi
    "${BB}" cat "${err}" >&2
  fi

  is_loaded "${rel}"
}

load_module() {
  local module dep_line
  module="$1"
  case "${module}" in
    kernel/*.ko) load_path "${module}" ;;
    *)
      [ -f "${DEPS}" ] || return 1
      dep_line="$(line_for_module "${module}" || true)"
      [ -n "${dep_line}" ] || return 1
      load_path "${dep_line%%:*}"
      ;;
  esac
}

status=0
for module in "$@"; do
  load_module "${module}" || {
    echo "module-unavailable=${module}" >&2
    status=1
  }
done
exit "${status}"
SCRIPT

chmod 0755 "${AUZIX_ROOT}/System/Tools/auzix-load-module"

cat > "${AUZIX_ROOT}/System/Tools/auzix-hw-detect" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -u

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox
MODE="${1:-manual}"
LOG=/System/Logs/display/hardware.log
LOAD=/System/Tools/auzix-load-module

"${BB}" mkdir -p /System/Logs/display /System/State/display /dev

log() {
  echo "$*" | "${BB}" tee -a "${LOG}"
}

load_best_effort() {
  [ -x "${LOAD}" ] || return 0
  for module in "$@"; do
    "${LOAD}" "${module}" >>"${LOG}" 2>&1 || true
  done
}

load_path_best_effort() {
  base="/System/Drivers/$(uname -r)"
  for rel in "$@"; do
    [ -f "${base}/${rel}" ] || continue
    err="${XDG_RUNTIME_DIR:-/tmp}/auzix-hw-insmod.err"
    : > "${err}"
    if ! "${BB}" insmod "${base}/${rel}" >>"${LOG}" 2>"${err}"; then
      "${BB}" grep -q "File exists" "${err}" 2>/dev/null || "${BB}" cat "${err}" >>"${LOG}" 2>/dev/null || true
    fi
  done
}

load_bochs_drm() {
  load_path_best_effort \
    kernel/drivers/gpu/drm/drm.ko \
    kernel/drivers/gpu/drm/drm_kms_helper.ko \
    kernel/drivers/gpu/drm/ttm/ttm.ko \
    kernel/drivers/gpu/drm/drm_ttm_helper.ko \
    kernel/drivers/gpu/drm/drm_vram_helper.ko \
    kernel/drivers/gpu/drm/tiny/bochs.ko
}

load_virtio_drm() {
  load_path_best_effort \
    kernel/drivers/virtio/virtio.ko \
    kernel/drivers/virtio/virtio_ring.ko \
    kernel/drivers/virtio/virtio_dma_buf.ko \
    kernel/drivers/gpu/drm/drm.ko \
    kernel/drivers/gpu/drm/drm_kms_helper.ko \
    kernel/drivers/gpu/drm/drm_shmem_helper.ko \
    kernel/drivers/gpu/drm/virtio/virtio-gpu.ko
}

load_intel_hda() {
  load_path_best_effort \
    kernel/drivers/leds/trigger/ledtrig-audio.ko \
    kernel/sound/soundcore.ko \
    kernel/sound/core/snd.ko \
    kernel/sound/core/snd-timer.ko \
    kernel/sound/core/snd-pcm.ko \
    kernel/sound/core/snd-hwdep.ko \
    kernel/sound/hda/snd-intel-sdw-acpi.ko \
    kernel/sound/hda/snd-intel-dspcfg.ko \
    kernel/sound/hda/snd-hda-core.ko \
    kernel/sound/pci/hda/snd-hda-codec.ko \
    kernel/sound/pci/hda/snd-hda-codec-generic.ko \
    kernel/sound/pci/hda/snd-hda-intel.ko
}

: > "${LOG}"
log "mode=${MODE}"
log "kernel=$(uname -r)"

load_best_effort \
  uhci-hcd ehci-hcd ehci-pci xhci-hcd xhci-pci \
  evdev joydev psmouse hid-generic usbhid

for dev in /sys/bus/pci/devices/*; do
  [ -e "${dev}/vendor" ] || continue
  vendor="$(cat "${dev}/vendor" 2>/dev/null || true)"
  device="$(cat "${dev}/device" 2>/dev/null || true)"
  class="$(cat "${dev}/class" 2>/dev/null || true)"
  slot="${dev##*/}"
  log "pci=${slot} vendor=${vendor} device=${device} class=${class}"

  case "${class}" in
    0x03*)
      case "${vendor}:${device}" in
        0x1234:0x1111) load_bochs_drm ;;
        0x1b36:0x0100) load_best_effort qxl ;;
        0x1af4:*) load_virtio_drm ;;
        *) load_bochs_drm; load_best_effort qxl; load_virtio_drm ;;
      esac
      ;;
    0x0403*)
      load_intel_hda
      ;;
  esac
done

"${BB}" mdev -s 2>/dev/null || true
"${BB}" chmod 0666 /dev/null 2>/dev/null || true
"${BB}" chmod 0666 /dev/random /dev/urandom 2>/dev/null || true

log "drm=$("${BB}" ls /sys/class/drm 2>/dev/null | "${BB}" tr '\n' ' ')"
log "dri=$("${BB}" ls /dev/dri 2>/dev/null | "${BB}" tr '\n' ' ')"
log "input=$("${BB}" ls /sys/class/input 2>/dev/null | "${BB}" tr '\n' ' ')"
log "sound=$("${BB}" ls /sys/class/sound 2>/dev/null | "${BB}" tr '\n' ' ')"

for node in /dev/dri/card*; do
  [ -e "${node}" ] || continue
  "${BB}" chgrp video "${node}" 2>/dev/null || true
  "${BB}" chmod 0660 "${node}" 2>/dev/null || true
done
for node in /dev/dri/renderD*; do
  [ -e "${node}" ] || continue
  "${BB}" chgrp render "${node}" 2>/dev/null || true
  "${BB}" chmod 0660 "${node}" 2>/dev/null || true
done
for node in /dev/input/event* /dev/input/mice /dev/input/mouse*; do
  [ -e "${node}" ] || continue
  "${BB}" chgrp input "${node}" 2>/dev/null || true
  "${BB}" chmod 0660 "${node}" 2>/dev/null || true
done
for node in /dev/snd/*; do
  [ -e "${node}" ] || continue
  "${BB}" chgrp audio "${node}" 2>/dev/null || true
  "${BB}" chmod 0660 "${node}" 2>/dev/null || true
done

exit 0
SCRIPT

chmod 0755 "${AUZIX_ROOT}/System/Tools/auzix-hw-detect"

mkdir -p \
  "${AUZIX_ROOT}/System/Settings/xdg/menus" \
  "${AUZIX_ROOT}/System/Compatibility/usr/share/desktop-directories"

cat > "${AUZIX_ROOT}/System/Settings/xdg/menus/e-applications.menu" <<'EOF_MENU'
<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
 "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">
<Menu>
  <Name>Applications</Name>
  <DefaultAppDirs/>
  <DefaultDirectoryDirs/>
  <Directory>auzix-applications.directory</Directory>

  <Menu>
    <Name>System</Name>
    <Directory>auzix-system.directory</Directory>
    <Include>
      <Category>System</Category>
      <Category>TerminalEmulator</Category>
    </Include>
  </Menu>

  <Menu>
    <Name>Internet</Name>
    <Directory>auzix-internet.directory</Directory>
    <Include>
      <Category>Network</Category>
      <Category>WebBrowser</Category>
    </Include>
  </Menu>

  <Menu>
    <Name>Multimedia</Name>
    <Directory>auzix-multimedia.directory</Directory>
    <Include>
      <Category>AudioVideo</Category>
      <Category>Audio</Category>
      <Category>Video</Category>
    </Include>
  </Menu>

  <Menu>
    <Name>Settings</Name>
    <Directory>auzix-settings.directory</Directory>
    <Include>
      <Category>Settings</Category>
    </Include>
  </Menu>

  <Menu>
    <Name>Other</Name>
    <Directory>auzix-other.directory</Directory>
    <OnlyUnallocated/>
    <Include>
      <All/>
    </Include>
  </Menu>
</Menu>
EOF_MENU

cat > "${AUZIX_ROOT}/System/Compatibility/usr/share/desktop-directories/auzix-applications.directory" <<'EOF_DIRECTORY'
[Desktop Entry]
Type=Directory
Name=Applications
Icon=applications-other
EOF_DIRECTORY

cat > "${AUZIX_ROOT}/System/Compatibility/usr/share/desktop-directories/auzix-system.directory" <<'EOF_DIRECTORY'
[Desktop Entry]
Type=Directory
Name=System
Icon=applications-system
EOF_DIRECTORY

cat > "${AUZIX_ROOT}/System/Compatibility/usr/share/desktop-directories/auzix-internet.directory" <<'EOF_DIRECTORY'
[Desktop Entry]
Type=Directory
Name=Internet
Icon=applications-internet
EOF_DIRECTORY

cat > "${AUZIX_ROOT}/System/Compatibility/usr/share/desktop-directories/auzix-multimedia.directory" <<'EOF_DIRECTORY'
[Desktop Entry]
Type=Directory
Name=Multimedia
Icon=applications-multimedia
EOF_DIRECTORY

cat > "${AUZIX_ROOT}/System/Compatibility/usr/share/desktop-directories/auzix-settings.directory" <<'EOF_DIRECTORY'
[Desktop Entry]
Type=Directory
Name=Settings
Icon=preferences-system
EOF_DIRECTORY

cat > "${AUZIX_ROOT}/System/Compatibility/usr/share/desktop-directories/auzix-other.directory" <<'EOF_DIRECTORY'
[Desktop Entry]
Type=Directory
Name=Other
Icon=applications-other
EOF_DIRECTORY

cat > "${AUZIX_ROOT}/System/Tools/start-enlightenment-session" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -u

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands:/Programs/EFL/1.28.1/Commands:/Programs/Enlightenment/0.27.1/Commands:/System/Compatibility/usr/bin
export PATH

BB=/Programs/BusyBox/1.36.1/Commands/busybox
export HOME="${HOME:-/Users/auzix}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-enlightenment}"
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Enlightenment}"
export XDG_MENU_PREFIX="${XDG_MENU_PREFIX:-e-}"
export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/Programs/Enlightenment/host/Resources/share:/Programs/EFL/host/Resources/share:/System/Compatibility/usr/local/share:/System/Compatibility/usr/share:/usr/local/share:/usr/share}"
export XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/System/Settings/xdg:/System/Compatibility/etc/xdg:/etc/xdg}"
export E_PREFIX="${E_PREFIX:-/usr}"
export E_BIN_DIR="${E_BIN_DIR:-/usr/bin}"
export E_LIB_DIR="${E_LIB_DIR:-/usr/lib/x86_64-linux-gnu}"
export E_DATA_DIR="${E_DATA_DIR:-/usr/share/enlightenment}"
export E_CONF_DIR="${E_CONF_DIR:-/System/Settings/desktop/enlightenment}"
export E_HOME_DIR="${E_HOME_DIR:-${HOME}/.e/e}"
export ELEMENTARY_THEME="${ELEMENTARY_THEME:-default}"
export ELM_CONFIG_DIR="${ELM_CONFIG_DIR:-/System/Settings/desktop/elementary}"
export ECORE_EVAS_ENGINE="${ECORE_EVAS_ENGINE:-software_x11}"
export ELM_ENGINE="${ELM_ENGINE:-software_x11}"
export ELM_ACCEL="${ELM_ACCEL:-none}"
export E_COMP_ENGINE="${E_COMP_ENGINE:-sw}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export SSL_CERT_DIR="${SSL_CERT_DIR:-/etc/ssl/certs}"
export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
export CURL_CA_BUNDLE="${CURL_CA_BUNDLE:-${SSL_CERT_FILE}}"
export REQUESTS_CA_BUNDLE="${REQUESTS_CA_BUNDLE:-${SSL_CERT_FILE}}"
export GCONV_PATH="${GCONV_PATH:-/usr/lib/x86_64-linux-gnu/gconv:/System/Compatibility/usr/lib/x86_64-linux-gnu/gconv:/System/Compatibility/lib/x86_64-linux-gnu/gconv}"
export E_START="${E_START:-1}"
export E_MODULE_TUNING="${E_MODULE_TUNING:-vm-safe}"
export AUZIX_MASK_GL_EVAS="${AUZIX_MASK_GL_EVAS:-1}"
export AUZIX_MASK_UNSTABLE_E_MODULES="${AUZIX_MASK_UNSTABLE_E_MODULES:-1}"

mask_evas_gl_engines() {
  [ "${AUZIX_MASK_GL_EVAS}" = "1" ] || return 0
  disabled_dir=/System/State/desktop/enlightenment/disabled-evas-engines
  engine_root=/System/Compatibility/usr/lib/x86_64-linux-gnu/evas/modules/engines
  [ -d "${engine_root}" ] || return 0
  "${BB}" mkdir -p "${disabled_dir}" 2>/dev/null || true
  for engine in gl_x11 gl_drm wayland_egl; do
    if [ -d "${engine_root}/${engine}" ]; then
      "${BB}" mv "${engine_root}/${engine}" "${disabled_dir}/${engine}" 2>/dev/null || true
    fi
  done
}

mask_unstable_enlightenment_modules() {
  [ "${AUZIX_MASK_UNSTABLE_E_MODULES}" = "1" ] || return 0
  disabled_dir=/System/State/desktop/enlightenment/disabled-modules
  module_root=/System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/modules
  "${BB}" mkdir -p "${disabled_dir}" 2>/dev/null || true
  for module in \
    wizard \
    connman \
    bluez5 \
    packagekit \
    geolocation \
    battery \
    cpufreq \
    temperature \
    backlight \
    wl_buffer \
    wl_desktop_shell \
    wl_drm \
    wl_text_input \
    wl_weekeyboard \
    wl_wl \
    wl_x11 \
    xwayland; do
    if [ -d "${module_root}/${module}" ]; then
      "${BB}" mv "${module_root}/${module}" "${disabled_dir}/${module}" 2>/dev/null || true
    fi
    "${BB}" rm -f "${HOME}/.e/e/config/standard/module.${module}.cfg" 2>/dev/null || true
  done
}

normalize_enlightenment_profile() {
  [ "${E_MODULE_TUNING}" = "vm-safe" ] || return 0
  command -v eet >/dev/null 2>&1 || return 0

  profile_dir="${HOME}/.e/e/config/standard"
  "${BB}" mkdir -p "${profile_dir}" /System/State/desktop/enlightenment 2>/dev/null || true

  if [ "${AUZIX_FORCE_E_PROFILE:-standard}" = "standard" ]; then
    "${BB}" mkdir -p "${HOME}/.e/e/config" 2>/dev/null || true
    profile_tmp="${XDG_CACHE_HOME:-${HOME}/.cache}/auzix-e-profile"
    printf standard > "${profile_tmp}"
    eet -i "${HOME}/.e/e/config/profile.cfg" config "${profile_tmp}" 0 2>/dev/null || true
    "${BB}" rm -f "${profile_tmp}" 2>/dev/null || true
  fi

  if [ ! -s "${profile_dir}/e_comp.cfg" ] &&
     [ -s /System/Settings/display/assets/config/standard/e_comp.cfg ]; then
    "${BB}" cp -f /System/Settings/display/assets/config/standard/e_comp.cfg "${profile_dir}/e_comp.cfg" 2>/dev/null || true
  fi

  if [ -s "${profile_dir}/e_comp.cfg" ]; then
    comp_txt="${XDG_CACHE_HOME:-${HOME}/.cache}/e_comp.cfg.txt"
    comp_new="${XDG_CACHE_HOME:-${HOME}/.cache}/e_comp.cfg.new"
    if eet -d "${profile_dir}/e_comp.cfg" config "${comp_txt}" 2>/dev/null; then
      "${BB}" sed \
        -e 's/value "engine" int: [0-9][0-9]*;/value "engine" int: 1;/' \
        -e 's/value "vsync" uchar: [0-9][0-9]*;/value "vsync" uchar: 0;/' \
        -e 's/value "smooth_windows" uchar: [0-9][0-9]*;/value "smooth_windows" uchar: 0;/' \
        "${comp_txt}" > "${comp_txt}.safe" 2>/dev/null || true
      if [ -s "${comp_txt}.safe" ] &&
         eet -e "${comp_new}" config "${comp_txt}.safe" 0 2>/dev/null; then
        "${BB}" cp -f "${comp_new}" "${profile_dir}/e_comp.cfg" 2>/dev/null || true
        "${BB}" rm -f "${comp_new}" 2>/dev/null || true
      fi
    fi
  fi

  if [ -s "${profile_dir}/e.cfg" ]; then
    e_txt="${XDG_CACHE_HOME:-${HOME}/.cache}/e.cfg.txt"
    e_new="${XDG_CACHE_HOME:-${HOME}/.cache}/e.cfg.new"
    if eet -d "${profile_dir}/e.cfg" config "${e_txt}" 2>/dev/null; then
      "${BB}" awk -v drop=" battery cpufreq temperature backlight connman bluez5 packagekit geolocation wizard wl_buffer wl_desktop_shell wl_drm wl_text_input wl_weekeyboard wl_wl wl_x11 xwayland " '
        /^        group "E_Config_Module" struct \{/ ||
        /^                group "E_Config_Gadcon_Client" struct \{/ {
          in_drop_block = 1
          skip = 0
          block = $0 "\n"
          next
        }
        in_drop_block {
          block = block $0 "\n"
          if ($0 ~ /value "name" string: "/) {
            name = $0
            sub(/^.*value "name" string: "/, "", name)
            sub(/";.*$/, "", name)
            if (index(drop, " " name " ") > 0) skip = 1
          }
          if ($0 ~ /^[ ]*\}$/) {
            if (!skip) printf "%s", block
            in_drop_block = 0
            block = ""
          }
          next
        }
        { print }
      ' "${e_txt}" > "${e_txt}.safe" 2>/dev/null || true
      if [ -s "${e_txt}.safe" ] &&
         eet -e "${e_new}" config "${e_txt}.safe" 0 2>/dev/null; then
        "${BB}" mv "${e_new}" "${profile_dir}/e.cfg" 2>/dev/null || true
      fi
    fi
  fi

  "${BB}" rm -f \
    "${profile_dir}/module.battery.cfg" \
    "${profile_dir}/module.cpufreq.cfg" \
    "${profile_dir}/module.temperature.cfg" \
    "${profile_dir}/module.backlight.cfg" \
    "${profile_dir}/module.connman.cfg" \
    "${profile_dir}/module.bluez5.cfg" \
    "${profile_dir}/module.packagekit.cfg" \
    "${profile_dir}/module.geolocation.cfg" 2>/dev/null || true
  "${BB}" chown -R "$(id -u 2>/dev/null || echo 1000):$(id -g 2>/dev/null || echo 1000)" \
    "${HOME}/.e" 2>/dev/null || true
}

"${BB}" mkdir -p \
  "${HOME}/.cache" \
  "${HOME}/.config" \
  "${HOME}/.local/share" \
  "${HOME}/.cache/efreet" \
  "${HOME}/.e/e" \
  /System/Settings/desktop/enlightenment \
  /System/Settings/desktop/elementary \
  /System/State/desktop/enlightenment \
  /System/Logs/display 2>/dev/null || true
"${BB}" chown -R "$(id -u 2>/dev/null || echo 1000):$(id -g 2>/dev/null || echo 1000)" \
  "${HOME}/.cache" "${HOME}/.config" "${HOME}/.e" \
  "${HOME}/.local" \
	  /System/Settings/desktop /System/State/desktop 2>/dev/null || true

mask_evas_gl_engines
mask_unstable_enlightenment_modules
normalize_enlightenment_profile

start_efreet_session() {
  [ "${AUZIX_PRESTART_EFREETD:-0}" = "1" ] || return 0
  command -v efreetd >/dev/null 2>&1 || return 0
  if "${BB}" ps | "${BB}" grep '[e]freetd' >/dev/null 2>&1; then
    return 0
  fi
  "${BB}" mkdir -p "${XDG_CACHE_HOME}/efreet" /System/Logs/display 2>/dev/null || true
  efreetd >>/System/Logs/display/efreetd.log 2>&1 &
  "${BB}" sleep 1
}

start_efreet_session

if command -v pulseaudio >/dev/null 2>&1 || command -v pipewire >/dev/null 2>&1; then
  disabled_dir=/System/State/desktop/enlightenment/disabled-modules
  for module in mixer music-control; do
    if [ -d "${disabled_dir}/${module}" ] &&
       [ ! -e "/System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/modules/${module}" ]; then
      "${BB}" mv "${disabled_dir}/${module}" "/System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/modules/${module}" 2>/dev/null || true
    fi
  done
elif [ "${AUZIX_MASK_NOAUDIO_MODULES:-1}" = "1" ]; then
  disabled_dir=/System/State/desktop/enlightenment/disabled-modules
  "${BB}" mkdir -p "${disabled_dir}" 2>/dev/null || true
  for module in mixer music-control; do
    if [ -d "/System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/modules/${module}" ]; then
      "${BB}" mv "/System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/modules/${module}" "${disabled_dir}/${module}" 2>/dev/null || true
    fi
    "${BB}" rm -f "${HOME}/.e/e/config/standard/module.${module}.cfg" 2>/dev/null || true
  done
fi

if [ "${E_MODULE_TUNING}" = "vm-safe" ] && command -v enlightenment_remote >/dev/null 2>&1; then
  (
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
      "${BB}" sleep 2
      DISPLAY="${DISPLAY:-:0}" enlightenment_remote -module-list >/dev/null 2>&1 && break
    done
    for module in mixer music-control bluez5 connman packagekit geolocation battery cpufreq temperature backlight wizard wl_buffer wl_desktop_shell wl_drm wl_text_input wl_weekeyboard wl_wl wl_x11 xwayland; do
      DISPLAY="${DISPLAY:-:0}" enlightenment_remote -module-disable "${module}" >/dev/null 2>&1 || true
      DISPLAY="${DISPLAY:-:0}" enlightenment_remote -module-unload "${module}" >/dev/null 2>&1 || true
    done
  ) >>/System/Logs/display/e-module-tuning.log 2>&1 &
fi

if [ "${AUZIX_USE_ENLIGHTENMENT_START:-1}" = "1" ] &&
   [ -x /usr/bin/enlightenment_start ]; then
  exec /usr/bin/enlightenment_start "$@"
fi

if [ "${AUZIX_USE_ENLIGHTENMENT_START:-1}" = "1" ] &&
   command -v enlightenment_start >/dev/null 2>&1; then
  exec enlightenment_start "$@"
fi

exec enlightenment "$@"
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/start-enlightenment-session"

cat > "${AUZIX_ROOT}/System/Tools/start-e" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -u

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands:/Programs/Xorg/current/Commands:/Programs/Xorg/host/Commands:/Programs/EFL/current/Commands:/Programs/EFL/host/Commands:/Programs/EFL/1.28.1/Commands:/Programs/Enlightenment/current/Commands:/Programs/Enlightenment/host/Commands:/Programs/Enlightenment/0.27.1/Commands:/System/Compatibility/usr/bin:/System/Compatibility/bin
export PATH

BB=/Programs/BusyBox/1.36.1/Commands/busybox
MODE="${AUZIX_E_MODE:-x11}"
LOG=/System/Logs/display/start-e.log

export HOME="${HOME:-/Users/root}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"
export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-enlightenment}"
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Enlightenment}"
export XDG_MENU_PREFIX="${XDG_MENU_PREFIX:-e-}"
export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/Programs/Enlightenment/host/Resources/share:/Programs/EFL/host/Resources/share:/System/Compatibility/usr/local/share:/System/Compatibility/usr/share:/usr/local/share:/usr/share}"
export XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/System/Settings/xdg:/System/Compatibility/etc/xdg:/etc/xdg}"
export XORG_RUN_AS_USER_OK="${XORG_RUN_AS_USER_OK:-1}"
export XKB_BINDIR="${XKB_BINDIR:-/Programs/Xorg/current/Commands}"
export XKB_CONFIG_ROOT="${XKB_CONFIG_ROOT:-/System/Settings/X11/xkb}"
export XLOCALEDIR="${XLOCALEDIR:-/System/Compatibility/usr/share/X11/locale}"
export ECORE_EVAS_ENGINE="${ECORE_EVAS_ENGINE:-software_x11}"
export ELM_ENGINE="${ELM_ENGINE:-software_x11}"
export ELM_ACCEL="${ELM_ACCEL:-none}"
export E_COMP_ENGINE="${E_COMP_ENGINE:-sw}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export SSL_CERT_DIR="${SSL_CERT_DIR:-/etc/ssl/certs}"
export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
export CURL_CA_BUNDLE="${CURL_CA_BUNDLE:-${SSL_CERT_FILE}}"
export REQUESTS_CA_BUNDLE="${REQUESTS_CA_BUNDLE:-${SSL_CERT_FILE}}"
export GCONV_PATH="${GCONV_PATH:-/usr/lib/x86_64-linux-gnu/gconv:/System/Compatibility/usr/lib/x86_64-linux-gnu/gconv:/System/Compatibility/lib/x86_64-linux-gnu/gconv}"
export LANG="${LANG:-C}"
export LC_ALL="${LC_ALL:-C}"
"${BB}" mkdir -p /System/Logs/display /System/State/display /Work/Temp /dev/shm 2>/dev/null || true
"${BB}" mount -t tmpfs tmpfs /dev/shm -o mode=1777,nosuid,nodev 2>/dev/null || true
"${BB}" chmod 1777 /dev/shm /Work/Temp /tmp 2>/dev/null || true
"${BB}" touch "${LOG}" 2>/dev/null || LOG="${HOME}/.auzix-start-e.log"
"${BB}" mkdir -p "${HOME}" "${XDG_RUNTIME_DIR}" "${XDG_CACHE_HOME}" "${XDG_CONFIG_HOME}" "${XDG_DATA_HOME}" "${XDG_CACHE_HOME}/efreet"
"${BB}" chmod 0700 "${XDG_RUNTIME_DIR}" 2>/dev/null || true
"${BB}" chmod 0666 /dev/ptmx /dev/pts/ptmx 2>/dev/null || true

if [ "${HOME}" = "/Users/auzix" ]; then
  "${BB}" mkdir -p \
    /Users/auzix/.cache \
    /Users/auzix/.cache/efreet \
    /Users/auzix/.config \
    /Users/auzix/.e/e \
    /Users/auzix/.elementary/config/standard 2>/dev/null || true
  if [ ! -s /Users/auzix/.e/e/config/standard/e.cfg ] &&
     [ -d /usr/share/enlightenment/data/config/standard ]; then
    "${BB}" mkdir -p /Users/auzix/.e/e/config
    "${BB}" cp -a /usr/share/enlightenment/data/config/standard /Users/auzix/.e/e/config/ 2>/dev/null || true
  fi
  if [ ! -s /Users/auzix/.e/e/config/profile.cfg ] &&
     command -v eet >/dev/null 2>&1; then
    printf standard > /run/auzix-e-profile
    eet -i /Users/auzix/.e/e/config/profile.cfg config /run/auzix-e-profile 0 2>/dev/null || true
    "${BB}" rm -f /run/auzix-e-profile 2>/dev/null || true
  fi
  if [ "${AUZIX_FORCE_E_PROFILE:-standard}" = "standard" ] &&
     command -v eet >/dev/null 2>&1; then
    printf standard > /run/auzix-e-profile
    eet -i /Users/auzix/.e/e/config/profile.cfg config /run/auzix-e-profile 0 2>/dev/null || true
    "${BB}" rm -f /run/auzix-e-profile 2>/dev/null || true
	  fi
	  "${BB}" chown -R "$(id -u 2>/dev/null || echo 1000):$(id -g 2>/dev/null || echo 1000)" /Users/auzix 2>/dev/null || true
	  if [ -x /System/Tools/repair-e-state ]; then
	    /System/Tools/repair-e-state /Users/auzix auzix >/System/Logs/display/repair-e-state.log 2>&1 || true
	  fi
fi

if [ -x /System/Tools/auzix-hw-detect ]; then
  /System/Tools/auzix-hw-detect display >/System/Logs/display/hardware-display.log 2>&1 ||
    /System/Tools/auzix-hw-detect display >"${HOME}/.auzix-hardware-display.log" 2>&1 || true
fi

ensure_dbus_machine_id() {
  "${BB}" mkdir -p /System/State/dbus /var/lib/dbus /etc 2>/dev/null || true

  machine_id=""
  if [ -s /etc/machine-id ]; then
    machine_id="$("${BB}" head -n 1 /etc/machine-id 2>/dev/null || true)"
  elif [ -s /var/lib/dbus/machine-id ]; then
    machine_id="$("${BB}" head -n 1 /var/lib/dbus/machine-id 2>/dev/null || true)"
  elif [ -s /System/State/dbus/machine-id ]; then
    machine_id="$("${BB}" head -n 1 /System/State/dbus/machine-id 2>/dev/null || true)"
  fi

  if [ -z "${machine_id}" ] && [ -r /proc/sys/kernel/random/uuid ]; then
    machine_id="$("${BB}" tr -d '-' </proc/sys/kernel/random/uuid 2>/dev/null || true)"
  fi
  if [ -z "${machine_id}" ]; then
    machine_id="$(date +%s 2>/dev/null || echo 0)$("${BB}" cat /proc/sys/kernel/random/boot_id 2>/dev/null | "${BB}" tr -d '-' 2>/dev/null || true)"
    machine_id="$(printf '%s' "${machine_id}" | "${BB}" tr -cd '0123456789abcdef' | "${BB}" cut -c1-32)"
  fi
  [ -n "${machine_id}" ] || machine_id=00000000000000000000000000000000

  dbus_state_dir=/System/State/dbus
  if ! ( : >"${dbus_state_dir}/.write-test" ) 2>/dev/null; then
    dbus_state_dir=/run/dbus-state
    "${BB}" mkdir -p "${dbus_state_dir}" 2>/dev/null || true
  else
    "${BB}" rm -f "${dbus_state_dir}/.write-test" 2>/dev/null || true
  fi

  printf '%s\n' "${machine_id}" >"${dbus_state_dir}/machine-id" 2>/dev/null || true
  "${BB}" cp -f "${dbus_state_dir}/machine-id" /etc/machine-id 2>/dev/null || true
  "${BB}" cp -f "${dbus_state_dir}/machine-id" /var/lib/dbus/machine-id 2>/dev/null || true
  "${BB}" chmod 0444 /etc/machine-id 2>/dev/null || true
  "${BB}" chmod 0644 /var/lib/dbus/machine-id "${dbus_state_dir}/machine-id" 2>/dev/null || true
}

start_system_bus() {
  if ! command -v dbus-daemon >/dev/null 2>&1; then
    return 0
  fi
  ensure_dbus_machine_id
  "${BB}" mkdir -p /run/dbus
  if [ -S /run/dbus/system_bus_socket ] &&
     "${BB}" ps | "${BB}" grep "dbus-daemon --system" | "${BB}" grep -v grep >/dev/null 2>&1; then
    return 0
  fi
  "${BB}" rm -f /run/dbus/system_bus_socket 2>/dev/null || true
  dbus-daemon --system --fork --nopidfile >/tmp/auzix-dbus-system.out 2>>"${LOG}" || true
}

start_session_bus() {
  if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    return 0
  fi
  if ! command -v dbus-daemon >/dev/null 2>&1; then
    return 0
  fi

  bus_socket="${XDG_RUNTIME_DIR}/bus"
  if [ -S "${bus_socket}" ]; then
    if "${BB}" ps | "${BB}" grep "dbus-daemon --session" | "${BB}" grep -v grep >/dev/null 2>&1; then
      export DBUS_SESSION_BUS_ADDRESS="unix:path=${bus_socket}"
      return 0
    fi
    "${BB}" rm -f "${bus_socket}" 2>/dev/null || true
  fi

  address="$(dbus-daemon --session --address="unix:path=${bus_socket}" --fork --print-address=1 --nopidfile 2>>"${LOG}" || true)"
  if [ -n "${address}" ]; then
    export DBUS_SESSION_BUS_ADDRESS="${address}"
    echo "dbus-session=${DBUS_SESSION_BUS_ADDRESS}" >>"${LOG}"
  fi
}

start_system_bus
start_session_bus

start_audio_session() {
  command -v pulseaudio >/dev/null 2>&1 || return 0
  "${BB}" mkdir -p "${XDG_RUNTIME_DIR}/pulse" /System/Logs/pulseaudio 2>/dev/null || true
  if [ -S "${XDG_RUNTIME_DIR}/pulse/native" ] &&
     "${BB}" ps | "${BB}" grep '[p]ulseaudio' >/dev/null 2>&1; then
    return 0
  fi
  pulseaudio --start --exit-idle-time=-1 \
    --log-target=file:/System/Logs/pulseaudio/session.log \
    >>"${LOG}" 2>&1 || true
}

start_audio_session

find_cmd() {
  for cmd in "$@"; do
    case "${cmd}" in
      */*)
        if [ -x "${cmd}" ]; then
          echo "${cmd}"
          return 0
        fi
        ;;
      *)
        if command -v "${cmd}" >/dev/null 2>&1; then
          command -v "${cmd}"
          return 0
        fi
        ;;
    esac
  done
  return 1
}

find_path_cmd() {
  for cmd in "$@"; do
    if command -v "${cmd}" >/dev/null 2>&1; then
      command -v "${cmd}"
      return 0
    fi
  done
  return 1
}

trace_exec() {
  if [ "${AUZIX_TRACE_E:-}" = "file" ] && command -v strace >/dev/null 2>&1; then
    "${BB}" mkdir -p /System/Logs/display/strace 2>/dev/null || true
    exec strace -ff -tt -s 160 -e trace=file,process \
      -o /System/Logs/display/strace/e "$@"
  fi
  exec "$@"
}

run_wayland() {
  enlightenment="$(find_cmd \
    /System/Tools/start-enlightenment-session \
    /Programs/Enlightenment/current/Commands/enlightenment_start \
    /Programs/Enlightenment/current/Commands/enlightenment \
    /Programs/Enlightenment/host/Commands/enlightenment_start \
    /Programs/Enlightenment/host/Commands/enlightenment \
    /System/Compatibility/bin/enlightenment_start \
    /System/Compatibility/bin/enlightenment \
    enlightenment_start enlightenment)"
  if [ -z "${enlightenment}" ]; then
    return 1
  fi
  if ! "${BB}" ls /dev/dri/card* >/dev/null 2>&1; then
    echo "mode=wayland blocked=missing-drm-card" >>"${LOG}"
    return 1
  fi
  if ! "${BB}" ls /dev/input/event* >/dev/null 2>&1; then
    echo "mode=wayland blocked=missing-input-events" >>"${LOG}"
    return 1
  fi
  echo "mode=wayland command=${enlightenment}" | "${BB}" tee "${LOG}"
  trace_exec "${enlightenment}" -wl >>"${LOG}" 2>&1
}

run_x11() {
  xinit="$(find_cmd \
    /Programs/Xorg/current/Commands/xinit \
    /Programs/Xorg/host/Commands/xinit \
    /System/Compatibility/bin/xinit \
    /System/Compatibility/usr/bin/xinit \
    xinit)"
  xorg="$(find_cmd \
    /Programs/Xorg/current/Commands/Xorg \
    /Programs/Xorg/host/Commands/Xorg \
    /System/Compatibility/bin/Xorg \
    /System/Compatibility/bin/X \
    /System/Compatibility/usr/bin/Xorg \
    /System/Compatibility/usr/bin/X \
    Xorg X)"
  enlightenment="$(find_cmd \
    /System/Tools/start-enlightenment-session \
    /Programs/Enlightenment/current/Commands/enlightenment_start \
    /Programs/Enlightenment/current/Commands/enlightenment \
    /Programs/Enlightenment/host/Commands/enlightenment_start \
    /Programs/Enlightenment/host/Commands/enlightenment \
    /System/Compatibility/bin/enlightenment_start \
    /System/Compatibility/bin/enlightenment \
    /System/Compatibility/usr/bin/enlightenment_start \
    /System/Compatibility/usr/bin/enlightenment \
    enlightenment_start enlightenment)"
  vt="${AUZIX_X_VT:-7}"
  if [ -z "${xinit}" ] || [ -z "${xorg}" ] || [ -z "${enlightenment}" ]; then
    echo "mode=x11 blocked=xinit:${xinit:-missing} xorg:${xorg:-missing} enlightenment:${enlightenment:-missing}" >>"${LOG}"
    return 1
  fi
  unset E_WL_FORCE E_ENGINE WAYLAND_DISPLAY
  export XDG_SESSION_TYPE=x11
  export XDG_SESSION_DESKTOP=enlightenment
  export XDG_CURRENT_DESKTOP=Enlightenment
  export ECORE_EVAS_ENGINE="${ECORE_EVAS_ENGINE:-software_x11}"
  export ELM_ENGINE="${ELM_ENGINE:-software_x11}"
  export ELM_ACCEL="${ELM_ACCEL:-none}"
  export E_COMP_ENGINE="${E_COMP_ENGINE:-sw}"
  export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
  export DISPLAY=:0
  echo "mode=x11 command=${xinit} ${enlightenment} -- ${xorg} :0 vt${vt} -keeptty -nolisten tcp -config xorg.conf" | "${BB}" tee "${LOG}"
  trace_exec "${xinit}" "${enlightenment}" -- "${xorg}" :0 "vt${vt}" -keeptty -nolisten tcp \
    -config xorg.conf >>"${LOG}" 2>&1
}

case "${MODE}" in
  wayland) run_wayland ;;
  x11) run_x11 ;;
  auto)
    run_x11
    ;;
  *)
    echo "Unknown AUZIX_E_MODE=${MODE}. Use auto, wayland, or x11." >&2
    exit 2
    ;;
esac

cat > "${LOG}" <<EOF
No runnable Enlightenment session was found.

Hardware snapshot:
  drm: $("${BB}" ls /sys/class/drm 2>/dev/null | "${BB}" tr '\n' ' ')
  dri: $("${BB}" ls /dev/dri 2>/dev/null | "${BB}" tr '\n' ' ')
  input: $("${BB}" ls /sys/class/input 2>/dev/null | "${BB}" tr '\n' ' ')
  sound: $("${BB}" ls /sys/class/sound 2>/dev/null | "${BB}" tr '\n' ' ')

Expected one of:
  /System/Compatibility/bin/enlightenment_start
  /System/Compatibility/bin/enlightenment
  /Programs/Enlightenment/current/Commands/enlightenment_start
  /Programs/Enlightenment/current/Commands/enlightenment
  /Programs/Enlightenment/host/Commands/enlightenment_start
  /Programs/Enlightenment/host/Commands/enlightenment
  /Programs/Enlightenment/0.27.1/Commands/enlightenment_start
  /Programs/Enlightenment/0.27.1/Commands/enlightenment
  /Programs/Xorg/current/Commands/xinit
  /Programs/Xorg/current/Commands/Xorg
  /Programs/Xorg/host/Commands/xinit
  /Programs/Xorg/host/Commands/Xorg

The build stage must provide package-owned Xorg and Enlightenment commands,
their compatibility links, input support, fonts, and writable runtime state.
Wayland is intentionally manual-only until the seat/DRM path is stable.
EOF
cat "${LOG}" >&2
exit 1
SCRIPT

chmod 0755 "${AUZIX_ROOT}/System/Tools/start-e"

cat > "${AUZIX_ROOT}/System/Tools/finalize-installed-root" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -u

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox
TARGET="${1:-/}"

case "${TARGET}" in
  "") TARGET="/" ;;
esac

target_path() {
  case "${TARGET}" in
    /) printf '%s\n' "$1" ;;
    */) printf '%s%s\n' "${TARGET%/}" "$1" ;;
    *) printf '%s%s\n' "${TARGET}" "$1" ;;
  esac
}

mkdir_p() {
  for path in "$@"; do
    "${BB}" mkdir -p "$(target_path "${path}")" 2>/dev/null || true
  done
}

chmod_path() {
  mode="$1"
  shift
  for path in "$@"; do
    [ -e "$(target_path "${path}")" ] || continue
    "${BB}" chmod "${mode}" "$(target_path "${path}")" 2>/dev/null || true
  done
}

chown_path() {
  owner="$1"
  shift
  for path in "$@"; do
    [ -e "$(target_path "${path}")" ] || continue
    "${BB}" chown -R "${owner}" "$(target_path "${path}")" 2>/dev/null || true
  done
}

mkdir_p \
  /Users \
  /Users/root \
  /Users/auzix/.cache/efreet \
  /Users/auzix/.config \
  /Users/auzix/.e/e/config \
  /Users/auzix/.elementary/config/standard \
  /Users/auzix/.local/share \
  /Users/auzix/.midori \
  /System/Logs/display \
  /System/Logs/packages \
  /System/State/dbus \
  /System/State/display \
  /System/State/packages \
  /System/State/tmp \
  /Work/Temp \
  /dev/shm \
  /run/user/1000 \
  /run/dbus \
  /run/lock

chown_path 0:0 /Users /Users/root
chmod_path 0755 /Users /Users/root /System/Logs /System/Logs/display /System/State /System/State/dbus /System/State/display
chown_path 1000:1000 /Users/auzix /run/user/1000
chmod_path 0755 /Users/auzix
chmod_path 0700 /run/user/1000
"${BB}" chmod -R u+rwX \
  "$(target_path /Users/auzix/.cache)" \
  "$(target_path /Users/auzix/.config)" \
  "$(target_path /Users/auzix/.e)" \
  "$(target_path /Users/auzix/.elementary)" \
  "$(target_path /Users/auzix/.local)" \
  "$(target_path /Users/auzix/.midori)" 2>/dev/null || true
chown_path 1000:1000 \
  /Users/auzix/.cache \
  /Users/auzix/.config \
  /Users/auzix/.e \
  /Users/auzix/.elementary \
  /Users/auzix/.local \
  /Users/auzix/.midori
chown_path 1000:1000 /System/State/packages /System/Logs/packages
chmod_path 0755 /System/State/packages /System/Logs/packages
chmod_path 1777 /Work/Temp /dev/shm

if [ -e "$(target_path /Programs/Sudo/host/Commands/sudo)" ]; then
  chown_path 0:0 /Programs/Sudo/host/Commands/sudo
  chmod_path 4755 /Programs/Sudo/host/Commands/sudo
fi
if [ -e "$(target_path /System/Compatibility/usr/lib/xorg/Xorg.wrap)" ]; then
  chown_path 0:0 /System/Compatibility/usr/lib/xorg/Xorg.wrap
  chmod_path 4755 /System/Compatibility/usr/lib/xorg/Xorg.wrap
fi
for helper in \
  /System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_system \
  /System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_sys \
  /System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_ckpasswd
do
  [ -e "$(target_path "${helper}")" ] || continue
  chown_path 0:0 "${helper}"
  chmod_path 4755 "${helper}"
done
if [ -e "$(target_path /System/Settings/sudoers)" ]; then
  chown_path 0:0 /System/Settings/sudoers /System/Settings/sudo.conf
  chmod_path 0440 /System/Settings/sudoers
fi
if [ -d "$(target_path /System/Settings/sudoers.d)" ]; then
  chown_path 0:0 /System/Settings/sudoers.d
fi
if [ -d "$(target_path /System/Compatibility/usr/libexec/sudo)" ]; then
  chown_path 0:0 /System/Compatibility/usr/libexec/sudo
fi

printf 'finalized-installed-root=%s\n' "${TARGET}"
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/finalize-installed-root"

cat > "${AUZIX_ROOT}/System/Tools/auzix-packages" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -eu

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox

usage() {
  cat <<'USAGE'
Usage:
  auzix-packages list
  auzix-packages manifest

Reports the Auzix receipt set staged under /System/PackageDB. This is not a
dependency solver; it is the live receipt view that the installer records.
USAGE
}

cmd="${1:-list}"
case "${cmd}" in
  list)
    for receipt in /System/PackageDB/*.json; do
      [ -f "${receipt}" ] || continue
      name="$("${BB}" sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${receipt}" | "${BB}" head -n 1)"
      version="$("${BB}" sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${receipt}" | "${BB}" head -n 1)"
      kind="$("${BB}" sed -n 's/.*"kind"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${receipt}" | "${BB}" head -n 1)"
      [ -n "${name}" ] || name="$("${BB}" basename "${receipt}" .json)"
      [ -n "${version}" ] || version=unknown
      [ -n "${kind}" ] || kind=unknown
      printf '%-24s %-16s %s\n' "${name}" "${version}" "${kind}"
    done
    ;;
  manifest)
    if [ -s /System/Settings/packages/installed.json ]; then
      "${BB}" cat /System/Settings/packages/installed.json
    else
      echo '{"format":"auzix-installed-v0","installed":[]}'
    fi
    ;;
  --help|-h|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
SCRIPT

chmod 0755 "${AUZIX_ROOT}/System/Tools/auzix-packages"

cat > "${AUZIX_ROOT}/System/Tools/auzix-install-package" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -eu

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox

usage() {
  cat <<'USAGE'
Usage:
  auzix-install-package [--root /path] [--sha256 HASH] package.auzix.tar.gz

Installs one Auzix package tarball into the selected root. This is deliberately
small: no dependency solving, no remote fetching, and no signatures yet.
USAGE
}

target_root="/"
expected_sha=""
package=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      target_root="${2:-}"
      shift 2
      ;;
    --sha256)
      expected_sha="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      usage >&2
      exit 2
      ;;
    *)
      package="$1"
      shift
      ;;
  esac
done

if [ -z "${package}" ] || [ -z "${target_root}" ]; then
  usage >&2
  exit 2
fi

if [ ! -f "${package}" ]; then
  echo "Package not found: ${package}" >&2
  exit 1
fi

if [ -n "${expected_sha}" ] && command -v sha256sum >/dev/null 2>&1; then
  actual_sha="$(sha256sum "${package}" | "${BB}" awk '{print $1}')"
  if [ "${actual_sha}" != "${expected_sha}" ]; then
    echo "Checksum mismatch for ${package}" >&2
    echo "expected=${expected_sha}" >&2
    echo "actual=${actual_sha}" >&2
    exit 1
  fi
fi

"${BB}" mkdir -p "${target_root}"
"${BB}" tar -xzf "${package}" -C "${target_root}"
if [ -x "${target_root%/}/System/Tools/finalize-installed-root" ]; then
  "${target_root%/}/System/Tools/finalize-installed-root" "${target_root}"
fi
echo "Installed package ${package} into ${target_root}"
SCRIPT

chmod 0755 "${AUZIX_ROOT}/System/Tools/auzix-install-package"

cat > "${AUZIX_ROOT}/System/Tools/auzix-install-disk" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -eu

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox

usage() {
  cat <<'USAGE'
Usage:
  auzix-install-disk /dev/vda
  auzix-install-disk --force /dev/vda
  auzix-install-disk --force --bootloader iso /dev/vda

This creates a journaled Linux root partition when ext4 or mke2fs is available,
copies the live Auzix root to it, and marks it as an installed Auzix root. The
default bootloader is BIOS GRUB when grub-install is available in the live
system.

With --bootloader iso, boot the installed root through the ISO with:

  auzix.root=/dev/vda1

WARNING: --force destroys the target disk partition table.
USAGE
}

force=0
bootloader=grub
target=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --force)
      force=1
      shift
      ;;
    --bootloader)
      bootloader="${2:-}"
      shift 2
      ;;
    --bootloader=*)
      bootloader="${1#--bootloader=}"
      shift
      ;;
    --*)
      usage >&2
      exit 2
      ;;
    *)
      target="$1"
      shift
      ;;
  esac
done

if [ -z "${target}" ]; then
  usage >&2
  exit 2
fi

case "${target}" in
  /dev/*) ;;
  *)
    echo "Target must be a block device path under /dev." >&2
    exit 2
    ;;
esac

if [ "${force}" -ne 1 ]; then
  echo "Refusing to alter ${target} without --force." >&2
  exit 2
fi

if [ ! -b "${target}" ]; then
  echo "Block device not found: ${target}" >&2
  exit 1
fi

partition="${target}1"
case "${target}" in
  *nvme*|*mmcblk*) partition="${target}p1" ;;
esac

find_cmd() {
  for cmd in "$@"; do
    [ -x "${cmd}" ] && {
      printf '%s\n' "${cmd}"
      return 0
    }
    command -v "${cmd}" >/dev/null 2>&1 && {
      command -v "${cmd}"
      return 0
    }
  done
  return 1
}

is_mounted() {
  "${BB}" grep -q " $1 " /proc/mounts 2>/dev/null
}

mount_live_media_for_install() {
  [ -d /run/auzix-iso ] || "${BB}" mkdir -p /run/auzix-iso
  if is_mounted /run/auzix-iso; then
    return 0
  fi
  for dev in /dev/sr0 /dev/cdrom /dev/disk/by-label/AUZIXLIVE /dev/disk/by-label/ISOIMAGE; do
    [ -e "${dev}" ] || continue
    "${BB}" mount -t iso9660 -o ro "${dev}" /run/auzix-iso 2>/dev/null && return 0
  done
  return 1
}

copy_boot_payload() {
  "${BB}" mkdir -p /Work/InstallTarget/boot
  if mount_live_media_for_install && [ -d /run/auzix-iso/boot ]; then
    ( cd /run/auzix-iso && "${BB}" tar -cf - boot ) | ( cd /Work/InstallTarget && "${BB}" tar -xf - )
  fi
}

write_installed_fstab() {
  root_fstype="$1"
  cat > /Work/InstallTarget/System/Settings/fstab <<EOF
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
devtmpfs /dev devtmpfs defaults 0 0
devpts /dev/pts devpts gid=5,mode=620,ptmxmode=666 0 0
tmpfs /dev/shm tmpfs mode=1777,nosuid,nodev 0 0
tmpfs /run tmpfs defaults 0 0
LABEL=AUZIXROOT / ${root_fstype} defaults 0 1
EOF
}

write_grub_cfg() {
  kernel=""
  initrd=""
  for candidate in /Work/InstallTarget/boot/vmlinuz /Work/InstallTarget/boot/vmlinuz-* /Work/InstallTarget/boot/linux; do
    [ -f "${candidate}" ] || continue
    kernel="/boot/$("${BB}" basename "${candidate}")"
    break
  done
  for candidate in /Work/InstallTarget/boot/initrd.img /Work/InstallTarget/boot/initrd.img-* /Work/InstallTarget/boot/initramfs.img /Work/InstallTarget/boot/initramfs.cpio.gz /Work/InstallTarget/boot/initramfs-*; do
    [ -f "${candidate}" ] || continue
    initrd="/boot/$("${BB}" basename "${candidate}")"
    break
  done
  [ -n "${kernel}" ] || return 1
  "${BB}" mkdir -p /Work/InstallTarget/boot/grub
  cat > /Work/InstallTarget/boot/grub/grub.cfg <<EOF
set timeout=3
set default=0

menuentry "AuziX installed root" {
    linux ${kernel} root=LABEL=AUZIXROOT auzix.root=LABEL=AUZIXROOT init=/init rw
EOF
  if [ -n "${initrd}" ]; then
    echo "    initrd ${initrd}" >> /Work/InstallTarget/boot/grub/grub.cfg
  fi
  cat >> /Work/InstallTarget/boot/grub/grub.cfg <<'EOF'
}
EOF
}

install_grub_bootloader() {
  grub_install="$(find_cmd \
    /System/Compatibility/usr/sbin/grub-install \
    /System/Compatibility/sbin/grub-install \
    /Programs/GRUB/host/Commands/grub-install \
    grub-install || true)"
  if [ -z "${grub_install}" ]; then
    echo "GRUB requested, but grub-install is not available in this live image." >&2
    echo "Install or package GRUB-host, then rerun with --bootloader grub." >&2
    return 1
  fi
  write_grub_cfg || {
    echo "GRUB requested, but no kernel was found under /boot on the installed root." >&2
    return 1
  }
  "${BB}" mkdir -p /Work/InstallTarget/dev /Work/InstallTarget/proc /Work/InstallTarget/sys
  is_mounted /Work/InstallTarget/dev || "${BB}" mount --bind /dev /Work/InstallTarget/dev 2>/dev/null || true
  is_mounted /Work/InstallTarget/proc || "${BB}" mount -t proc proc /Work/InstallTarget/proc 2>/dev/null || true
  is_mounted /Work/InstallTarget/sys || "${BB}" mount -t sysfs sysfs /Work/InstallTarget/sys 2>/dev/null || true
  "${grub_install}" --boot-directory=/Work/InstallTarget/boot "${target}"
}

echo "Creating Auzix partition on ${target}"
"${BB}" dd if=/dev/zero of="${target}" bs=1M count=8
printf 'o\nn\np\n1\n\n\nw\n' | "${BB}" fdisk "${target}"
"${BB}" partprobe "${target}" 2>/dev/null || true
"${BB}" sleep 2

if [ ! -b "${partition}" ]; then
  echo "Partition was not discovered: ${partition}" >&2
  exit 1
fi

echo "Formatting ${partition}"
root_fstype=ext2
mkfs_ext4="$(find_cmd \
  /System/Compatibility/usr/sbin/mkfs.ext4 \
  /System/Compatibility/sbin/mkfs.ext4 \
  mkfs.ext4 || true)"
mke2fs="$(find_cmd \
  /System/Compatibility/usr/sbin/mke2fs \
  /System/Compatibility/sbin/mke2fs \
  mke2fs || true)"
if [ -n "${mkfs_ext4}" ]; then
  "${mkfs_ext4}" -F -L AUZIXROOT "${partition}"
  root_fstype=ext4
elif [ -n "${mke2fs}" ]; then
  "${mke2fs}" -F -t ext4 -L AUZIXROOT "${partition}"
  root_fstype=ext4
else
  echo "WARNING: ext4 tooling is unavailable; falling back to non-journaled ext2." >&2
  "${BB}" mkfs.ext2 -F -L AUZIXROOT "${partition}"
fi

"${BB}" mkdir -p /Work/InstallTarget
"${BB}" mount "${partition}" /Work/InstallTarget
is_mounted /Work/InstallTarget || {
  echo "Target partition did not mount at /Work/InstallTarget." >&2
  exit 1
}

echo "Copying live Auzix root to ${partition}"
(
  cd /
  tar \
    --exclude='./dev/*' \
    --exclude='./proc/*' \
    --exclude='./sys/*' \
    --exclude='./run/*' \
    --exclude='./System/Settings/display/assets/*' \
    --exclude='./Work/InstallTarget/*' \
    -cf - .
) | (
  cd /Work/InstallTarget
  "${BB}" tar -xf -
)

"${BB}" mkdir -p /Work/InstallTarget/dev /Work/InstallTarget/proc /Work/InstallTarget/sys /Work/InstallTarget/run
"${BB}" rm -rf /Work/InstallTarget/System/Settings/display/assets 2>/dev/null || true
"${BB}" mkdir -p /Work/InstallTarget/System/Settings/display/assets
"${BB}" cp /Work/InstallTarget/System/Boot/InstalledInit /Work/InstallTarget/init
"${BB}" chmod 0755 /Work/InstallTarget/init
"${BB}" mkdir -p /Work/InstallTarget/System/Settings /Work/InstallTarget/System/Settings/install
if [ -x /Work/InstallTarget/System/Tools/finalize-installed-root ]; then
  /Work/InstallTarget/System/Tools/finalize-installed-root /Work/InstallTarget
fi
write_installed_fstab "${root_fstype}"
copy_boot_payload
"${BB}" mkdir -p /Work/InstallTarget/boot/grub
write_grub_cfg 2>/dev/null || true
"${BB}" mkdir -p /Work/InstallTarget/System/State/install
"${BB}" date > /Work/InstallTarget/System/State/install/installed-at.txt 2>/dev/null || true
if [ -s /Work/InstallTarget/System/Settings/packages/installed.json ]; then
  "${BB}" cp /Work/InstallTarget/System/Settings/packages/installed.json \
    /Work/InstallTarget/System/State/install/installed-packages.json 2>/dev/null || true
fi
(
  cd /Work/InstallTarget
  find System/PackageDB -maxdepth 1 -type f -name '*.json' -print 2>/dev/null | sort
) > /Work/InstallTarget/System/State/install/package-receipts.txt 2>/dev/null || true
cat > /Work/InstallTarget/System/Settings/install/boot-note.txt <<NOTE
This root was installed by auzix-install-disk.

Boot it with the Auzix ISO and add this kernel argument:

  auzix.root=${partition}

If --bootloader grub was used successfully, the target disk also has a GRUB
configuration under /boot/grub/grub.cfg.
NOTE

if [ "${bootloader}" = "grub" ]; then
  install_grub_bootloader
elif [ "${bootloader}" != "iso" ] && [ "${bootloader}" != "none" ]; then
  echo "Unsupported bootloader: ${bootloader}" >&2
  exit 2
fi

"${BB}" sync
"${BB}" umount /Work/InstallTarget/proc 2>/dev/null || true
"${BB}" umount /Work/InstallTarget/sys 2>/dev/null || true
"${BB}" umount /Work/InstallTarget/dev 2>/dev/null || true
"${BB}" umount /Work/InstallTarget
echo "Installed Auzix root to ${partition}"
echo "Next boot argument: auzix.root=${partition}"
SCRIPT

chmod 0755 "${AUZIX_ROOT}/System/Tools/auzix-install-disk"

cat > "${AUZIX_ROOT}/System/Settings/install/live-tools.txt" <<'TXT'
auzix-install-disk transposes the live strict root to local storage.
Use --bootloader grub for an experimental BIOS GRUB install when grub-install
is available inside the live image.
TXT

cat > "${AUZIX_ROOT}/System/Settings/display/e27-stage.txt" <<'TXT'
Target graphical stage:
- EFL 1.28.1
- Enlightenment 0.27.1
- Wayland compositor path preferred when seat/input/DRM support exists
- Xorg fallback kept for early VM testing
- DesktopAssets exports themes and backgrounds through E's global data paths
- Theme selection remains per-user because themes are EFL/E-version-bound

Start manually with:
  /System/Tools/start-e

Force a mode with:
  AUZIX_E_MODE=wayland /System/Tools/start-e
  AUZIX_E_MODE=x11 /System/Tools/start-e
TXT

log "Live tools installed into ${AUZIX_ROOT}"
