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
  "${AUZIX_ROOT}/System/Logs/installer" \
  "${AUZIX_ROOT}/System/Logs/packages" \
  "${AUZIX_ROOT}/Services"

if [ -f "${ROOT_DIR}/scripts/auzix-install-root-from-repo-profile.sh" ]; then
  cp "${ROOT_DIR}/scripts/auzix-install-root-from-repo-profile.sh" \
    "${AUZIX_ROOT}/System/Tools/auzix-install-root-from-repo-profile"
  chmod 0755 "${AUZIX_ROOT}/System/Tools/auzix-install-root-from-repo-profile"
fi
if [ -f "${ROOT_DIR}/profiles/packages/auzix-alpha-installer.apk.list" ]; then
  mkdir -p "${AUZIX_ROOT}/System/Settings/install/apk-installer"
  cp "${ROOT_DIR}/profiles/packages/auzix-alpha-installer.apk.list" \
    "${AUZIX_ROOT}/System/Settings/install/apk-installer/10-alpha-minimal.list"
fi

chown -R 0:1000 \
  "${AUZIX_ROOT}/System/Logs/installer" \
  "${AUZIX_ROOT}/System/Logs/packages" 2>/dev/null || true
chmod 0775 \
  "${AUZIX_ROOT}/System/Logs/installer" \
  "${AUZIX_ROOT}/System/Logs/packages" 2>/dev/null || true

# STRICT BOOT USER HANDOFF CONTRACT:
# r4 proved PID1/StartSequence reaches the display stage, but the final
# openvt->E handoff failed because BusyBox `su auzix` consults libc account
# lookup state that is not guaranteed to exist in strict root.  This tiny helper
# is the r5 additive fix: drop to numeric uid/gid/groups without needing
# /etc/passwd or NSS.  Do not replace it with `su auzix` unless strict-root user
# lookup has first been proven in the init path.
cat > "${AUZIX_ROOT}/System/Tools/auzix-run-as-uid.c" <<'EOF'
#define _GNU_SOURCE
#include <errno.h>
#include <grp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

static void die(const char *msg) {
  perror(msg);
  exit(111);
}

static unsigned long parse_ulong(const char *s, const char *what) {
  char *end = NULL;
  errno = 0;
  unsigned long value = strtoul(s, &end, 10);
  if (errno || end == s || *end != '\0') {
    fprintf(stderr, "auzix-run-as-uid: invalid %s: %s\n", what, s);
    exit(64);
  }
  return value;
}

int main(int argc, char **argv) {
  if (argc < 5) {
    fprintf(stderr, "usage: %s UID GID GROUPS COMMAND [ARGS...]\n", argv[0]);
    return 64;
  }

  uid_t uid = (uid_t)parse_ulong(argv[1], "uid");
  gid_t gid = (gid_t)parse_ulong(argv[2], "gid");

  gid_t groups[64];
  int group_count = 0;
  char *group_spec = strdup(argv[3]);
  if (!group_spec) die("strdup");
  char *save = NULL;
  for (char *tok = strtok_r(group_spec, ",", &save);
       tok && group_count < (int)(sizeof(groups) / sizeof(groups[0]));
       tok = strtok_r(NULL, ",", &save)) {
    if (*tok == '\0') continue;
    groups[group_count++] = (gid_t)parse_ulong(tok, "group");
  }

  if (setgroups((size_t)group_count, groups) != 0) die("setgroups");
  if (setgid(gid) != 0) die("setgid");
  if (setuid(uid) != 0) die("setuid");

  execv(argv[4], &argv[4]);
  die("execv");
}
EOF
if command -v gcc >/dev/null 2>&1; then
  # Strict-root means this helper must not depend on /lib64 or a dynamic loader.
  # If static linking is unavailable, stop here and fix the builder/toolchain
  # instead of baking a dynamically linked handoff that fails at boot.
  gcc -static -Os -s -o "${AUZIX_ROOT}/System/Tools/auzix-run-as-uid" \
    "${AUZIX_ROOT}/System/Tools/auzix-run-as-uid.c"
  rm -f "${AUZIX_ROOT}/System/Tools/auzix-run-as-uid.c"
  chmod 0755 "${AUZIX_ROOT}/System/Tools/auzix-run-as-uid"
else
  printf 'add-auzix-live-tools: gcc is required to build static auzix-run-as-uid\n' >&2
  exit 1
fi

if [ -x "${ROOT_DIR}/scripts/probe-auzix-desktop-launchers.sh" ]; then
  install -D -m 0755 \
    "${ROOT_DIR}/scripts/probe-auzix-desktop-launchers.sh" \
    "${AUZIX_ROOT}/System/Tools/probe-auzix-desktop-launchers"
fi

cat > "${AUZIX_ROOT}/System/Settings/mdev.conf" <<'EOF'
null 0:0 0666
random 0:0 0666
urandom 0:0 0666
EOF

cat > "${AUZIX_ROOT}/System/Boot/StartSequence" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -u

[ -r /System/Settings/auzix-paths.sh ] && . /System/Settings/auzix-paths.sh
PATH=/Programs/BusyBox/1.36.1/Commands:${PATH:-}
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox

# PROVEN BOOT CONTRACT:
# Keep StartSequence self-hosted on static BusyBox primitives.  r4 reached this
# script, mounted runtime filesystems, DHCP'd, started services, and reached the
# display stage.  Changes here must be additive and evidence-driven; do not
# rewrite the init/runtime path while debugging desktop/package issues.
LINK_MODE="${AUZIX_LINK_MODE:-}"
if [ -z "${LINK_MODE}" ] && [ -r /proc/cmdline ]; then
  for arg in $(${BB} cat /proc/cmdline 2>/dev/null || true); do
    case "${arg}" in
      auzix.links=*) LINK_MODE="${arg#auzix.links=}" ;;
      auzix.strict-links|auzix.links=off|auzix.links=none) LINK_MODE=strict ;;
    esac
  done
fi
LINK_MODE="${LINK_MODE:-strict}"

compat_links_enabled() {
  case "${LINK_MODE}" in
    full|compat|legacy|on|yes) return 0 ;;
    *) return 1 ;;
  esac
}

log() {
  echo "[StartSequence] $*"
}

console_note() {
  msg="[StartSequence] $*"
  # PID 1 already inherits the selected kernel console.  Writing the same
  # message to tty1 and an unattended ttyS0 can block startup when QEMU has no
  # serial client, as well as duplicating every line on the framebuffer.
  echo "${msg}"
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

  "${BB}" mkdir -p /System/State/ssh /System/State/dbus /System/State/display /System/State/desktop /System/State/packages /System/Logs/display /System/Logs/installer /System/Logs/packages 2>/dev/null || true
  if [ -d /run/auzix-state-seed/ssh ]; then
    "${BB}" cp -a /run/auzix-state-seed/ssh/. /System/State/ssh/ 2>/dev/null || true
  fi
  "${BB}" chown -R 0:0 /System/State/ssh 2>/dev/null || true
  "${BB}" chown -R 0:1000 /System/State/packages /System/Logs/installer /System/Logs/packages 2>/dev/null || true
  "${BB}" chown -R 1000:1000 /System/State/display /System/State/desktop /System/Logs/display 2>/dev/null || true
  "${BB}" chmod 0755 /System/State /System/State/dbus /System/Logs 2>/dev/null || true
  "${BB}" chmod 0775 /System/State/display /System/State/desktop /System/Logs/display 2>/dev/null || true
  "${BB}" chmod 0775 /System/State/packages /System/Logs/installer /System/Logs/packages 2>/dev/null || true
  "${BB}" chmod 0700 /System/State/ssh 2>/dev/null || true
  "${BB}" chmod 0600 /System/State/ssh/ssh_host_*_key 2>/dev/null || true
  "${BB}" chmod 0644 /System/State/ssh/ssh_host_*_key.pub 2>/dev/null || true
}

mount_runtime() {
  is_mounted /proc || "${BB}" mount -t proc proc /proc 2>/dev/null || true
  is_mounted /sys || "${BB}" mount -t sysfs sysfs /sys 2>/dev/null || true
  "${BB}" mkdir -p /sys/fs/cgroup
  is_mounted /sys/fs/cgroup || "${BB}" mount -t cgroup2 cgroup2 /sys/fs/cgroup 2>/dev/null || true
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
  "${BB}" mkdir -p /run /run/lock /run/user /run/sshd /tmp /tmp/.X11-unix /dev/shm /Work/Temp /System/State /System/State/log /System/Cache /System/Logs /Network/DNS
  "${BB}" chmod 0755 /run/sshd 2>/dev/null || true
  "${BB}" touch /System/Logs/lastlog 2>/dev/null || true
  "${BB}" ln -sfn /run/resolv.conf /System/Settings/resolv.conf 2>/dev/null || true
  # POSIX/libc contract: user/group/name-service lookups are conventionally
  # rooted in /etc.  The working moon ISO kept /etc as a symlink to
  # /System/Settings, so getpwnam/getgrnam, chgrp, Xorg, and desktop helpers
  # all saw the AUZiX account database without duplicating state.
  if [ -d /etc ] && [ ! -L /etc ]; then
    "${BB}" rmdir /etc 2>/dev/null || true
  fi
  [ -e /etc ] || "${BB}" ln -s /System/Settings /etc 2>/dev/null || true
  # APK/container roots legitimately carry a populated /etc, so the directory
  # cannot always be replaced by the historical /System/Settings link.  In
  # that layout publish DHCP's live resolver file at the libc-standard path.
  if [ -d /etc ] && [ ! -L /etc ]; then
    "${BB}" ln -sfn /run/resolv.conf /etc/resolv.conf 2>/dev/null || true
  fi
  "${BB}" mkdir -p /System/Compatibility/etc 2>/dev/null || true
  for settings_file in passwd group shadow shells nsswitch.conf hosts; do
    if [ -e "/System/Settings/${settings_file}" ]; then
      "${BB}" ln -sfn "/System/Settings/${settings_file}" "/System/Compatibility/etc/${settings_file}" 2>/dev/null || true
    fi
  done
  "${BB}" ln -sfn /run/resolv.conf /System/Compatibility/etc/resolv.conf 2>/dev/null || true
  if [ -d /System/Compatibility/etc/ssl ]; then
    "${BB}" ln -sfn /System/Compatibility/etc/ssl /System/Settings/ssl 2>/dev/null || true
    "${BB}" mkdir -p /System/Compatibility/usr/lib 2>/dev/null || true
    "${BB}" ln -sfn /System/Compatibility/etc/ssl /System/Compatibility/usr/lib/ssl 2>/dev/null || true
    if [ -s /System/Compatibility/etc/ssl/certs/ca-certificates.crt ]; then
      "${BB}" ln -sfn /System/Compatibility/etc/ssl/certs/ca-certificates.crt /System/Compatibility/etc/ssl/cert.pem 2>/dev/null || true
      "${BB}" ln -sfn /System/Compatibility/etc/ssl/certs/ca-certificates.crt /System/Compatibility/usr/lib/ssl/cert.pem 2>/dev/null || true
      # The packaged Flatpak runtime carries an OpenSSL build whose upstream
      # OPENSSLDIR is /etc/pki/tls. Publish the same trusted bundle there; this
      # is a compatibility view, not a second certificate authority store.
      "${BB}" mkdir -p /System/Compatibility/etc/pki/tls/certs 2>/dev/null || true
      "${BB}" ln -sfn /System/Compatibility/etc/ssl/certs/ca-certificates.crt \
        /System/Compatibility/etc/pki/tls/certs/ca-bundle.crt 2>/dev/null || true
      if [ -e /System/Compatibility/etc/ssl/openssl.cnf ]; then
        "${BB}" ln -sfn /System/Compatibility/etc/ssl/openssl.cnf \
          /System/Compatibility/etc/pki/tls/openssl.cnf 2>/dev/null || true
      fi
      [ -e /System/Settings/pki ] || "${BB}" ln -s /System/Compatibility/etc/pki /System/Settings/pki 2>/dev/null || true
      if [ -d /etc ] && [ ! -L /etc ]; then
        [ -e /etc/pki ] || "${BB}" ln -s /System/Compatibility/etc/pki /etc/pki 2>/dev/null || true
      fi
    fi
  fi
  if [ "$("${BB}" hostname 2>/dev/null || echo "(none)")" = "(none)" ]; then
    "${BB}" hostname auzix-live 2>/dev/null || true
  fi
  current_hostname="$("${BB}" hostname 2>/dev/null || echo auzix-live)"
  if [ -n "${current_hostname}" ] &&
     ! "${BB}" grep -Eq "^[^#]*[[:space:]]${current_hostname}([[:space:]]|$)" /System/Settings/hosts 2>/dev/null; then
    printf '127.0.1.1\t%s\n' "${current_hostname}" >>/System/Settings/hosts
  fi
  if [ -n "${current_hostname}" ] && [ -f /etc/hosts ] &&
     ! "${BB}" grep -Eq "^[^#]*[[:space:]]${current_hostname}([[:space:]]|$)" /etc/hosts 2>/dev/null; then
    printf '127.0.1.1\t%s\n' "${current_hostname}" >>/etc/hosts
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
  [ -e /System/State/tmp ] || "${BB}" ln -s /Work/Temp /System/State/tmp 2>/dev/null || true
  # Strict mode means no legacy top-level AUZiX root aliases at runtime either.
  # These links are allowed only when booted with auzix.links=compat/full for
  # break-glass package triage.
  if compat_links_enabled; then
    [ -e /opt ] || "${BB}" ln -s /Programs /opt 2>/dev/null || true
    if [ -d /root ] && [ ! -L /root ]; then
      "${BB}" rmdir /root 2>/dev/null || true
    fi
    [ -e /root ] || "${BB}" ln -s /Users/root /root 2>/dev/null || true
  fi
  # Xorg/xkbcomp still contain an upstream default XKB lookup rooted at
  # /usr/share/X11/xkb.  Keep this as a narrow display compatibility alias; do
  # not restore broad top-level /usr payloads from here.
  if [ -d /System/Settings/X11/xkb ]; then
    "${BB}" mkdir -p /usr/share/X11 2>/dev/null || true
    if [ ! -e /usr/share/X11/xkb ]; then
      "${BB}" ln -s /System/Settings/X11/xkb /usr/share/X11/xkb 2>/dev/null || true
    fi
  fi
  [ -d /usr/local ] && "${BB}" chown 0:0 /usr/local 2>/dev/null || true
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
  # devtmpfs/mdev may publish a separate 0660 /dev/ptmx node after devpts is
  # mounted.  POSIX PTY allocation must enter the mounted devpts instance.
  "${BB}" rm -f /dev/ptmx 2>/dev/null || true
  "${BB}" ln -s pts/ptmx /dev/ptmx 2>/dev/null || true
  "${BB}" chmod 0666 /dev/pts/ptmx 2>/dev/null || true
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
tty:x:5:root,auzix,lightdm
auzix:x:1000:
sshd:x:74:
messagebus:x:101:
lightdm:x:102:
sudo:x:27:auzix
wheel:x:10:root,auzix
input:x:104:root,auzix,lightdm
video:x:39:root,auzix,lightdm
render:x:105:root,auzix,lightdm
audio:x:63:root,auzix
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
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
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

start_rescue_consoles() {
  "${BB}" mkdir -p /System/Logs 2>/dev/null || true
  if [ -c /dev/tty2 ] && [ ! -e /run/auzix-rescue-tty2 ]; then
    "${BB}" touch /run/auzix-rescue-tty2 2>/dev/null || true
    "${BB}" setsid "${BB}" sh -c 'echo "Auzix rescue shell on tty2. GUI continues on tty7." >/dev/tty2; exec /Programs/BusyBox/1.36.1/Commands/busybox cttyhack /Programs/BusyBox/1.36.1/Commands/busybox sh </dev/tty2 >/dev/tty2 2>&1' &
  fi
  if [ -c /dev/ttyS0 ] && [ ! -e /run/auzix-rescue-ttyS0 ]; then
    "${BB}" touch /run/auzix-rescue-ttyS0 2>/dev/null || true
    "${BB}" setsid "${BB}" sh -c 'echo "Auzix rescue shell on ttyS0. GUI continues on tty7." >/dev/ttyS0; exec /Programs/BusyBox/1.36.1/Commands/busybox cttyhack /Programs/BusyBox/1.36.1/Commands/busybox sh </dev/ttyS0 >/dev/ttyS0 2>&1' &
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

live_media_candidates() {
  # Moon reference behavior: only probe actual live-media style devices.  Do
  # not scan HDD/root block devices here.  The HDD image regressed when this
  # grew to include /dev/vda,/dev/sda and partitions, causing installed/root
  # boots to repeatedly try to mount their own disk as live media before X/E.
  for dev in \
    /dev/disk/by-label/AUZIXLIVE \
    /dev/disk/by-label/ISOIMAGE \
    /dev/sr0 /dev/cdrom /dev/hdc
  do
    [ -e "${dev}" ] || continue
    printf '%s\n' "${dev}"
  done
}

try_mount_live_media_dev() {
  dev="$1"
  for fstype in iso9660 ext4 vfat; do
    "${BB}" mount -t "${fstype}" -o ro "${dev}" /run/auzix-iso 2>/dev/null || continue
    if live_media_ready; then
      return 0
    fi
    unmount_live_media
  done
  return 1
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
    for dev in $(live_media_candidates); do
      if try_mount_live_media_dev "${dev}"; then
        log "live media mounted from ${dev}"
        return 0
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
  [ "${AUZIX_STAGE_LIVE_ASSETS:-1}" = "1" ] || {
    log "live display assets skipped"
    return 0
  }
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

  if [ "${AUZIX_STAGE_E_CONFIG:-1}" = "1" ] && [ -f "${asset_dir}/config/profile.cfg" ]; then
    "${BB}" cp -f "${asset_dir}/config/profile.cfg" /Users/auzix/.e/e/config/profile.cfg 2>/dev/null || true
  fi
  if [ "${AUZIX_STAGE_E_CONFIG:-1}" = "1" ]; then
  for profile in standard default; do
    [ -d "${asset_dir}/config/${profile}" ] || continue
    "${BB}" mkdir -p "/Users/auzix/.e/e/config/${profile}" 2>/dev/null || true
    "${BB}" cp -a "${asset_dir}/config/${profile}/." "/Users/auzix/.e/e/config/${profile}/" 2>/dev/null || true
  done
  if [ -d "${asset_dir}/config/elementary" ]; then
    "${BB}" mkdir -p /Users/auzix/.elementary/config 2>/dev/null || true
    "${BB}" cp -a "${asset_dir}/config/elementary/." /Users/auzix/.elementary/config/ 2>/dev/null || true
  fi
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
     [ -d /System/Compatibility/usr/share/enlightenment/data/config/standard ]; then
    "${BB}" mkdir -p /Users/auzix/.e/e/config
    "${BB}" cp -a /System/Compatibility/usr/share/enlightenment/data/config/standard /Users/auzix/.e/e/config/ 2>/dev/null || true
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
    /System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_system \
    /System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_sys \
    /System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_ckpasswd; do
    [ -e "${helper}" ] || continue
    "${BB}" chown root:root "${helper}" 2>/dev/null || true
    "${BB}" chmod 4755 "${helper}" 2>/dev/null || true
  done
  if [ -d /System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment ] && [ ! -e /System/Compatibility/usr/lib/enlightenment ]; then
    "${BB}" mkdir -p /System/Compatibility/usr/lib
    "${BB}" ln -s /System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment /System/Compatibility/usr/lib/enlightenment 2>/dev/null || true
  fi
  "${BB}" mkdir -p /run/user/1000 /System/State/display /System/State/desktop
  "${BB}" chown 1000:1000 /run/user/1000 2>/dev/null || true
  "${BB}" chmod 0700 /run/user/1000 2>/dev/null || true
  "${BB}" mkdir -p /System/Logs/display /System/State/display /System/State/desktop
  "${BB}" touch \
    /System/Logs/display/start-e.log \
    /System/Logs/display/openvt.log \
    /System/Logs/display/hardware-display.log \
    /System/Logs/display/e-module-tuning.log 2>/dev/null || true
  "${BB}" chown -R 1000:1000 /System/Logs/display /System/State/display /System/State/desktop 2>/dev/null || true
  "${BB}" chmod 0775 /System/Logs/display /System/State/display /System/State/desktop 2>/dev/null || true
  "${BB}" chown 1000:1000 \
    /System/Logs/display/start-e.log \
    /System/Logs/display/openvt.log \
    /System/Logs/display/hardware-display.log \
    /System/Logs/display/e-module-tuning.log 2>/dev/null || true
}

ensure_dbus_machine_id() {
  # Machine-id/system DBus state is root-owned runtime state.  User sessions may
  # read it, but must not create/chown/overwrite it after we drop to uid 1000.
  [ "$("${BB}" id -u 2>/dev/null || echo 0)" = "0" ] || return 0
  "${BB}" mkdir -p /System/State/dbus /run/dbus-state 2>/dev/null || true
  # /run/dbus-state is live runtime state, not packaged truth.  In strict live
  # mode /System/State may be read-only from squashfs, so DBus must always have
  # a writable, root-readable fallback before system/session bus startup.
  "${BB}" chown root:root /run/dbus-state /System/State/dbus 2>/dev/null || true
  "${BB}" chmod 0755 /run/dbus-state /System/State/dbus 2>/dev/null || true
  if [ ! -d /System/State/dbus ]; then
    "${BB}" mkdir -p /run/dbus-state 2>/dev/null || true
    [ -e /System/State/dbus ] || "${BB}" ln -s /run/dbus-state /System/State/dbus 2>/dev/null || true
  fi

  machine_id=""
  if [ -s /System/State/dbus/machine-id ]; then
    machine_id="$("${BB}" head -n 1 /System/State/dbus/machine-id 2>/dev/null || true)"
  elif [ -s /run/dbus-state/machine-id ]; then
    machine_id="$("${BB}" head -n 1 /run/dbus-state/machine-id 2>/dev/null || true)"
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
    "${BB}" chown root:root "${dbus_state_dir}" 2>/dev/null || true
    "${BB}" chmod 0755 "${dbus_state_dir}" 2>/dev/null || true
  else
    "${BB}" rm -f "${dbus_state_dir}/.write-test" 2>/dev/null || true
  fi

  "${BB}" mkdir -p /run/dbus-state "${dbus_state_dir}" 2>/dev/null || true
  "${BB}" chown root:root /run/dbus-state "${dbus_state_dir}" 2>/dev/null || true
  "${BB}" chmod 0755 /run/dbus-state "${dbus_state_dir}" 2>/dev/null || true
  if ! printf '%s\n' "${machine_id}" >"${dbus_state_dir}/machine-id" 2>/dev/null; then
    dbus_state_dir=/run/dbus-state
    printf '%s\n' "${machine_id}" >"${dbus_state_dir}/machine-id" 2>/dev/null || true
  fi
  "${BB}" cp -f "${dbus_state_dir}/machine-id" /run/dbus-state/machine-id 2>/dev/null || true
  "${BB}" chmod 0644 /run/dbus-state/machine-id "${dbus_state_dir}/machine-id" 2>/dev/null || true
}

start_system_bus() {
  [ "$("${BB}" id -u 2>/dev/null || echo 0)" = "0" ] || return 0
  command -v dbus-daemon >/dev/null 2>&1 || return 0
  ensure_dbus_machine_id
  "${BB}" mkdir -p /run/dbus
  if [ -S /run/dbus/system_bus_socket ] &&
     "${BB}" ps | "${BB}" grep "dbus-daemon --system" | "${BB}" grep -v grep >/dev/null 2>&1; then
    return 0
  fi
  "${BB}" rm -f /run/dbus/system_bus_socket 2>/dev/null || true
  "${BB}" timeout 5 dbus-daemon --system --fork --nopidfile >/System/Logs/dbus-system.log 2>&1 || true
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

first_absolute_pointer_event() {
  preferred_pattern="${1:-}"
  "${BB}" awk -v pat="${preferred_pattern}" '
    /^N: Name=/ { name=$0; event=""; has_abs=0; has_keys=0 }
    /^H: Handlers=/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^event[0-9]+$/) event="/dev/input/" $i
      }
    }
    /^B: KEY=/ && $3 != "0" { has_keys=1 }
    /^B: ABS=/ && $3 != "0" { has_abs=1 }
    /^$/ {
      if (event != "" && has_abs && has_keys && (pat == "" || name ~ pat)) {
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

audit_runtime_devices() {
  log_file=/System/Logs/dev-audit.log
  {
    echo "== mounts =="
    "${BB}" mount | "${BB}" grep -E ' on /(dev|dev/pts|dev/shm|proc|sys|run)( |$)' || true
    echo "== core nodes =="
    "${BB}" ls -l \
      /dev/console \
      /dev/null \
      /dev/tty \
      /dev/tty0 \
      /dev/tty1 \
      /dev/tty2 \
      /dev/tty7 \
      /dev/ttyS0 \
      /dev/ptmx \
      /dev/pts/ptmx 2>&1 || true
    echo "== input =="
    "${BB}" ls -l /dev/input 2>&1 || true
    "${BB}" ls -l /dev/input/* 2>&1 || true
    echo "== dri =="
    "${BB}" ls -l /dev/dri 2>&1 || true
    "${BB}" ls -l /dev/dri/* 2>&1 || true
    echo "== xorg config =="
    [ -s /System/Settings/X11/xorg.conf ] && "${BB}" sed -n '1,120p' /System/Settings/X11/xorg.conf || true
  } >"${log_file}" 2>&1 || true
}

write_xorg_config() {
  input_mode="${AUZIX_XORG_INPUT_MODE:-auto}"
  keyboard_event="$(first_event_for_name "AT Translated Set 2 keyboard")"
  tablet_event="$(first_absolute_pointer_event "QEMU QEMU USB Tablet")"
  [ -n "${tablet_event}" ] || tablet_event="$(first_absolute_pointer_event "VirtualPS/2 VMware VMMouse")"
  [ -n "${tablet_event}" ] || tablet_event="$(first_absolute_pointer_event)"
  mouse_event="$(first_relative_pointer_event)"
  [ -n "${tablet_event}" ] || tablet_event="${mouse_event}"
  [ -n "${mouse_event}" ] || mouse_event="$(first_event_for_name "VirtualPS/2 VMware VMMouse")"
  [ -n "${keyboard_event}" ] || keyboard_event=/dev/input/event0
  [ -n "${tablet_event}" ] || tablet_event=/dev/input/event2
  [ -n "${mouse_event}" ] || mouse_event="${tablet_event}"

  "${BB}" mkdir -p /System/Settings/X11
  if [ "${input_mode}" != "evdev-explicit" ]; then
    cat > /System/Settings/X11/xorg.conf <<EOF
Section "Files"
    ModulePath "/System/Drivers/Xorg/modules"
    ModulePath "/System/Compatibility/usr/lib/xorg/modules"
    FontPath "/System/Fonts/truetype/dejavu"
    FontPath "/System/Compatibility/usr/share/fonts/truetype/dejavu"
    FontPath "/System/Compatibility/usr/share/fonts/X11/misc"
    FontPath "/System/Compatibility/usr/share/fonts/X11/Type1"
    FontPath "/System/Compatibility/usr/share/fonts/X11/75dpi"
    FontPath "/System/Compatibility/usr/share/fonts/X11/100dpi"
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
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1920x1080" "1280x800" "1024x768"
    EndSubSection
EndSection

Section "ServerLayout"
    Identifier "AuzixLayout"
    Screen "AuzixScreen"
EndSection
EOF
    if [ -e /System/Compatibility/usr/lib/xorg/modules/input/libinput_drv.so ]; then
      log "xorg input=auto libinput=present keyboard=${keyboard_event} tablet=${tablet_event} pointer=${mouse_event}"
    else
      log "xorg input=auto libinput=missing udev-or-server-probe-required keyboard=${keyboard_event} tablet=${tablet_event} pointer=${mouse_event}"
    fi
    return 0
  fi

  cat > /System/Settings/X11/xorg.conf <<EOF
Section "Files"
    ModulePath "/System/Drivers/Xorg/modules"
    ModulePath "/System/Compatibility/usr/lib/xorg/modules"
    FontPath "/System/Fonts/truetype/dejavu"
    FontPath "/System/Compatibility/usr/share/fonts/truetype/dejavu"
    FontPath "/System/Compatibility/usr/share/fonts/X11/misc"
    FontPath "/System/Compatibility/usr/share/fonts/X11/Type1"
    FontPath "/System/Compatibility/usr/share/fonts/X11/75dpi"
    FontPath "/System/Compatibility/usr/share/fonts/X11/100dpi"
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
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1920x1080" "1280x800" "1024x768"
    EndSubSection
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
  # Diagnostics must never become a boot gate.  On minimal PID 1 systems a
  # pipeline-backed `while read` can retain the pipe through a daemon child and
  # block StartSequence forever.  Snapshot to a file, then read it normally.
  process_snapshot=/run/auzix-service-processes.txt
  "${BB}" ps >"${process_snapshot}" 2>/dev/null || true
  "${BB}" grep -E "sshd|dbus-daemon|acpid|udevd|Xorg|enlightenment|start-e" "${process_snapshot}" 2>/dev/null |
    "${BB}" grep -v grep >"${process_snapshot}.filtered" 2>/dev/null || true
  while IFS= read -r line; do
    console_note "services: ${line}"
  done <"${process_snapshot}.filtered"
  if command -v nc >/dev/null 2>&1; then
    for _probe in 1 2 3 4 5; do
      nc -z 127.0.0.1 22 >/dev/null 2>&1 && break
      "${BB}" sleep 1
    done
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
  [ -x /System/Tools/start-gui-stage ] || return 0
  display_mode="$("${BB}" head -n 1 /System/Settings/display/autostart 2>/dev/null || echo manual)"
  [ "${display_mode}" = "manual" ] && return 0
  if "${BB}" ps | "${BB}" grep -E "enlightenment|start-e|Xorg|xinit" | "${BB}" grep -v grep >/dev/null 2>&1; then
    return 0
  fi

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

  # Keep exactly one graphical boot contract.  Earlier HDD experiments drifted
  # because StartSequence carried a copied mini-launcher while start-gui-stage
  # received the real DBus/state/E ownership fixes.  Boot must delegate to the
  # stage wrapper so manual and autostart paths exercise the same code.
  log "starting display via start-gui-stage mode=${display_mode}"
  AUZIX_E_MODE="${display_mode}" /System/Tools/start-gui-stage
}

report_display_status() {
  delay="${AUZIX_DISPLAY_VERIFY_DELAY:-8}"
  if [ "${delay}" -gt 0 ] 2>/dev/null; then
    console_note "display: waiting ${delay}s for X/E process evidence"
    "${BB}" sleep "${delay}"
  fi

  observed=0
  console_note "display: process summary follows"
  "${BB}" ps | "${BB}" grep -E "Xorg|enlightenment|start-e|xinit|efreetd" | "${BB}" grep -v grep | while IFS= read -r line; do
    console_note "display: ${line}"
  done
  if "${BB}" ps | "${BB}" grep -E "Xorg|enlightenment|start-e|xinit" | "${BB}" grep -v grep >/dev/null 2>&1; then
    observed=1
  fi

  if [ "${observed}" = "1" ]; then
    console_note "display: X/E process observed"
  else
    console_note "display: no X/E process observed"
  fi

  smoke_midori=0
  if [ -r /proc/cmdline ]; then
    for arg in $(${BB} cat /proc/cmdline 2>/dev/null || true); do
      case "${arg}" in
        auzix.smoke.midori=1|auzix.smoke.midori|auzix.midori.smoke=1) smoke_midori=1 ;;
      esac
    done
  fi
  if [ "${smoke_midori}" = "1" ] && [ "${observed}" = "1" ] && [ -x /System/Tools/launch-auzix-browser ]; then
    console_note "display: launching Midori smoke URL"
    /System/Tools/auzix-run-as-uid 1000 1000 "${desktop_groups}" \
      "${BB}" env \
      HOME=/Users/auzix \
      XDG_RUNTIME_DIR=/run/user/1000 \
      DISPLAY=:0 \
      DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
      /System/Tools/launch-auzix-browser https://auzietek.com \
      >/System/Logs/display/midori-smoke.log 2>&1 &
    "${BB}" sleep 8
    if "${BB}" ps | "${BB}" grep -E "midori|midori-bin" | "${BB}" grep -v grep >/dev/null 2>&1; then
      console_note "display: Midori process observed"
    else
      console_note "display: no Midori process observed"
    fi
  fi

  if [ -x /System/Tools/auzix-live-agent ]; then
    console_note "display: midori-check follows"
    /System/Tools/auzix-live-agent midori-check 2>&1 | while IFS= read -r line; do
      console_note "midori-check: ${line}"
    done
  fi

  for log_file in \
    /System/Logs/display/openvt.log \
    /System/Logs/display/start-e.log \
    /Users/auzix/.local/share/xorg/Xorg.0.log \
    /System/Logs/display/midori-smoke.log \
    /Users/auzix/.e-log.log \
    /Users/auzix/.xsession-errors; do
    [ -s "${log_file}" ] || continue
    console_note "display: tail ${log_file}"
    "${BB}" tail -12 "${log_file}" 2>/dev/null | while IFS= read -r line; do
      console_note "display-log: ${line}"
    done
  done
}

console_note "stage: mounting runtime filesystems"
mount_runtime
console_note "stage: starting rescue consoles"
start_rescue_consoles
console_note "stage: repairing live user home"
repair_live_user_home
console_note "stage: starting udev"
start_device_manager
console_note "stage: staging live assets"
stage_live_assets
console_note "stage: detecting hardware"
start_hardware
write_xorg_config
audit_runtime_devices
console_note "stage: fixing session permissions"
fix_session_permissions
if [ -x /System/Tools/repair-auzix-desktop-session ]; then
  console_note "stage: repairing desktop session contract"
  if [ -x /Programs/BusyBox/current/Commands/busybox ]; then
    /Programs/BusyBox/current/Commands/busybox timeout 25 \
      /System/Tools/repair-auzix-desktop-session --boot-fast \
      >/System/Logs/display/desktop-session-boot-repair.log 2>&1 || \
      console_note "desktop: session repair timed out or failed; inspect /System/Logs/display/desktop-session-boot-repair.log"
  else
    /System/Tools/repair-auzix-desktop-session --boot-fast >/System/Logs/display/desktop-session-boot-repair.log 2>&1 || \
      console_note "desktop: session repair failed; inspect /System/Logs/display/desktop-session-boot-repair.log"
  fi
fi
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
  report_display_status
else
  console_note "gui: autostart disabled; run /System/Tools/start-gui-stage or AUZIX_GUI_AUTOSTART=1 /System/Boot/StartSequence"
fi
console_note "stage: complete"
SCRIPT

chmod 0755 "${AUZIX_ROOT}/System/Boot/StartSequence"

cat > "${AUZIX_ROOT}/System/Tools/auzix-live-agent" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
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
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
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

mask_evas_gl_engines_root() {
  [ "${AUZIX_MASK_GL_EVAS:-1}" = "1" ] || return 0
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

mask_unstable_enlightenment_modules_root() {
  [ "${AUZIX_MASK_UNSTABLE_E_MODULES:-1}" = "1" ] || return 0
  disabled_dir=/System/State/desktop/enlightenment/disabled-modules
  module_root=/System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/modules
  "${BB}" mkdir -p "${disabled_dir}" /Users/auzix/.e/e/config/standard /Users/auzix/.e/e/config/default 2>/dev/null || true
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
    emix \
    wl_buffer \
    wl_desktop_shell \
    wl_drm \
    wl_text_input \
    wl_weekeyboard \
    wl_wl \
    wl_x11 \
    xwayland; do
    if [ -d "${module_root}/${module}" ]; then
      "${BB}" touch "${disabled_dir}/${module}.live-profile-disabled" 2>/dev/null || true
    fi
    "${BB}" rm -f \
      "/Users/auzix/.e/e/config/standard/module.${module}.cfg" \
      "/Users/auzix/.e/e/config/default/module.${module}.cfg" \
      "/Users/auzix/.e/e/config/module.${module}.cfg" 2>/dev/null || true
  done
  "${BB}" touch \
    /System/State/desktop/enlightenment/vm-safe-modules-applied \
    /System/State/desktop/enlightenment/wizard-disabled \
    /Users/auzix/.e/e/config/standard/.auzix-wizard-disabled 2>/dev/null || true
}

prune_enlightenment_masked_modules_root() {
  command -v eet >/dev/null 2>&1 || return 0
  drop_modules=" battery cpufreq temperature backlight connman bluez5 packagekit geolocation wizard emix everything-apps everything-files wl_buffer wl_desktop_shell wl_drm wl_text_input wl_weekeyboard wl_wl wl_x11 xwayland "
  "${BB}" mkdir -p /Work/Temp /System/State/desktop/enlightenment 2>/dev/null || true

  for cfg in \
    /Users/auzix/.e/e/config/standard/e.cfg \
    /Users/auzix/.e/e/config/default/e.cfg \
    /System/Compatibility/usr/share/enlightenment/data/config/standard/e.cfg \
    /System/Compatibility/usr/share/enlightenment/data/config/default/e.cfg \
    /usr/share/enlightenment/data/config/standard/e.cfg \
    /usr/share/enlightenment/data/config/default/e.cfg
  do
    [ -s "${cfg}" ] || continue
    stem="$("${BB}" basename "${cfg}")"
    txt="/Work/Temp/${stem}.$$.$("${BB}" basename "$("${BB}" dirname "${cfg}")").txt"
    safe="${txt}.safe"
    new="${txt}.eet"
    if eet -d "${cfg}" config "${txt}" 2>/dev/null; then
      "${BB}" awk -v drop="${drop_modules}" '
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
      ' "${txt}" > "${safe}" 2>/dev/null || true
      if [ -s "${safe}" ] &&
         ! "${BB}" cmp -s "${txt}" "${safe}" 2>/dev/null &&
         eet -e "${new}" config "${safe}" 0 2>/dev/null; then
        "${BB}" cp -f "${cfg}" "${cfg}.pre-auzix-module-prune" 2>/dev/null || true
        "${BB}" cp -f "${new}" "${cfg}" 2>/dev/null || true
        echo "${cfg}" >> /System/State/desktop/enlightenment/pruned-module-configs 2>/dev/null || true
      fi
    fi
    "${BB}" rm -f "${txt}" "${safe}" "${new}" 2>/dev/null || true
  done
}

blast_stale_enlightenment_configs_root() {
  [ "${AUZIX_BLAST_STALE_E_CONFIG:-1}" = "1" ] || return 0
  stamp="$(date +%Y%m%dT%H%M%SZ 2>/dev/null || echo now)"
  backup="/Users/auzix/.e/backup/stale-config-blast-${stamp}"
  "${BB}" mkdir -p "${backup}" /System/State/desktop/enlightenment 2>/dev/null || true

  for profile in default standard; do
    dir="/Users/auzix/.e/e/config/${profile}"
    [ -d "${dir}" ] || continue
    if "${BB}" grep -R "wizard" "${dir}" >/dev/null 2>&1; then
      "${BB}" mkdir -p "${backup}/${profile}" 2>/dev/null || true
      "${BB}" cp -a "${dir}/." "${backup}/${profile}/" 2>/dev/null || true
      "${BB}" rm -f "${dir}"/*.cfg "${dir}"/*.cfg.* 2>/dev/null || true
      echo "${dir}" >> /System/State/desktop/enlightenment/blasted-stale-configs 2>/dev/null || true
    fi
  done
}

force_enlightenment_standard_profile_root() {
  profile_file=/Users/auzix/.e/e/config/profile.cfg
  profile_text=/Work/Temp/auzix-e-profile
  "${BB}" mkdir -p /Users/auzix/.e/e/config /Users/auzix/.e/e/config/standard /Work/Temp 2>/dev/null || true
  printf standard > "${profile_text}"
  if command -v eet >/dev/null 2>&1; then
    eet -i "${profile_file}" config "${profile_text}" 0 2>/dev/null || true
  fi
  "${BB}" rm -f "${profile_text}" 2>/dev/null || true
}

prepare_enlightenment_vm_safe_state() {
  "${BB}" mkdir -p \
    /System/State/desktop/enlightenment \
    /Users/auzix/.cache/efreet \
    /Users/auzix/.config \
    /Users/auzix/.local/share \
    /Users/auzix/.e/e/config/standard \
    /Users/auzix/.elementary/config/standard 2>/dev/null || true
  mask_evas_gl_engines_root
  mask_unstable_enlightenment_modules_root
  blast_stale_enlightenment_configs_root
  prune_enlightenment_masked_modules_root
  force_enlightenment_standard_profile_root
  if [ -x /System/Tools/repair-e-state ]; then
    AUZIX_RESET_E_THEME_STATE=0 \
    AUZIX_SAFE_E_THEMES=1 \
    AUZIX_MASK_GL_EVAS=1 \
    AUZIX_MASK_UNSTABLE_E_MODULES=1 \
      /System/Tools/repair-e-state /Users/auzix auzix >/System/Logs/display/repair-e-state.log 2>&1 || true
  fi
  "${BB}" chown -R 1000:1000 \
    /Users/auzix/.cache \
    /Users/auzix/.config \
    /Users/auzix/.local \
    /Users/auzix/.e \
    /Users/auzix/.elementary 2>/dev/null || true
  "${BB}" chmod -R u+rwX \
    /Users/auzix/.cache \
    /Users/auzix/.config \
    /Users/auzix/.local \
    /Users/auzix/.e \
    /Users/auzix/.elementary 2>/dev/null || true
}

"${BB}" mkdir -p /run/auzix-iso /System/Settings/display/assets /System/Logs/display /System/State/display /Work/Temp
if is_mounted /run/auzix-iso && ! live_media_ready; then
  unmount_live_media
fi
if ! is_mounted /run/auzix-iso; then
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    for dev in $(live_media_candidates); do
      if try_mount_live_media_dev "${dev}"; then
        break 2
      fi
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
  if [ "${AUZIX_STAGE_E_CONFIG:-1}" = "1" ] && [ -f "${asset_dir}/config/profile.cfg" ]; then
    "${BB}" cp -f "${asset_dir}/config/profile.cfg" /Users/auzix/.e/e/config/profile.cfg 2>/dev/null || true
  fi
  if [ "${AUZIX_STAGE_E_CONFIG:-1}" = "1" ]; then
  for profile in standard default; do
    [ -d "${asset_dir}/config/${profile}" ] || continue
    "${BB}" mkdir -p "/Users/auzix/.e/e/config/${profile}" 2>/dev/null || true
    "${BB}" cp -a "${asset_dir}/config/${profile}/." "/Users/auzix/.e/e/config/${profile}/" 2>/dev/null || true
  done
  fi
  "${BB}" chmod -R u+rwX /Users/auzix/.e/e/config 2>/dev/null || true
  "${BB}" chown -R 1000:1000 /Users/auzix/.e 2>/dev/null || true
fi

prepare_enlightenment_vm_safe_state

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
      "${BB}" touch "${disabled_dir}/${module}.live-profile-disabled" 2>/dev/null || true
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
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
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
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -u

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands:/System/Compatibility/usr/bin
export PATH

AUZIX_RESET_E_THEME_STATE=1 AUZIX_SAFE_E_THEMES=1 /System/Tools/repair-e-state /Users/auzix auzix
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/reset-e-theme-state"

cat > "${AUZIX_ROOT}/System/Tools/start-e-supervisor" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
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
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
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

cat > "${AUZIX_ROOT}/System/Tools/auzix-stage-realworld-x11" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -u

# AUZiX real-world graphical handoff.
#
# This is intentionally boring Linux.  The prior failure loop came from forcing
# a stale monolithic xorg.conf and hand-launching E while bypassing the normal
# udev -> xorg.conf.d -> LightDM -> session path.  Debian-style live systems do
# not guess fixed event devices; they stage tiny transient InputClass/Device
# snippets, let Xorg/udev/libinput probe the bus, then let the display manager
# own the session handoff.

BB=/Programs/BusyBox/1.36.1/Commands/busybox
PATH=/System/Compatibility/sbin:/System/Compatibility/bin:/System/Compatibility/usr/sbin:/System/Compatibility/usr/bin:/Programs/BusyBox/1.36.1/Commands
export PATH

log=/System/Logs/display/realworld-x11-stage.log

say() {
  "${BB}" mkdir -p /System/Logs/display 2>/dev/null || true
  printf '[realworld-x11] %s\n' "$*" | "${BB}" tee -a "${log}" >/dev/null 2>&1 || true
}

ensure_link() {
  name="$1"
  target="$2"
  # Compatibility aliases are the POSIX ABI contract for software that does not
  # honor AUZiX paths yet.  Do not replace real directories here; that belongs
  # in the image/package build, not in the graphical bootstrap.
  if [ -L "/${name}" ]; then
    current="$("${BB}" readlink "/${name}" 2>/dev/null || true)"
    [ "${current}" = "${target}" ] || {
      "${BB}" rm -f "/${name}" 2>/dev/null || true
      "${BB}" ln -s "${target}" "/${name}" 2>/dev/null || true
    }
  elif [ ! -e "/${name}" ]; then
    "${BB}" ln -s "${target}" "/${name}" 2>/dev/null || true
  fi
}

ensure_posix_contract() {
  ensure_link etc /System/Settings
  ensure_link usr /System/Compatibility/usr
  ensure_link lib /System/Compatibility/lib
  ensure_link lib64 /System/Compatibility/lib64

  if [ ! -e /var ]; then
    "${BB}" mkdir -p /System/State/var 2>/dev/null || true
    "${BB}" ln -s /System/State/var /var 2>/dev/null || true
  fi

  "${BB}" mkdir -p \
    /System/Logs/display \
    /System/Logs/lightdm \
    /System/State/lightdm/cache \
    /System/State/lightdm/data/lightdm \
    /System/State/var/log \
    /System/State/var/lib/lightdm/data \
    /run/lightdm \
    /run/user/1000 \
    /tmp/.X11-unix 2>/dev/null || true

  "${BB}" chown root:root / /System /System/Settings /System/Compatibility /Programs /Services 2>/dev/null || true
  "${BB}" chmod 0755 / /System /System/Settings /System/Compatibility /Programs /Services 2>/dev/null || true
  "${BB}" chmod 1777 /tmp /tmp/.X11-unix 2>/dev/null || true
  "${BB}" chown -R 1000:1000 /run/user/1000 /Users/auzix/.cache /Users/auzix/.config /Users/auzix/.local /Users/auzix/.e /Users/auzix/.elementary 2>/dev/null || true
  "${BB}" chmod 0700 /run/user/1000 2>/dev/null || true
}

ensure_dbus_machine_id() {
  "${BB}" mkdir -p /System/State/dbus /run/dbus-state /run/dbus 2>/dev/null || true
  "${BB}" chown root:root /System/State/dbus /run/dbus-state /run/dbus 2>/dev/null || true
  "${BB}" chmod 0755 /System/State/dbus /run/dbus-state /run/dbus 2>/dev/null || true

  machine_id=""
  [ -s /System/State/dbus/machine-id ] && machine_id="$("${BB}" head -n 1 /System/State/dbus/machine-id 2>/dev/null || true)"
  [ -z "${machine_id}" ] && [ -s /run/dbus-state/machine-id ] && machine_id="$("${BB}" head -n 1 /run/dbus-state/machine-id 2>/dev/null || true)"
  [ -z "${machine_id}" ] && [ -r /proc/sys/kernel/random/uuid ] && machine_id="$("${BB}" tr -d '-' </proc/sys/kernel/random/uuid 2>/dev/null || true)"
  [ -n "${machine_id}" ] || machine_id=00000000000000000000000000000000

  printf '%s\n' "${machine_id}" >/System/State/dbus/machine-id 2>/dev/null || true
  "${BB}" cp -f /System/State/dbus/machine-id /run/dbus-state/machine-id 2>/dev/null || true
  "${BB}" chmod 0644 /System/State/dbus/machine-id /run/dbus-state/machine-id 2>/dev/null || true
}

start_system_bus() {
  command -v dbus-daemon >/dev/null 2>&1 || return 0
  ensure_dbus_machine_id
  if [ -S /run/dbus/system_bus_socket ] &&
     "${BB}" ps | "${BB}" grep "dbus-daemon --system" | "${BB}" grep -v grep >/dev/null 2>&1; then
    return 0
  fi
  "${BB}" rm -f /run/dbus/system_bus_socket 2>/dev/null || true
  dbus-daemon --system --fork --nopidfile >/System/Logs/lightdm/dbus-system.log 2>&1 || true
}

stage_xorg_conf_d() {
  xconf=/etc/X11/xorg.conf.d
  "${BB}" mkdir -p "${xconf}" /System/Settings/X11/xorg.conf.d 2>/dev/null || true
  "${BB}" rm -f "${xconf}/10-video.conf" "${xconf}/40-input.conf" "${xconf}/50-keyboard.conf" 2>/dev/null || true

  # Xorg feeds its generated keymap to xkbcomp through stdin
  # (`xkbcomp ... - ...`).  On the current AUZiX root the Xorg/XKB pairing can
  # hand xkbcomp an empty stdin stream during first server bootstrap.  Debian's
  # normal package/config stack supplies sane defaults before this point; AUZiX
  # must do that explicitly until the package scripts own it.
  if [ -x /Programs/Xorg/host/Commands/xkbcomp.real ]; then
    if [ -f /Programs/Xorg/host/Commands/xkbcomp ] &&
       "${BB}" grep -q 'xkbcomp-wrapper.log' /Programs/Xorg/host/Commands/xkbcomp 2>/dev/null; then
      "${BB}" mv /Programs/Xorg/host/Commands/xkbcomp /Programs/Xorg/host/Commands/xkbcomp.wrapper-disabled 2>/dev/null || true
    fi
    if [ -L /Programs/Xorg/host/Commands/xkbcomp ]; then
      "${BB}" rm -f /Programs/Xorg/host/Commands/xkbcomp 2>/dev/null || true
    fi
    cat >/Programs/Xorg/host/Commands/xkbcomp <<'EOF'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -u
BB=/Programs/BusyBox/1.36.1/Commands/busybox
REAL=/Programs/Xorg/host/Commands/xkbcomp.real
needs_stdin=0
for arg in "$@"; do
  [ "${arg}" = "-" ] && needs_stdin=1
done
if [ "${needs_stdin}" = "1" ]; then
  in=/tmp/auzix-xkbcomp-stdin-$$.xkb
  "${BB}" cat >"${in}" 2>/dev/null || true
  if [ ! -s "${in}" ]; then
    cat >"${in}" <<'XKB'
xkb_keymap {
  xkb_keycodes  { include "evdev+aliases(qwerty)" };
  xkb_types     { include "complete" };
  xkb_compat    { include "complete" };
  xkb_symbols   { include "pc+us+inet(evdev)" };
  xkb_geometry  { include "pc(pc105)" };
};
XKB
  fi
  exec "${REAL}" "$@" <"${in}"
fi
exec "${REAL}" "$@"
EOF
    "${BB}" chmod 0755 /Programs/Xorg/host/Commands/xkbcomp 2>/dev/null || true
    "${BB}" ln -sfn /Programs/Xorg/host/Commands/xkbcomp /usr/bin/xkbcomp 2>/dev/null || true
  fi

  video_driver=modesetting
  if command -v udevadm >/dev/null 2>&1; then
    if udevadm info --export-db 2>/dev/null | "${BB}" grep -qi "qxl"; then
      # modesetting is the safest baseline across QXL/VirtIO/VMware in AUZiX
      # because it avoids binding the live image to one hypervisor-specific DDX.
      video_driver=modesetting
    elif udevadm info --export-db 2>/dev/null | "${BB}" grep -qi "virtio"; then
      video_driver=modesetting
    fi
  fi

  cat >"${xconf}/10-video.conf" <<EOF
Section "Device"
    Identifier "AuzixAutodetectedVideo"
    Driver     "${video_driver}"
    Option     "AccelMethod" "none"
    Option     "DRI" "false"
EndSection
EOF

  cat >"${xconf}/40-input.conf" <<'EOF'
Section "InputClass"
    Identifier "QEMU Explicit Keyboard"
    MatchIsKeyboard "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
    Option "XkbRules" "evdev"
    Option "XkbModel" "pc105"
    Option "XkbLayout" "us"
EndSection

Section "InputClass"
    Identifier "Auzix libinput pointer catchall"
    MatchIsPointer "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
EndSection

Section "InputClass"
    Identifier "Auzix libinput tablet catchall"
    MatchIsTablet "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
EndSection
EOF

  cat >"${xconf}/50-keyboard.conf" <<'EOF'
Section "InputClass"
    Identifier "Auzix default keyboard"
    MatchIsKeyboard "on"
    Driver "libinput"
    Option "XkbRules" "evdev"
    Option "XkbModel" "pc105"
    Option "XkbLayout" "us"
EndSection
EOF

  # Keep a mirror under /System/Settings for inspection, but LightDM/Xorg should
  # discover the snippets through the standard /etc/X11/xorg.conf.d path.
  "${BB}" cp -f "${xconf}/"*.conf /System/Settings/X11/xorg.conf.d/ 2>/dev/null || true
  [ -f /etc/X11/xorg.conf ] && "${BB}" mv /etc/X11/xorg.conf /etc/X11/xorg.conf.auzix-disabled 2>/dev/null || true
  say "xorg-conf-d=ready video=${video_driver}"
}

write_lightdm_conf() {
  "${BB}" mkdir -p /System/Settings/lightdm /System/State/lightdm/cache /System/Logs/lightdm /run/lightdm 2>/dev/null || true
  cat >/System/Tools/auzix-xorg-realworld <<'EOF'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -u

BB=/Programs/BusyBox/1.36.1/Commands/busybox
PATH=/System/Compatibility/sbin:/System/Compatibility/bin:/System/Compatibility/usr/sbin:/System/Compatibility/usr/bin:/Programs/BusyBox/1.36.1/Commands
export PATH

export XKB_BINDIR=/usr/bin
export XKB_CONFIG_ROOT=/usr/share/X11/xkb
export XLOCALEDIR=/usr/share/X11/locale
export XKB_DEFAULT_RULES=evdev
export XKB_DEFAULT_MODEL=pc105
export XKB_DEFAULT_LAYOUT=us

"${BB}" mkdir -p /System/Logs/display /tmp/.X11-unix 2>/dev/null || true
"${BB}" chmod 1777 /tmp /tmp/.X11-unix 2>/dev/null || true
{
  printf '[auzix-xorg-realworld] argv:'
  for arg in "$@"; do printf ' <%s>' "$arg"; done
  printf '\n'
  printf '[auzix-xorg-realworld] XKB_CONFIG_ROOT=%s XKB_BINDIR=%s\n' "${XKB_CONFIG_ROOT}" "${XKB_BINDIR}"
} >>/System/Logs/display/auzix-xorg-realworld.log 2>&1 || true

exec /System/Compatibility/bin/Xorg "$@"
EOF
  "${BB}" chmod 0755 /System/Tools/auzix-xorg-realworld 2>/dev/null || true

  cat >/System/Settings/lightdm/lightdm.conf <<'EOF'
[LightDM]
run-directory=/run/lightdm
cache-directory=/System/State/lightdm/cache
log-directory=/System/Logs/lightdm
sessions-directory=/Programs/Enlightenment/host/Resources/share/xsessions:/System/Compatibility/usr/share/xsessions:/usr/share/xsessions
greeters-directory=/System/Compatibility/usr/share/xgreeters:/usr/share/xgreeters

[Seat:*]
user-session=enlightenment-auzix
autologin-user=auzix
autologin-user-timeout=0
autologin-session=enlightenment-auzix
session-wrapper=/System/Tools/lightdm-auzix-session
greeter-session=lightdm-gtk-greeter
xserver-command=/System/Tools/auzix-xorg-realworld -modulepath /System/Drivers/Xorg/modules,/System/Compatibility/usr/lib/xorg/modules -logfile /System/Logs/display/Xorg-lightdm.log
EOF
  say "lightdm-conf=ready"
}

clean_stale_display() {
  "${BB}" touch /System/State/display/stop-gui 2>/dev/null || true
  "${BB}" killall lightdm lightdm-gtk-greeter efreetd enlightenment enlightenment_start Xorg xinit start-e-supervisor 2>/dev/null || true
  "${BB}" sleep 1
  "${BB}" killall lightdm lightdm-gtk-greeter efreetd enlightenment enlightenment_start Xorg xinit start-e-supervisor 2>/dev/null || true
  "${BB}" rm -f /System/State/display/stop-gui /tmp/.X*-lock /tmp/.X11-unix/X* /run/lightdm/* 2>/dev/null || true
}

ensure_posix_contract
start_system_bus
stage_xorg_conf_d
write_lightdm_conf
clean_stale_display

say "ready"
exit 0
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/auzix-stage-realworld-x11"

cat > "${AUZIX_ROOT}/System/Tools/start-lightdm-stage" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -u

PATH=/System/Compatibility/sbin:/System/Compatibility/bin:/System/Compatibility/usr/sbin:/System/Compatibility/usr/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox
log=/System/Logs/lightdm/start-lightdm-stage.log

ensure_dbus_machine_id() {
  # Machine-id/system DBus state is root-owned runtime state.  User sessions may
  # read it, but must not create/chown/overwrite it after we drop to uid 1000.
  [ "$("${BB}" id -u 2>/dev/null || echo 0)" = "0" ] || return 0
  "${BB}" mkdir -p /System/State/dbus /run/dbus-state 2>/dev/null || true
  # Runtime DBus state must remain writable after squashfs/live mounting.
  "${BB}" chown root:root /run/dbus-state /System/State/dbus 2>/dev/null || true
  "${BB}" chmod 0755 /run/dbus-state /System/State/dbus 2>/dev/null || true

  machine_id=""
  if [ -s /System/State/dbus/machine-id ]; then
    machine_id="$("${BB}" head -n 1 /System/State/dbus/machine-id 2>/dev/null || true)"
  elif [ -s /run/dbus-state/machine-id ]; then
    machine_id="$("${BB}" head -n 1 /run/dbus-state/machine-id 2>/dev/null || true)"
  fi

  if [ -z "${machine_id}" ] && [ -r /proc/sys/kernel/random/uuid ]; then
    machine_id="$("${BB}" tr -d '-' </proc/sys/kernel/random/uuid 2>/dev/null || true)"
  fi
  [ -n "${machine_id}" ] || machine_id=00000000000000000000000000000000

  dbus_state_dir=/System/State/dbus
  if ! ( : >"${dbus_state_dir}/.write-test" ) 2>/dev/null; then
    dbus_state_dir=/run/dbus-state
    "${BB}" mkdir -p "${dbus_state_dir}" 2>/dev/null || true
    "${BB}" chown root:root "${dbus_state_dir}" 2>/dev/null || true
    "${BB}" chmod 0755 "${dbus_state_dir}" 2>/dev/null || true
  else
    "${BB}" rm -f "${dbus_state_dir}/.write-test" 2>/dev/null || true
  fi

  "${BB}" mkdir -p /run/dbus-state "${dbus_state_dir}" 2>/dev/null || true
  "${BB}" chown root:root /run/dbus-state "${dbus_state_dir}" 2>/dev/null || true
  "${BB}" chmod 0755 /run/dbus-state "${dbus_state_dir}" 2>/dev/null || true
  if ! printf '%s\n' "${machine_id}" >"${dbus_state_dir}/machine-id" 2>/dev/null; then
    dbus_state_dir=/run/dbus-state
    printf '%s\n' "${machine_id}" >"${dbus_state_dir}/machine-id" 2>/dev/null || true
  fi
  "${BB}" cp -f "${dbus_state_dir}/machine-id" /run/dbus-state/machine-id 2>/dev/null || true
  "${BB}" chmod 0644 /run/dbus-state/machine-id "${dbus_state_dir}/machine-id" 2>/dev/null || true
}

start_system_bus() {
  [ "$("${BB}" id -u 2>/dev/null || echo 0)" = "0" ] || return 0
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

"${BB}" chown root:root / /System /System/Settings /System/Compatibility /Programs /Services 2>/dev/null || true
"${BB}" chmod 0755 / /System /System/Settings /System/Compatibility /Programs /Services /System/State /tmp 2>/dev/null || true
"${BB}" mkdir -p /System/Logs/lightdm /System/State/lightdm/cache /System/State/lightdm/data/lightdm /run/lightdm /run/user /System/State/display 2>/dev/null || true
start_system_bus

if [ -x /System/Tools/auzix-stage-realworld-x11 ]; then
  /System/Tools/auzix-stage-realworld-x11
fi

"${BB}" chown -R lightdm:lightdm /System/State/lightdm /System/Logs/lightdm /run/lightdm 2>/dev/null || true
"${BB}" chmod 0755 /System/State/lightdm /System/Logs/lightdm /run/lightdm 2>/dev/null || true

echo "lightdm-stage=starting" >>"${log}"
exec /System/Compatibility/sbin/lightdm --config /System/Settings/lightdm/lightdm.conf --debug >>"${log}" 2>&1
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/start-lightdm-stage"

cat > "${AUZIX_ROOT}/System/Tools/start-gui-stage" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -u

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox

ensure_dbus_machine_id() {
  # Machine-id/system DBus state is root-owned runtime state.  User sessions may
  # read it, but must not create/chown/overwrite it after we drop to uid 1000.
  [ "$("${BB}" id -u 2>/dev/null || echo 0)" = "0" ] || return 0
  "${BB}" mkdir -p /System/State/dbus /run/dbus-state 2>/dev/null || true
  # Runtime DBus state must remain writable after squashfs/live mounting.
  "${BB}" chown root:root /run/dbus-state /System/State/dbus 2>/dev/null || true
  "${BB}" chmod 0755 /run/dbus-state /System/State/dbus 2>/dev/null || true

  machine_id=""
  if [ -s /System/State/dbus/machine-id ]; then
    machine_id="$("${BB}" head -n 1 /System/State/dbus/machine-id 2>/dev/null || true)"
  elif [ -s /run/dbus-state/machine-id ]; then
    machine_id="$("${BB}" head -n 1 /run/dbus-state/machine-id 2>/dev/null || true)"
  fi

  if [ -z "${machine_id}" ] && [ -r /proc/sys/kernel/random/uuid ]; then
    machine_id="$("${BB}" tr -d '-' </proc/sys/kernel/random/uuid 2>/dev/null || true)"
  fi
  [ -n "${machine_id}" ] || machine_id=00000000000000000000000000000000

  dbus_state_dir=/System/State/dbus
  if ! ( : >"${dbus_state_dir}/.write-test" ) 2>/dev/null; then
    dbus_state_dir=/run/dbus-state
    "${BB}" mkdir -p "${dbus_state_dir}" 2>/dev/null || true
    "${BB}" chown root:root "${dbus_state_dir}" 2>/dev/null || true
    "${BB}" chmod 0755 "${dbus_state_dir}" 2>/dev/null || true
  else
    "${BB}" rm -f "${dbus_state_dir}/.write-test" 2>/dev/null || true
  fi

  "${BB}" mkdir -p /run/dbus-state "${dbus_state_dir}" 2>/dev/null || true
  "${BB}" chown root:root /run/dbus-state "${dbus_state_dir}" 2>/dev/null || true
  "${BB}" chmod 0755 /run/dbus-state "${dbus_state_dir}" 2>/dev/null || true
  if ! printf '%s\n' "${machine_id}" >"${dbus_state_dir}/machine-id" 2>/dev/null; then
    dbus_state_dir=/run/dbus-state
    printf '%s\n' "${machine_id}" >"${dbus_state_dir}/machine-id" 2>/dev/null || true
  fi
  "${BB}" cp -f "${dbus_state_dir}/machine-id" /run/dbus-state/machine-id 2>/dev/null || true
  "${BB}" chmod 0644 /run/dbus-state/machine-id "${dbus_state_dir}/machine-id" 2>/dev/null || true
}

ensure_dbus_machine_id
if [ "${AUZIX_PREPARE_LIVECD_STATE:-auto}" != "0" ]; then
  # HDD/live-disk boots do not always have /run/live/iso.  prepare-livecd-state
  # is useful for true live media, but must not be allowed to poison the normal
  # Debian-like display path when no live payload exists.
  if [ -d /run/live/iso ] || [ "${AUZIX_PREPARE_LIVECD_STATE:-auto}" = "1" ]; then
    /System/Tools/prepare-livecd-state || true
  fi
fi

# The seeded Enlightenment profile can contain directories copied from package
# payloads/root-owned live assets.  Do the ownership normalization while this
# stage is still root; start-enlightenment-session runs as the desktop user and
# cannot repair root-owned E config directories later.  If this drifts, E reaches
# MAIN LOOP and then fails writing e_randr2.cfg.tmp during first display setup.
"${BB}" chown -R 1000:1000 \
  /Users/auzix/.cache \
  /Users/auzix/.config \
  /Users/auzix/.local \
  /Users/auzix/.e \
  /Users/auzix/.elementary 2>/dev/null || true
"${BB}" chmod -R u+rwX \
  /Users/auzix/.cache \
  /Users/auzix/.config \
  /Users/auzix/.local \
  /Users/auzix/.e \
  /Users/auzix/.elementary 2>/dev/null || true

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
env="${env} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
desktop_groups="$("${BB}" awk -F: '
  $1=="tty" || $1=="audio" || $1=="video" || $1=="input" || $1=="render" {
    if (out != "") out = out ",";
    out = out $3
  }
  END { print out }
' /System/Settings/group 2>/dev/null || true)"
[ -n "${desktop_groups}" ] || desktop_groups="5,63,39,104,105"
"${BB}" openvt -c "${vt}" -s -- /System/Tools/auzix-run-as-uid 1000 1000 "${desktop_groups}" \
  "${BB}" env ${env} /System/Tools/start-e-supervisor \
  </dev/console >/System/Logs/display/openvt.log 2>&1 &
echo "gui-stage=starting mode=${mode} vt=${vt}"
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/start-gui-stage"

# InstalledInit is PID1 for disk boots, so it has the same rule as the
# initramfs handoff: static BusyBox first, compatibility aliases later.
cat > "${AUZIX_ROOT}/System/Boot/InstalledInit" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -u

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox

"${BB}" chown root:root / /System /System/Settings /System/Compatibility /Programs /Services 2>/dev/null || true
"${BB}" chmod 0755 / /System /System/Settings /System/Compatibility /Programs /Services /System/State /tmp 2>/dev/null || true

# Installed-root boots do not get the ISO tmpfs /System/State and /System/Logs
# preparation from /run/live/iso.  Before StartSequence can drop from root to
# the desktop uid, the full parent chain must already be searchable and the
# display/session leaves must be writable by uid 1000.  If only the leaf is
# fixed later, openvt/start-e can still fail like a classic /var/www parent
# permission mistake.
"${BB}" mkdir -p /System/Logs/display /System/State/display /System/State/desktop /run/user/1000 /Users/auzix /Work/Temp /tmp /dev/shm 2>/dev/null || true
"${BB}" chmod 0755 / /System /System/Logs /System/State /run /run/user /Users 2>/dev/null || true
"${BB}" chmod 0775 /System/Logs/display /System/State/display /System/State/desktop 2>/dev/null || true
"${BB}" chmod 1777 /Work/Temp /tmp /dev/shm 2>/dev/null || true
"${BB}" chmod 0700 /run/user/1000 2>/dev/null || true
"${BB}" chown -R 1000:1000 /System/Logs/display /System/State/display /System/State/desktop /run/user/1000 /Users/auzix 2>/dev/null || true

export AUZIX_STAGE_LIVE_ASSETS="${AUZIX_STAGE_LIVE_ASSETS:-0}"
/System/Boot/StartSequence || true

echo
echo "Auzix installed-root shell"
echo "startup=/System/Boot/StartSequence"
echo "gui=/System/Tools/start-gui-stage"
echo

if [ -c /dev/tty1 ]; then
  "${BB}" setsid "${BB}" sh -c 'echo "Auzix console shell. Run /System/Tools/start-gui-stage for desktop." >/dev/tty1; exec /Programs/BusyBox/1.36.1/Commands/busybox sh </dev/tty1 >/dev/tty1 2>&1' &
fi

if [ -e /System/Settings/display/autostart ] &&
   [ "$(cat /System/Settings/display/autostart 2>/dev/null)" != "manual" ]; then
  exec "${BB}" sh -c 'while true; do sleep 3600; done'
fi

"${BB}" cttyhack "${BB}" sh </dev/console >/dev/console 2>&1 || true
exec "${BB}" sh -c 'while true; do sleep 3600; done'
SCRIPT

chmod 0755 "${AUZIX_ROOT}/System/Boot/InstalledInit"
cp "${AUZIX_ROOT}/System/Boot/InstalledInit" "${AUZIX_ROOT}/init"
chmod 0755 "${AUZIX_ROOT}/init"
cat > "${AUZIX_ROOT}/System/Settings/display/autostart" <<TXT
${AUZIX_DISPLAY_AUTOSTART:-x11}
TXT

cat > "${AUZIX_ROOT}/System/Tools/auzix-load-module" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
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
  path="${path%.xz}"
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
  "${BB}" grep -m 1 "/${first}.xz:" "${DEPS}" 2>/dev/null && return 0
  if [ "${second}" != "${first}" ]; then
    "${BB}" grep -m 1 "/${second}:" "${DEPS}" 2>/dev/null && return 0
    "${BB}" grep -m 1 "/${second}.xz:" "${DEPS}" 2>/dev/null && return 0
  fi
  if [ "${third}" != "${first}" ]; then
    "${BB}" grep -m 1 "/${third}:" "${DEPS}" 2>/dev/null && return 0
    "${BB}" grep -m 1 "/${third}.xz:" "${DEPS}" 2>/dev/null && return 0
  fi
  return 1
}

materialize_module() {
  local rel path out
  rel="$1"
  path="${BASE}/${rel}"
  if [ -f "${path}" ]; then
    printf '%s\n' "${path}"
    return 0
  fi
  if [ -f "${path}.xz" ]; then
    out="/run/auzix-modules/${rel}"
    "${BB}" mkdir -p "$("${BB}" dirname "${out}")" 2>/dev/null || true
    if [ ! -s "${out}" ]; then
      "${BB}" xzcat "${path}.xz" >"${out}" 2>/run/auzix-xzcat.err || {
        "${BB}" cat /run/auzix-xzcat.err >&2 2>/dev/null || true
        return 1
      }
    fi
    printf '%s\n' "${out}"
    return 0
  fi
  return 1
}

load_path() {
  local rel path key deps reversed dep_line dep err insmod_path dep_rel
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
      dep_rel="${dep%.xz}"
      reversed="${dep_rel} ${reversed}"
    done
    for dep in ${reversed}; do
      [ -n "${dep}" ] || continue
      load_path "${dep}" || true
    done
  fi

  insmod_path="$(materialize_module "${rel}" || true)"
  if [ -n "${insmod_path}" ]; then
    err="/run/auzix-insmod.err"
    : > "${err}"
    if "${BB}" insmod "${insmod_path}" 2>"${err}"; then
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
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
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
  for rel in "$@"; do
    "${LOAD}" "${rel}" >>"${LOG}" 2>&1 || true
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

load_vmware_drm() {
  load_path_best_effort \
    kernel/drivers/gpu/drm/drm.ko \
    kernel/drivers/gpu/drm/drm_kms_helper.ko \
    kernel/drivers/gpu/drm/ttm/ttm.ko \
    kernel/drivers/gpu/drm/drm_ttm_helper.ko \
    kernel/drivers/gpu/drm/vmwgfx/vmwgfx.ko
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
  ehci-hcd ehci-pci uhci-hcd ohci-hcd ohci-pci xhci-hcd xhci-pci \
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
        0x15ad:*) load_vmware_drm ;;
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
# Hardware discovery runs after mount_runtime and mdev may recreate the public
# PTY node with its device-table mode.  Reassert the devpts entry only after
# this final population pass so unprivileged desktop terminals can open PTYs.
"${BB}" rm -f /dev/ptmx 2>/dev/null || true
"${BB}" ln -s pts/ptmx /dev/ptmx 2>/dev/null || true
"${BB}" chmod 0666 /dev/pts/ptmx 2>/dev/null || true

log "drm=$("${BB}" ls /sys/class/drm 2>/dev/null | "${BB}" tr '\n' ' ')"
log "dri=$("${BB}" ls /dev/dri 2>/dev/null | "${BB}" tr '\n' ' ')"
log "input=$("${BB}" ls /sys/class/input 2>/dev/null | "${BB}" tr '\n' ' ')"
log "sound=$("${BB}" ls /sys/class/sound 2>/dev/null | "${BB}" tr '\n' ' ')"

group_gid() {
  "${BB}" awk -F: -v name="$1" '$1 == name { print $3; exit }' /System/Settings/group 2>/dev/null
}

video_gid="$(group_gid video)"
render_gid="$(group_gid render)"
input_gid="$(group_gid input)"
audio_gid="$(group_gid audio)"
[ -n "${video_gid}" ] || video_gid=39
[ -n "${render_gid}" ] || render_gid=105
[ -n "${input_gid}" ] || input_gid=104
[ -n "${audio_gid}" ] || audio_gid=63

for node in /dev/dri/card*; do
  [ -e "${node}" ] || continue
  "${BB}" chgrp "${video_gid}" "${node}" 2>/dev/null || true
  "${BB}" chmod 0660 "${node}" 2>/dev/null || true
done
for node in /dev/dri/renderD*; do
  [ -e "${node}" ] || continue
  "${BB}" chgrp "${render_gid}" "${node}" 2>/dev/null || true
  "${BB}" chmod 0660 "${node}" 2>/dev/null || true
done
for node in /dev/input/event* /dev/input/mice /dev/input/mouse*; do
  [ -e "${node}" ] || continue
  "${BB}" chgrp "${input_gid}" "${node}" 2>/dev/null || true
  "${BB}" chmod 0660 "${node}" 2>/dev/null || true
done
for node in /dev/snd/*; do
  [ -e "${node}" ] || continue
  "${BB}" chgrp "${audio_gid}" "${node}" 2>/dev/null || true
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

cat > "${AUZIX_ROOT}/System/Tools/launch-rescue-terminal" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -eu

PATH=/System/Compatibility/bin:/Programs/Xterm/current/Commands:/Programs/Terminology/current/Commands:/Programs/BusyBox/current/Commands:/Programs/BusyBox/1.36.1/Commands:${PATH:-}
export PATH
export HOME="${HOME:-/Users/auzix}"
export SHELL="${SHELL:-/System/Compatibility/bin/sh}"

if command -v xterm >/dev/null 2>&1; then
  exec xterm -T "AUZiX Rescue Terminal" -e /System/Compatibility/bin/sh -lc \
    'echo AUZiX rescue terminal; exec /System/Compatibility/bin/sh -i'
fi

exec terminology -e /System/Compatibility/bin/sh -lc \
  'echo AUZiX rescue terminal; exec /System/Compatibility/bin/sh -i'
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/launch-rescue-terminal"

cat > "${AUZIX_ROOT}/System/Tools/launch-auzix-browser" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -eu

PATH=/System/Compatibility/bin:/Programs/Midori/current/Commands:/Programs/NetSurf/current/Commands:/Programs/BusyBox/current/Commands:/Programs/BusyBox/1.36.1/Commands:${PATH:-}
export PATH
export SSL_CERT_DIR="${SSL_CERT_DIR:-/System/Compatibility/etc/ssl/certs}"
export SSL_CERT_FILE="${SSL_CERT_FILE:-/System/Compatibility/etc/ssl/certs/ca-certificates.crt}"
export CURL_CA_BUNDLE="${CURL_CA_BUNDLE:-${SSL_CERT_FILE}}"
export REQUESTS_CA_BUNDLE="${REQUESTS_CA_BUNDLE:-${SSL_CERT_FILE}}"

url="${1:-https://auzietek.com}"
if command -v midori >/dev/null 2>&1; then
  exec midori "${url}"
fi
if command -v netsurf-gtk >/dev/null 2>&1; then
  exec netsurf-gtk "${url}"
fi

exec /System/Compatibility/bin/sh -lc "echo No browser found for ${url}; exec /System/Compatibility/bin/sh"
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/launch-auzix-browser"

cat > "${AUZIX_ROOT}/System/Tools/launch-auzix-files" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -eu

[ -r /System/Settings/auzix-paths.sh ] && . /System/Settings/auzix-paths.sh
PATH=/System/Compatibility/bin:/Programs/Enlightenment/current/Commands:/Programs/Enlightenment/0.27.1/Commands:/Programs/BusyBox/current/Commands:/Programs/BusyBox/1.36.1/Commands:${PATH:-}
export PATH

target="${1:-/Users/auzix}"
if command -v enlightenment_filemanager >/dev/null 2>&1; then
  exec enlightenment_filemanager "${target}"
fi
if command -v enlightenment_open >/dev/null 2>&1; then
  exec enlightenment_open "${target}"
fi

exec /System/Tools/launch-rescue-terminal
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/launch-auzix-files"

cat > "${AUZIX_ROOT}/System/Tools/start-enlightenment-session" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -u

[ -r /System/Settings/auzix-paths.sh ] && . /System/Settings/auzix-paths.sh
PATH=/Programs/BusyBox/1.36.1/Commands:/Programs/EFL/1.28.1/Commands:/Programs/Enlightenment/0.27.1/Commands:${PATH:-}
export PATH

BB=/Programs/BusyBox/1.36.1/Commands/busybox
export HOME="${HOME:-/Users/auzix}"
export SHELL="${SHELL:-/System/Compatibility/bin/sh}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-enlightenment}"
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Enlightenment}"
export XDG_MENU_PREFIX="${XDG_MENU_PREFIX:-e-}"
export XDG_DATA_DIRS="/System/Compatibility/usr/local/share:/System/Compatibility/usr/share:/System/State/flatpak/exports/share:${HOME}/.local/share/flatpak/exports/share${XDG_DATA_DIRS:+:${XDG_DATA_DIRS}}"
export XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/System/Settings/xdg:/System/Compatibility/etc/xdg}"
export E_PREFIX="${E_PREFIX:-/System/Compatibility/usr}"
export E_BIN_DIR="${E_BIN_DIR:-/System/Compatibility/usr/bin}"
export E_LIB_DIR="${E_LIB_DIR:-/System/Compatibility/usr/lib/x86_64-linux-gnu}"
export E_DATA_DIR="${E_DATA_DIR:-/System/Compatibility/usr/share/enlightenment}"
export E_CONF_DIR="${E_CONF_DIR:-/System/Settings/desktop/enlightenment}"
export E_HOME_DIR="${E_HOME_DIR:-${HOME}/.e/e}"
export ELEMENTARY_THEME="${ELEMENTARY_THEME:-default}"
export ELM_CONFIG_DIR="${ELM_CONFIG_DIR:-/System/Settings/desktop/elementary}"
export ECORE_EVAS_ENGINE="${ECORE_EVAS_ENGINE:-software_x11}"
export ELM_ENGINE="${ELM_ENGINE:-software_x11}"
export ELM_ACCEL="${ELM_ACCEL:-none}"
export E_COMP_ENGINE="${E_COMP_ENGINE:-sw}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export SSL_CERT_DIR="${SSL_CERT_DIR:-/System/Compatibility/etc/ssl/certs}"
export SSL_CERT_FILE="${SSL_CERT_FILE:-/System/Compatibility/etc/ssl/certs/ca-certificates.crt}"
export CURL_CA_BUNDLE="${CURL_CA_BUNDLE:-${SSL_CERT_FILE}}"
export REQUESTS_CA_BUNDLE="${REQUESTS_CA_BUNDLE:-${SSL_CERT_FILE}}"
export GCONV_PATH="${GCONV_PATH:-/System/Compatibility/usr/lib/x86_64-linux-gnu/gconv:/System/Compatibility/lib/x86_64-linux-gnu/gconv}"
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
      "${BB}" touch "${disabled_dir}/${module}.live-profile-disabled" 2>/dev/null || true
    fi
    "${BB}" rm -f "${HOME}/.e/e/config/standard/module.${module}.cfg" 2>/dev/null || true
  done
  "${BB}" touch /System/State/desktop/enlightenment/vm-safe-modules-applied 2>/dev/null || true
}

prune_enlightenment_masked_modules() {
  command -v eet >/dev/null 2>&1 || return 0
  drop_modules=" battery cpufreq temperature backlight connman bluez5 packagekit geolocation wizard emix everything-apps everything-files wl_buffer wl_desktop_shell wl_drm wl_text_input wl_weekeyboard wl_wl wl_x11 xwayland "
  "${BB}" mkdir -p "${XDG_CACHE_HOME:-${HOME}/.cache}" /System/State/desktop/enlightenment 2>/dev/null || true

  for cfg in \
    "${HOME}/.e/e/config/standard/e.cfg" \
    "${HOME}/.e/e/config/default/e.cfg" \
    /System/Compatibility/usr/share/enlightenment/data/config/standard/e.cfg \
    /System/Compatibility/usr/share/enlightenment/data/config/default/e.cfg \
    /usr/share/enlightenment/data/config/standard/e.cfg \
    /usr/share/enlightenment/data/config/default/e.cfg
  do
    [ -s "${cfg}" ] || continue
    txt="${XDG_CACHE_HOME:-${HOME}/.cache}/e-module-prune.$$.$("${BB}" basename "$("${BB}" dirname "${cfg}")").txt"
    safe="${txt}.safe"
    new="${txt}.eet"
    if eet -d "${cfg}" config "${txt}" 2>/dev/null; then
      "${BB}" awk -v drop="${drop_modules}" '
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
      ' "${txt}" > "${safe}" 2>/dev/null || true
      if [ -s "${safe}" ] &&
         ! "${BB}" cmp -s "${txt}" "${safe}" 2>/dev/null &&
         eet -e "${new}" config "${safe}" 0 2>/dev/null; then
        "${BB}" cp -f "${cfg}" "${cfg}.pre-auzix-module-prune" 2>/dev/null || true
        "${BB}" cp -f "${new}" "${cfg}" 2>/dev/null || true
        echo "${cfg}" >> /System/State/desktop/enlightenment/pruned-module-configs 2>/dev/null || true
      fi
    fi
    "${BB}" rm -f "${txt}" "${safe}" "${new}" 2>/dev/null || true
  done
}

blast_stale_enlightenment_configs() {
  [ "${AUZIX_BLAST_STALE_E_CONFIG:-1}" = "1" ] || return 0
  stamp="$(date +%Y%m%dT%H%M%SZ 2>/dev/null || echo now)"
  backup="${HOME}/.e/backup/stale-config-blast-${stamp}"
  "${BB}" mkdir -p "${backup}" /System/State/desktop/enlightenment 2>/dev/null || true

  for profile in default standard; do
    dir="${HOME}/.e/e/config/${profile}"
    [ -d "${dir}" ] || continue
    if "${BB}" grep -R "wizard" "${dir}" >/dev/null 2>&1; then
      "${BB}" mkdir -p "${backup}/${profile}" 2>/dev/null || true
      "${BB}" cp -a "${dir}/." "${backup}/${profile}/" 2>/dev/null || true
      "${BB}" rm -f "${dir}"/*.cfg "${dir}"/*.cfg.* 2>/dev/null || true
      echo "${dir}" >> /System/State/desktop/enlightenment/blasted-stale-configs 2>/dev/null || true
    fi
  done
}

disable_enlightenment_first_run_wizard() {
  [ "${AUZIX_DISABLE_E_WIZARD:-1}" = "1" ] || return 0
  disabled_dir=/System/State/desktop/enlightenment/disabled-modules
  module_root=/System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/modules
  wizard_dir="${module_root}/wizard"
  "${BB}" mkdir -p "${disabled_dir}" "${HOME}/.e/e/config/standard" 2>/dev/null || true
  if [ -d "${wizard_dir}" ]; then
    "${BB}" touch "${disabled_dir}/wizard.live-profile-disabled" 2>/dev/null || true
  fi
  "${BB}" rm -f \
    "${HOME}/.e/e/config/standard/module.wizard.cfg" \
    "${HOME}/.e/e/config/default/module.wizard.cfg" \
    "${HOME}/.e/e/config/module.wizard.cfg" 2>/dev/null || true
  "${BB}" touch "${HOME}/.e/e/config/standard/.auzix-wizard-disabled" 2>/dev/null || true
  "${BB}" touch /System/State/desktop/enlightenment/wizard-disabled 2>/dev/null || true
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
      "${BB}" awk -v drop=" battery cpufreq temperature backlight connman bluez5 packagekit geolocation wizard emix everything-apps everything-files wl_buffer wl_desktop_shell wl_drm wl_text_input wl_weekeyboard wl_wl wl_x11 xwayland " '
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
    "${profile_dir}/module.geolocation.cfg" \
    "${profile_dir}/module.emix.cfg" \
    "${profile_dir}/module.everything-apps.cfg" \
    "${profile_dir}/module.everything-files.cfg" \
    "${profile_dir}/module.wizard.cfg" 2>/dev/null || true
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
blast_stale_enlightenment_configs
prune_enlightenment_masked_modules
disable_enlightenment_first_run_wizard
normalize_enlightenment_profile
blast_stale_enlightenment_configs
prune_enlightenment_masked_modules
disable_enlightenment_first_run_wizard

start_efreet_session() {
  # Efreet is part of the desktop-session spine.  Starting it here makes menu
  # discovery deterministic on a fresh user profile instead of depending on E
  # eventually spawning it after the first desktop has appeared.
  [ "${AUZIX_PRESTART_EFREETD:-1}" = "1" ] || return 0
  command -v efreetd >/dev/null 2>&1 || return 0
  if "${BB}" ps | "${BB}" grep '[e]freetd' >/dev/null 2>&1; then
    return 0
  fi
  "${BB}" mkdir -p "${XDG_CACHE_HOME}/efreet" /System/Logs/display 2>/dev/null || true
  efreetd >>/System/Logs/display/efreetd.log 2>&1 &
  "${BB}" sleep 1
}

ensure_dbus_session() {
  "${BB}" mkdir -p "${XDG_RUNTIME_DIR}" 2>/dev/null || true
  "${BB}" chown "$(id -u 2>/dev/null || echo 1000):$(id -g 2>/dev/null || echo 1000)" "${XDG_RUNTIME_DIR}" 2>/dev/null || true
  "${BB}" chmod 0700 "${XDG_RUNTIME_DIR}" 2>/dev/null || true
  if [ -S "${XDG_RUNTIME_DIR}/bus" ]; then
    return 0
  fi
  if command -v dbus-daemon >/dev/null 2>&1; then
    dbus-daemon --session --address="${DBUS_SESSION_BUS_ADDRESS}" --fork --nopidfile \
      >>/System/Logs/display/dbus-session.log 2>&1 || true
  fi
}

ensure_dbus_session
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
      "${BB}" touch "${disabled_dir}/${module}.live-profile-disabled" 2>/dev/null || true
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
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -u

[ -r /System/Settings/auzix-paths.sh ] && . /System/Settings/auzix-paths.sh
PATH=/Programs/BusyBox/1.36.1/Commands:/Programs/Xorg/current/Commands:/Programs/Xorg/host/Commands:/Programs/EFL/current/Commands:/Programs/EFL/host/Commands:/Programs/EFL/1.28.1/Commands:/Programs/Enlightenment/current/Commands:/Programs/Enlightenment/host/Commands:/Programs/Enlightenment/0.27.1/Commands:${PATH:-}
export PATH

BB=/Programs/BusyBox/1.36.1/Commands/busybox
MODE="${AUZIX_E_MODE:-x11}"
LOG=/System/Logs/display/start-e.log

trace_start_e() {
  msg="[start-e] $*"
  echo "${msg}" >>"${LOG}" 2>/dev/null || true
}

export HOME="${HOME:-/Users/root}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"
export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-enlightenment}"
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Enlightenment}"
export XDG_MENU_PREFIX="${XDG_MENU_PREFIX:-e-}"
export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/System/Compatibility/usr/local/share:/System/Compatibility/usr/share:/Programs/Enlightenment/host/Resources/share:/Programs/EFL/host/Resources/share}"
export XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/System/Settings/xdg:/System/Compatibility/etc/xdg}"
export XORG_RUN_AS_USER_OK="${XORG_RUN_AS_USER_OK:-1}"
export XKB_BINDIR="${XKB_BINDIR:-/Programs/Xorg/current/Commands}"
export XKB_CONFIG_ROOT="${XKB_CONFIG_ROOT:-/System/Settings/X11/xkb}"
export XLOCALEDIR="${XLOCALEDIR:-/System/Compatibility/usr/share/X11/locale}"
export ECORE_EVAS_ENGINE="${ECORE_EVAS_ENGINE:-software_x11}"
export ELM_ENGINE="${ELM_ENGINE:-software_x11}"
export ELM_ACCEL="${ELM_ACCEL:-none}"
export E_COMP_ENGINE="${E_COMP_ENGINE:-sw}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export SSL_CERT_DIR="${SSL_CERT_DIR:-/System/Compatibility/etc/ssl/certs}"
export SSL_CERT_FILE="${SSL_CERT_FILE:-/System/Compatibility/etc/ssl/certs/ca-certificates.crt}"
export CURL_CA_BUNDLE="${CURL_CA_BUNDLE:-${SSL_CERT_FILE}}"
export REQUESTS_CA_BUNDLE="${REQUESTS_CA_BUNDLE:-${SSL_CERT_FILE}}"
export GCONV_PATH="${GCONV_PATH:-/System/Compatibility/usr/lib/x86_64-linux-gnu/gconv:/System/Compatibility/lib/x86_64-linux-gnu/gconv}"
export LANG="${LANG:-C}"
export LC_ALL="${LC_ALL:-C}"
"${BB}" mkdir -p /System/Logs/display /System/State/display /Work/Temp /dev/shm 2>/dev/null || true
"${BB}" mount -t tmpfs tmpfs /dev/shm -o mode=1777,nosuid,nodev 2>/dev/null || true
"${BB}" chmod 1777 /dev/shm /Work/Temp /tmp 2>/dev/null || true
"${BB}" touch "${LOG}" 2>/dev/null || LOG="${HOME}/.auzix-start-e.log"
trace_start_e "begin uid=$("${BB}" id -u 2>/dev/null || echo unknown) home=${HOME} runtime=${XDG_RUNTIME_DIR} mode=${MODE} log=${LOG}"
"${BB}" mkdir -p "${HOME}" "${XDG_RUNTIME_DIR}" "${XDG_CACHE_HOME}" "${XDG_CONFIG_HOME}" "${XDG_DATA_HOME}" "${XDG_CACHE_HOME}/efreet"
"${BB}" chmod 0700 "${XDG_RUNTIME_DIR}" 2>/dev/null || true
"${BB}" chmod 0666 /dev/ptmx /dev/pts/ptmx 2>/dev/null || true
trace_start_e "base-runtime-ready"

if [ "${HOME}" = "/Users/auzix" ]; then
  trace_start_e "user-home-prep-begin"
  "${BB}" mkdir -p \
    /Users/auzix/.cache \
    /Users/auzix/.cache/efreet \
    /Users/auzix/.config \
    /Users/auzix/.e/e \
    /Users/auzix/.elementary/config/standard 2>/dev/null || true
  if [ ! -s /Users/auzix/.e/e/config/standard/e.cfg ] &&
     [ -d /System/Compatibility/usr/share/enlightenment/data/config/standard ]; then
    "${BB}" mkdir -p /Users/auzix/.e/e/config
    "${BB}" cp -a /System/Compatibility/usr/share/enlightenment/data/config/standard /Users/auzix/.e/e/config/ 2>/dev/null || true
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
	  trace_start_e "user-home-chown-done"
	  if [ -x /System/Tools/repair-e-state ]; then
	    trace_start_e "repair-e-state-begin"
	    /System/Tools/repair-e-state /Users/auzix auzix >/System/Logs/display/repair-e-state.log 2>&1 || true
	    trace_start_e "repair-e-state-done"
	  fi
fi

if [ -x /System/Tools/auzix-hw-detect ]; then
  /System/Tools/auzix-hw-detect display >/System/Logs/display/hardware-display.log 2>&1 ||
    /System/Tools/auzix-hw-detect display >"${HOME}/.auzix-hardware-display.log" 2>&1 || true
fi

ensure_dbus_machine_id() {
  # Machine-id/system DBus state is root-owned runtime state.  User sessions may
  # read it, but must not create/chown/overwrite it after we drop to uid 1000.
  [ "$("${BB}" id -u 2>/dev/null || echo 0)" = "0" ] || return 0
  "${BB}" mkdir -p /System/State/dbus /run/dbus-state 2>/dev/null || true
  # Runtime DBus state must remain writable after squashfs/live mounting.
  "${BB}" chown root:root /run/dbus-state /System/State/dbus 2>/dev/null || true
  "${BB}" chmod 0755 /run/dbus-state /System/State/dbus 2>/dev/null || true

  machine_id=""
  if [ -s /System/State/dbus/machine-id ]; then
    machine_id="$("${BB}" head -n 1 /System/State/dbus/machine-id 2>/dev/null || true)"
  elif [ -s /run/dbus-state/machine-id ]; then
    machine_id="$("${BB}" head -n 1 /run/dbus-state/machine-id 2>/dev/null || true)"
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
    "${BB}" chown root:root "${dbus_state_dir}" 2>/dev/null || true
    "${BB}" chmod 0755 "${dbus_state_dir}" 2>/dev/null || true
  else
    "${BB}" rm -f "${dbus_state_dir}/.write-test" 2>/dev/null || true
  fi

  "${BB}" mkdir -p /run/dbus-state "${dbus_state_dir}" 2>/dev/null || true
  "${BB}" chown root:root /run/dbus-state "${dbus_state_dir}" 2>/dev/null || true
  "${BB}" chmod 0755 /run/dbus-state "${dbus_state_dir}" 2>/dev/null || true
  if ! printf '%s\n' "${machine_id}" >"${dbus_state_dir}/machine-id" 2>/dev/null; then
    dbus_state_dir=/run/dbus-state
    printf '%s\n' "${machine_id}" >"${dbus_state_dir}/machine-id" 2>/dev/null || true
  fi
  "${BB}" cp -f "${dbus_state_dir}/machine-id" /run/dbus-state/machine-id 2>/dev/null || true
  "${BB}" chmod 0644 /run/dbus-state/machine-id "${dbus_state_dir}/machine-id" 2>/dev/null || true
}

start_system_bus() {
  [ "$("${BB}" id -u 2>/dev/null || echo 0)" = "0" ] || return 0
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
  # Autodetection is the default. A caller may still select a relative config
  # explicitly; Xorg.wrap rejects absolute paths while elevated.
  if [ -n "${XORG_CONFIG_FILE:-}" ]; then
    echo "mode=x11 command=${xinit} ${enlightenment} -- ${xorg} :0 vt${vt} -keeptty -nolisten tcp -config ${XORG_CONFIG_FILE}" | "${BB}" tee "${LOG}"
    trace_exec "${xinit}" "${enlightenment}" -- "${xorg}" :0 "vt${vt}" -keeptty -nolisten tcp \
      -config "${XORG_CONFIG_FILE}" >>"${LOG}" 2>&1
  else
    echo "mode=x11 command=${xinit} ${enlightenment} -- ${xorg} :0 vt${vt} -keeptty -nolisten tcp" | "${BB}" tee "${LOG}"
    trace_exec "${xinit}" "${enlightenment}" -- "${xorg}" :0 "vt${vt}" -keeptty -nolisten tcp \
      >>"${LOG}" 2>&1
  fi
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
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -u

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox
TARGET="${1:-/}"
LINK_MODE="${AUZIX_LINK_MODE:-}"

case "${TARGET}" in
  "") TARGET="/" ;;
esac

if [ -z "${LINK_MODE}" ] && [ -r /proc/cmdline ]; then
  for arg in $(${BB} cat /proc/cmdline 2>/dev/null || true); do
    case "${arg}" in
      auzix.links=*) LINK_MODE="${arg#auzix.links=}" ;;
      auzix.strict-links|auzix.links=off|auzix.links=none) LINK_MODE=strict ;;
    esac
  done
fi
LINK_MODE="${LINK_MODE:-strict}"

compat_links_enabled() {
  case "${LINK_MODE}" in
    full|compat|legacy|on|yes) return 0 ;;
    *) return 1 ;;
  esac
}

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

link_file() {
  source_path="$1"
  target_file="$2"
  [ -e "${source_path}" ] || return 0
  target_abs="$(target_path "${target_file}")"
  link_source="${source_path}"
  case "${TARGET}" in
    /|"") ;;
    *)
      target_prefix="${TARGET%/}"
      case "${source_path}" in
        "${target_prefix}"/*) link_source="${source_path#${target_prefix}}" ;;
      esac
      ;;
  esac
  "${BB}" mkdir -p "$("${BB}" dirname "${target_abs}")" 2>/dev/null || true
  if [ -L "${target_abs}" ]; then
    current_target="$("${BB}" readlink "${target_abs}" 2>/dev/null || true)"
    [ "${current_target}" = "${link_source}" ] && return 0
    # Do not churn live inodes by default.  A mismatched compatibility link is
    # safer left alone than relinked under running X/E/DBus/libc consumers.
    compat_links_enabled || return 0
    "${BB}" rm -f "${target_abs}" 2>/dev/null || return 0
  elif [ -e "${target_abs}" ]; then
    compat_links_enabled || return 0
    "${BB}" mv "${target_abs}" "${target_abs}.before-auzix-finalizer" 2>/dev/null || return 0
  fi
  [ -e "${target_abs}" ] || "${BB}" ln -s "${link_source}" "${target_abs}" 2>/dev/null || true
}

link_tree_files() {
  source_dir="$1"
  target_dir="$2"
  [ -d "${source_dir}" ] || return 0
  "${BB}" find "${source_dir}" -type f 2>/dev/null | while IFS= read -r source_file; do
    rel="${source_file#${source_dir}/}"
    link_file "${source_file}" "${target_dir}/${rel}"
  done
}

ensure_busybox_applets() {
  busybox_bin="$(target_path /Programs/BusyBox/current/Commands/busybox)"
  busybox_link=/Programs/BusyBox/current/Commands/busybox
  if [ ! -x "${busybox_bin}" ]; then
    busybox_bin="$(target_path /Programs/BusyBox/1.36.1/Commands/busybox)"
    busybox_link=/Programs/BusyBox/1.36.1/Commands/busybox
  fi
  [ -x "${busybox_bin}" ] || return 0
  mkdir_p /System/Compatibility/bin
  for applet in \
    sh ash cat ls pwd whoami id env printenv echo true false test expr \
    grep egrep fgrep sed awk cut tr sort uniq head tail wc \
    ps kill killall sleep date uname hostname dmesg \
    mkdir rmdir touch chmod chown chgrp ln cp mv rm basename dirname readlink realpath \
    find xargs tar gzip gunzip zcat ar dd stat df du free mount umount sync \
    less more vi which; do
    target_abs="$(target_path "/System/Compatibility/bin/${applet}")"
    if [ -L "${target_abs}" ]; then
      current_target="$("${BB}" readlink "${target_abs}" 2>/dev/null || true)"
      [ "${current_target}" = "${busybox_link}" ] && continue
      compat_links_enabled || continue
      "${BB}" rm -f "${target_abs}" 2>/dev/null || continue
    elif [ -e "${target_abs}" ]; then
      continue
    fi
    "${BB}" ln -s "${busybox_link}" "${target_abs}" 2>/dev/null || true
  done
}

normalize_target_symlinks() {
  case "${TARGET}" in
    /|"") return 0 ;;
  esac
  target_prefix="${TARGET%/}"
  [ -d "${target_prefix}" ] || return 0
  "${BB}" find "${target_prefix}" -xdev -type l -print 2>/dev/null | while IFS= read -r link_path; do
    link_target="$("${BB}" readlink "${link_path}" 2>/dev/null || true)"
    case "${link_target}" in
      "${target_prefix}"/*)
        # This is not creation of a legacy compatibility surface.  It removes
        # the temporary installer mount from an otherwise valid absolute link.
        # Skipping this in strict mode leaves /init, sh, mount, and every other
        # BusyBox applet unexecutable after switch_root.
        fixed_target="${link_target#${target_prefix}}"
        "${BB}" ln -sfn "${fixed_target}" "${link_path}" 2>/dev/null || true
        ;;
    esac
  done
}

assert_no_staging_symlinks() {
  case "${TARGET}" in
    /|"") return 0 ;;
  esac
  target_prefix="${TARGET%/}"
  stale_links="$("${BB}" find "${target_prefix}" -xdev -type l -lname "${target_prefix}/*" -print 2>/dev/null || true)"
  if [ -n "${stale_links}" ]; then
    echo "fatal: installed root retains staging-qualified symlinks:" >&2
    echo "${stale_links}" >&2
    return 1
  fi
}

ensure_program_current_links() {
  programs_root="$(target_path /Programs)"
  [ -d "${programs_root}" ] || return 0
  for program_dir in "${programs_root}"/*; do
    [ -d "${program_dir}" ] || continue
    if [ -e "${program_dir}/current" ] || [ -L "${program_dir}/current" ]; then
      continue
    fi
    latest=""
    for version_dir in "${program_dir}"/*; do
      [ -d "${version_dir}" ] || continue
      case "$("${BB}" basename "${version_dir}")" in
        current|RootFS) continue ;;
      esac
      latest="${version_dir}"
    done
    [ -n "${latest}" ] || continue
    link_target="/Programs/$("${BB}" basename "${program_dir}")/$("${BB}" basename "${latest}")"
    "${BB}" ln -sfn "${link_target}" "${program_dir}/current" 2>/dev/null || true
  done
}

disable_live_installer_autostart() {
  # Installed roots should not keep launching the installer every desktop login.
  # Keep browser/terminal/file-manager conveniences, but strip the live-only
  # destructive installer startup hooks.
  for autostart_dir in \
    /Users/auzix/.config/autostart \
    /Users/auzix/.e/e/applications/startup; do
    [ -d "$(target_path "${autostart_dir}")" ] || continue
    if [ -f "$(target_path "${autostart_dir}/auzix-installer.desktop")" ]; then
      "${BB}" mv \
        "$(target_path "${autostart_dir}/auzix-installer.desktop")" \
        "$(target_path "${autostart_dir}/auzix-installer.desktop.disabled")" 2>/dev/null || true
    fi
  done
  order_file="$(target_path /Users/auzix/.e/e/applications/startup/.order)"
  if [ -f "${order_file}" ]; then
    "${BB}" grep -v '^auzix-installer.desktop$' "${order_file}" > "${order_file}.tmp" 2>/dev/null || true
    "${BB}" mv "${order_file}.tmp" "${order_file}" 2>/dev/null || true
    "${BB}" chown 1000:1000 "${order_file}" 2>/dev/null || true
  fi
}

refresh_program_surfaces() {
  programs_root="$(target_path /Programs)"
  [ -d "${programs_root}" ] || return 0

  ensure_program_current_links

  if ! compat_links_enabled; then
    printf 'finalizer link mode %s: skipping compatibility surface refresh\n' "${LINK_MODE}" >&2
    return 0
  fi

  mkdir_p \
    /System/Compatibility/usr/share/applications \
    /System/Compatibility/usr/share/dbus-1/services \
    /System/Compatibility/usr/share/dbus-1/system-services \
    /System/Compatibility/usr/share/dbus-1/system.d \
    /System/Compatibility/usr/share/glib-2.0/schemas \
    /System/Compatibility/usr/libexec \
    /System/Compatibility/usr/lib/x86_64-linux-gnu \
    /System/Compatibility/lib/x86_64-linux-gnu \
    /System/Compatibility/usr/bin \
    /System/Compatibility/bin \
    /usr/libexec \
    /usr/bin

  for rootfs in "${programs_root}"/*/current/RootFS; do
    [ -d "${rootfs}" ] || continue

    link_tree_files "${rootfs}/usr/share/applications" /System/Compatibility/usr/share/applications
    link_tree_files "${rootfs}/usr/share/dbus-1/services" /System/Compatibility/usr/share/dbus-1/services
    link_tree_files "${rootfs}/usr/share/dbus-1/system-services" /System/Compatibility/usr/share/dbus-1/system-services
    link_tree_files "${rootfs}/usr/share/dbus-1/system.d" /System/Compatibility/usr/share/dbus-1/system.d
    link_tree_files "${rootfs}/usr/share/glib-2.0/schemas" /System/Compatibility/usr/share/glib-2.0/schemas
    link_tree_files "${rootfs}/usr/libexec" /System/Compatibility/usr/libexec
    link_tree_files "${rootfs}/usr/libexec" /usr/libexec

    # DBus-activated helpers often execute directly from /usr/libexec and do
    # not inherit AUZiX command-wrapper library ladders. Keep the conventional
    # compatibility lib directories pointing at the newest installed package
    # payloads so services such as Flatpak portals, Pluma, and GTK helpers do
    # not fail one library at a time.
    for libdir in "${rootfs}/usr/lib/x86_64-linux-gnu" "${rootfs}/lib/x86_64-linux-gnu"; do
      [ -d "${libdir}" ] || continue
      "${BB}" find "${libdir}" -maxdepth 1 -type f -name '*.so*' 2>/dev/null | while IFS= read -r libfile; do
        base="$("${BB}" basename "${libfile}")"
        link_file "${libfile}" "/System/Compatibility/usr/lib/x86_64-linux-gnu/${base}"
        link_file "${libfile}" "/System/Compatibility/lib/x86_64-linux-gnu/${base}"
      done
      "${BB}" find "${libdir}" -maxdepth 1 -type l -name '*.so*' 2>/dev/null | while IFS= read -r liblink; do
        resolved="$("${BB}" readlink -f "${liblink}" 2>/dev/null || true)"
        [ -n "${resolved}" ] || continue
        base="$("${BB}" basename "${liblink}")"
        link_file "${resolved}" "/System/Compatibility/usr/lib/x86_64-linux-gnu/${base}"
        link_file "${resolved}" "/System/Compatibility/lib/x86_64-linux-gnu/${base}"
      done
    done
  done

  # Debian's libglib2.0-bin exposes /usr/bin/glib-compile-schemas as a symlink
  # to a binary shipped by libglib2.0-0t64. Preserve that cross-package target
  # explicitly; otherwise schema compilation appears present but execs as
  # "not found".
  for schema_compiler in \
    "${programs_root}/Libglib200t64/current/RootFS/usr/lib/x86_64-linux-gnu/glib-2.0/glib-compile-schemas" \
    "${programs_root}/Libglib20Bin/current/RootFS/usr/lib/x86_64-linux-gnu/glib-2.0/glib-compile-schemas" \
    "${programs_root}/Libglib20Bin/current/RootFS/usr/bin/glib-compile-schemas"; do
    if [ -x "${schema_compiler}" ]; then
      link_file "${schema_compiler}" /System/Compatibility/usr/bin/glib-compile-schemas
      link_file "${schema_compiler}" /usr/bin/glib-compile-schemas
      "${schema_compiler}" "$(target_path /System/Compatibility/usr/share/glib-2.0/schemas)" >/dev/null 2>&1 || true
      break
    fi
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
  /System/Logs/installer \
  /System/Logs/packages \
  /System/State/dbus \
  /System/State/display \
  /System/State/desktop \
  /System/State/packages \
  /System/State/tmp \
  /Work/Temp \
  /dev/shm \
  /run/dbus-state \
  /run/user/1000 \
  /run/dbus \
  /run/lock

chown_path 0:0 /Users /Users/root
chmod_path 0755 /Users /Users/root /System/Logs /System/State /System/State/dbus /System/State/display /run/dbus-state /run/dbus
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
  /Users/auzix/.midori \
  /System/Logs/display \
  /System/State/display \
  /System/State/desktop
chown_path 0:1000 /System/State/packages /System/Logs/installer /System/Logs/packages
chmod_path 0775 /System/State/packages /System/Logs/installer /System/Logs/packages /System/Logs/display
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

ensure_busybox_applets
ensure_program_current_links
refresh_program_surfaces
normalize_target_symlinks
assert_no_staging_symlinks
disable_live_installer_autostart

printf 'finalized-installed-root=%s link_mode=%s\n' "${TARGET}" "${LINK_MODE}"
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/finalize-installed-root"

cat > "${AUZIX_ROOT}/System/Tools/auzix-packages" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -eu

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox
JQ=/Programs/AuzixPackageTools/current/Commands/jq
[ -x "${JQ}" ] || JQ=/System/Compatibility/bin/jq

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
    if [ -s /System/State/packages/installed.json ]; then
      "${BB}" cat /System/State/packages/installed.json
    elif [ -s /System/Settings/packages/installed.json ]; then
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
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -eu

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox
JQ=/Programs/AuzixPackageTools/current/Commands/jq
[ -x "${JQ}" ] || JQ=/System/Compatibility/bin/jq

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
before_receipts="/run/auzix-install-package-before.$$"
after_receipts="/run/auzix-install-package-after.$$"
new_receipts="/run/auzix-install-package-new.$$"
find "${target_root%/}/System/PackageDB" -maxdepth 1 -type f -name '*.json' -print 2>/dev/null | sort >"${before_receipts}" || : >"${before_receipts}"
"${BB}" tar -xzpf "${package}" -C "${target_root}"
find "${target_root%/}/System/PackageDB" -maxdepth 1 -type f -name '*.json' -print 2>/dev/null | sort >"${after_receipts}" || : >"${after_receipts}"
comm -13 "${before_receipts}" "${after_receipts}" >"${new_receipts}" 2>/dev/null || cp "${after_receipts}" "${new_receipts}"

if [ -x "${JQ}" ]; then
  state_dir="${target_root%/}/System/State/packages"
  installed_json="${state_dir}/installed.json"
  "${BB}" mkdir -p "${state_dir}"
  if [ ! -s "${installed_json}" ]; then
    printf '%s\n' '{"format":"auzix-installed-v1","installed":[]}' >"${installed_json}"
  fi
  while IFS= read -r receipt; do
    [ -s "${receipt}" ] || continue
    tmp_state="${installed_json}.tmp.$$"
    installed_at="$("${BB}" date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || "${BB}" date)"
    "${JQ}" \
      --slurpfile package_state "${receipt}" \
      --arg receipt "${receipt}" \
      --arg installed_at "${installed_at}" '
        ($package_state[0]) as $package
        |
        .installed = (
          [.installed[] | select((.name | ascii_downcase) != ($package.name | ascii_downcase))]
          + [{
              name: $package.name,
              version: $package.version,
              kind: $package.kind,
              package: ($package.package // ""),
              sha256: ($package.sha256 // ""),
              description: ($package.description // ""),
              receipt: $receipt,
              prefix: ($package.prefix // ""),
              commands: ($package.commands // []),
              desktop_entries: ($package.desktop_entries // []),
              compatibility_exports: ($package.compatibility_exports // []),
              depends: ($package.depends // []),
              recommends: ($package.recommends // []),
              source_metadata: ($package.source // {}),
              runtime_ladder: ($package.runtime_ladder // null),
              runtime_environment: ($package.runtime_environment // null),
              permissions: ($package.permissions // null),
              validation: ($package.validation // null),
              installed_at: $installed_at
            }]
          | sort_by(.name | ascii_downcase)
        )
      ' "${installed_json}" >"${tmp_state}" && "${BB}" mv "${tmp_state}" "${installed_json}"
    hook="$("${JQ}" -r '.hooks.post_install // empty' "${receipt}" 2>/dev/null || true)"
    if [ -n "${hook}" ] && [ "${target_root}" = "/" ]; then
      AUZIX_PACKAGE_NAME="$("${JQ}" -r '.name // empty' "${receipt}")" \
        AUZIX_PACKAGE_VERSION="$("${JQ}" -r '.version // empty' "${receipt}")" \
        /System/Compatibility/bin/sh -c "${hook}"
    fi
  done <"${new_receipts}"
fi
rm -f "${before_receipts}" "${after_receipts}" "${new_receipts}"
if [ -x "${target_root%/}/System/Tools/finalize-installed-root" ]; then
    AUZIX_LINK_MODE="${AUZIX_LINK_MODE:-strict}" \
    "${target_root%/}/System/Tools/finalize-installed-root" "${target_root}"
fi
echo "Installed package ${package} into ${target_root}"
SCRIPT

chmod 0755 "${AUZIX_ROOT}/System/Tools/auzix-install-package"

cat > "${AUZIX_ROOT}/System/Tools/auzix-install-disk" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
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
repo_url=""
profile_path=""

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
    --repo)
      repo_url="${2:-}"
      shift 2
      ;;
    --repo=*)
      repo_url="${1#--repo=}"
      shift
      ;;
    --profile)
      profile_path="${2:-}"
      shift 2
      ;;
    --profile=*)
      profile_path="${1#--profile=}"
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

if [ -n "${profile_path}" ]; then
  profile_installer=/System/Tools/auzix-install-root-from-repo-profile
  if [ ! -x "${profile_installer}" ]; then
    echo "Profile install requested, but ${profile_installer} is missing." >&2
    exit 1
  fi
  if [ -n "${repo_url}" ]; then
    exec "${profile_installer}" --force --bootloader "${bootloader}" --repo "${repo_url}" --profile "${profile_path}" "${target}"
  fi
  exec "${profile_installer}" --force --bootloader "${bootloader}" --profile "${profile_path}" "${target}"
fi

INSTALL_TOTAL_STAGES=9

install_stage() {
  step="$1"
  total="$2"
  shift 2
  echo "INSTALL_STAGE step=${step} total=${total} label=$*"
}

activate_installed_desktop_surfaces() {
  target_root="$1"
  prefix="${target_root%/}/Programs/AuzixDesktopIntegration/current"
  [ -d "${prefix}/Resources" ] || return 0

  "${BB}" mkdir -p \
    "${target_root%/}/etc/xdg/menus" \
    "${target_root%/}/System/Settings/xdg/menus" \
    "${target_root%/}/System/Compatibility/usr/share/desktop-directories" \
    "${target_root%/}/System/Compatibility/usr/share/applications" \
    "${target_root%/}/Users/auzix/.config" \
    "${target_root%/}/Users/auzix/.local/share/applications" \
    "${target_root%/}/Users/auzix/.e/e/applications/menu/all" \
    "${target_root%/}/Users/auzix/.e/e/applications/menu/favorite" \
    "${target_root%/}/Users/auzix/.e/e/applications/bar/default" \
    "${target_root%/}/Users/auzix/.cache/efreet"

  if [ -f "${prefix}/Resources/xdg/menus/e-applications.menu" ]; then
    "${BB}" cp "${prefix}/Resources/xdg/menus/e-applications.menu" \
      "${target_root%/}/etc/xdg/menus/e-applications.menu"
    "${BB}" cp "${prefix}/Resources/xdg/menus/e-applications.menu" \
      "${target_root%/}/System/Settings/xdg/menus/e-applications.menu"
  fi
  for item in "${prefix}"/Resources/desktop-directories/*.directory; do
    [ -f "${item}" ] || continue
    "${BB}" cp "${item}" "${target_root%/}/System/Compatibility/usr/share/desktop-directories/$("${BB}" basename "${item}")"
  done
  for item in "${prefix}"/Resources/applications/*.desktop; do
    [ -f "${item}" ] || continue
    base="$("${BB}" basename "${item}")"
    "${BB}" cp "${item}" "${target_root%/}/System/Compatibility/usr/share/applications/${base}"
    "${BB}" cp "${item}" "${target_root%/}/Users/auzix/.local/share/applications/${base}"
  done
  if [ -f "${prefix}/Resources/config/mimeapps.list" ]; then
    "${BB}" cp "${prefix}/Resources/config/mimeapps.list" "${target_root%/}/Users/auzix/.config/mimeapps.list"
    "${BB}" cp "${prefix}/Resources/config/mimeapps.list" "${target_root%/}/Users/auzix/.local/share/applications/mimeapps.list"
  fi

  appdir="${target_root%/}/System/Compatibility/usr/share/applications"
  ebase="${target_root%/}/Users/auzix/.e/e/applications"
  approved='
auzix-libreoffice-startcenter.desktop
auzix-libreoffice-calc.desktop
auzix-libreoffice-writer.desktop
auzix-libreoffice-impress.desktop
auzix-libreoffice-draw.desktop
auzix-libreoffice-math.desktop
auzix-libreoffice-base.desktop
auzix-AbiWord-abiword.desktop
auzix-abiword.desktop
auzix-Gnumeric-org.gnumeric.gnumeric.desktop
auzix-gnumeric.desktop
auzix-Geany-geany.desktop
auzix-Pluma-pluma.desktop
auzix-Micro-micro.desktop
auzix-Htop-htop.desktop
auzix-Galculator-galculator.desktop
auzix-midori.desktop
auzix-netsurf.desktop
netsurf-gtk.desktop
io.github.kolunmi.Bazaar.desktop
auzix-flatpak.desktop
auzix-installer.desktop
auzix-package-setup.desktop
auzix-terminal.desktop
terminology.desktop
auzix-xterm.desktop
'
  for name in ${approved}; do
    [ -f "${appdir}/${name}" ] || continue
    "${BB}" cp "${appdir}/${name}" "${ebase}/menu/all/${name}" 2>/dev/null || true
  done
  cat >"${ebase}/bar/default/.order" <<'ORDER'
auzix-midori.desktop
auzix-installer.desktop
auzix-package-setup.desktop
auzix-terminal.desktop
terminology.desktop
auzix-xterm.desktop
ORDER
  cat >"${ebase}/menu/favorite/.order" <<'ORDER'
auzix-midori.desktop
auzix-installer.desktop
auzix-package-setup.desktop
auzix-terminal.desktop
terminology.desktop
auzix-xterm.desktop
ORDER
  "${BB}" rm -f "${target_root%/}/Users/auzix/.cache/efreet/"* 2>/dev/null || true
  "${BB}" chown -R 1000:1000 \
    "${target_root%/}/Users/auzix/.config" \
    "${target_root%/}/Users/auzix/.local" \
    "${target_root%/}/Users/auzix/.e" \
    "${target_root%/}/Users/auzix/.cache" 2>/dev/null || true
}

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

part_path() {
  case "${target}" in
    *nvme*|*mmcblk*) printf '%sp%s\n' "${target}" "$1" ;;
    *) printf '%s%s\n' "${target}" "$1" ;;
  esac
}

partition="$(part_path 1)"
home_partition="$(part_path 2)"
work_partition="$(part_path 3)"

plan_field() {
  expr="$1"
  default="$2"
  if [ -n "${AUZIX_INSTALL_PLAN:-}" ] && [ -s "${AUZIX_INSTALL_PLAN}" ] && command -v jq >/dev/null 2>&1; then
    jq -r "${expr} // \"${default}\"" "${AUZIX_INSTALL_PLAN}" 2>/dev/null || printf '%s\n' "${default}"
  else
    printf '%s\n' "${default}"
  fi
}

plan_number() {
  expr="$1"
  default="$2"
  value="$(plan_field "${expr}" "${default}")"
  case "${value}" in
    ''|*[!0-9]*) printf '%s\n' "${default}" ;;
    *) printf '%s\n' "${value}" ;;
  esac
}

storage_layout="$(plan_field '.storage.layout' 'whole')"
users_percent="$(plan_number '.storage.users_percent' '20')"
work_percent="$(plan_number '.storage.work_percent' '20')"
programs_percent="$(plan_number '.storage.programs_percent' '40')"
case "${storage_layout}" in
  whole|user-work-programs) ;;
  *) echo "Unsupported executable storage layout: ${storage_layout}" >&2; exit 2 ;;
esac

is_mounted() {
  "${BB}" grep -q " $1 " /proc/mounts 2>/dev/null
}

mount_live_media_for_install() {
  [ -d /run/auzix-iso ] || "${BB}" mkdir -p /run/auzix-iso
  if is_mounted /run/auzix-iso; then
    return 0
  fi
  for dev in \
    /dev/disk/by-label/AUZIXLIVE \
    /dev/disk/by-label/ISOIMAGE \
    /dev/vda3 /dev/vda2 \
    /dev/sda3 /dev/sda2 \
    /dev/sdb3 /dev/sdb2 \
    /dev/xvda3 /dev/xvda2 \
    /dev/nvme0n1p3 /dev/nvme0n1p2 \
    /dev/sdb /dev/sda /dev/vda /dev/xvda \
    /dev/sr0 /dev/cdrom /dev/hdc
  do
    [ -e "${dev}" ] || continue
    for fstype in iso9660 ext4 vfat; do
      "${BB}" mount -t "${fstype}" -o ro "${dev}" /run/auzix-iso 2>/dev/null || continue
      if [ -d /run/auzix-iso/boot ]; then
        return 0
      fi
      "${BB}" umount /run/auzix-iso 2>/dev/null || true
    done
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
  root_mount_spec="${root_boot_spec:-LABEL=AUZIXROOT}"
  cat > /Work/InstallTarget/System/Settings/fstab <<EOF
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
devtmpfs /dev devtmpfs defaults 0 0
devpts /dev/pts devpts gid=5,mode=620,ptmxmode=666 0 0
tmpfs /dev/shm tmpfs mode=1777,nosuid,nodev 0 0
tmpfs /run tmpfs defaults 0 0
${root_mount_spec} / ${root_fstype} defaults 0 1
EOF
  if [ "${storage_layout}" = "user-work-programs" ]; then
    cat >> /Work/InstallTarget/System/Settings/fstab <<EOF
LABEL=AUZIXHOME /Home ${root_fstype} defaults 0 2
LABEL=AUZIXWORK /Work ${root_fstype} defaults 0 2
# /Programs allocation intent: ${programs_percent} percent. Kept in the boot root until AUZiX early-boot mount staging can mount /Programs before /Programs/BusyBox is required.
EOF
  fi
}

write_grub_cfg() {
  kernel=""
  initrd=""
  root_spec="${root_boot_spec:-LABEL=AUZIXROOT}"
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
    linux ${kernel} root=${root_spec} auzix.root=${partition} init=/init rw
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

install_stage 1 "${INSTALL_TOTAL_STAGES}" "preparing target disk ${target}"
echo "Creating Auzix partition on ${target}"
"${BB}" dd if=/dev/zero of="${target}" bs=1M count=8
if [ "${storage_layout}" = "user-work-programs" ]; then
  install_stage 2 "${INSTALL_TOTAL_STAGES}" "partitioning split AUZiX layout"
  parted_cmd="$(find_cmd /System/Compatibility/usr/sbin/parted /System/Compatibility/sbin/parted parted || true)"
  [ -n "${parted_cmd}" ] || {
    echo "Default split layout requires parted in the live installer environment." >&2
    exit 1
  }
  data_total=$((users_percent + work_percent))
  [ "${data_total}" -le 80 ] || {
    echo "Invalid default split: /Home + /Work must leave at least 20 percent for the boot root." >&2
    exit 2
  }
  home_start=$((100 - data_total))
  home_end=$((home_start + users_percent))
  work_end=$((home_end + work_percent))
  echo "Partitioning ${target}: root 1MiB-${home_start}%, /Home ${home_start}-${home_end}%, /Work ${home_end}-${work_end}%"
  "${parted_cmd}" -s "${target}" mklabel msdos
  "${parted_cmd}" -s "${target}" mkpart primary ext4 1MiB "${home_start}%"
  "${parted_cmd}" -s "${target}" mkpart primary ext4 "${home_start}%" "${home_end}%"
  "${parted_cmd}" -s "${target}" mkpart primary ext4 "${home_end}%" "${work_end}%"
else
  install_stage 2 "${INSTALL_TOTAL_STAGES}" "partitioning simple AUZiX root"
  # BusyBox fdisk may inherit legacy CHS geometry and otherwise choose sector 32.
  # Reserve the conventional 1 MiB embedding area required by BIOS GRUB.
  printf 'o\nn\np\n1\n2048\n\nw\n' | "${BB}" fdisk "${target}"
fi
"${BB}" partprobe "${target}" 2>/dev/null || true
"${BB}" sleep 2

if [ ! -b "${partition}" ]; then
  echo "Partition was not discovered: ${partition}" >&2
  exit 1
fi

install_stage 3 "${INSTALL_TOTAL_STAGES}" "formatting filesystems"
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
  if [ "${storage_layout}" = "user-work-programs" ]; then
    [ -b "${home_partition}" ] || { echo "Home partition was not discovered: ${home_partition}" >&2; exit 1; }
    [ -b "${work_partition}" ] || { echo "Work partition was not discovered: ${work_partition}" >&2; exit 1; }
    "${mkfs_ext4}" -F -L AUZIXHOME "${home_partition}"
    "${mkfs_ext4}" -F -L AUZIXWORK "${work_partition}"
  fi
  root_fstype=ext4
elif [ -n "${mke2fs}" ]; then
  "${mke2fs}" -F -t ext4 -L AUZIXROOT "${partition}"
  if [ "${storage_layout}" = "user-work-programs" ]; then
    [ -b "${home_partition}" ] || { echo "Home partition was not discovered: ${home_partition}" >&2; exit 1; }
    [ -b "${work_partition}" ] || { echo "Work partition was not discovered: ${work_partition}" >&2; exit 1; }
    "${mke2fs}" -F -t ext4 -L AUZIXHOME "${home_partition}"
    "${mke2fs}" -F -t ext4 -L AUZIXWORK "${work_partition}"
  fi
  root_fstype=ext4
else
  if [ "${AUZIX_ALLOW_EXT2_FALLBACK:-0}" != "1" ]; then
    echo "ext4 tooling is unavailable; refusing normal install." >&2
    echo "Install E2fsprogs in the live environment first, or set AUZIX_ALLOW_EXT2_FALLBACK=1 for emergency ext2 mode." >&2
    exit 1
  fi
  echo "WARNING: ext4 tooling is unavailable; emergency AUZIX_ALLOW_EXT2_FALLBACK=1 selected, falling back to non-journaled ext2." >&2
  "${BB}" mkfs.ext2 -F -L AUZIXROOT "${partition}"
fi

install_stage 4 "${INSTALL_TOTAL_STAGES}" "mounting target filesystems"
root_uuid="$("${BB}" blkid "${partition}" 2>/dev/null | "${BB}" sed -n 's/.*UUID="\([^"]*\)".*/\1/p' | "${BB}" head -n 1 || true)"
if [ -n "${root_uuid}" ]; then
  root_boot_spec="UUID=${root_uuid}"
else
  root_boot_spec="LABEL=AUZIXROOT"
  echo "WARNING: could not resolve UUID for ${partition}; falling back to label-based boot spec." >&2
fi
"${BB}" mkdir -p /Work/InstallTarget
"${BB}" mount "${partition}" /Work/InstallTarget
is_mounted /Work/InstallTarget || {
  echo "Target partition did not mount at /Work/InstallTarget." >&2
  exit 1
}
if [ "${storage_layout}" = "user-work-programs" ]; then
  "${BB}" mkdir -p /Work/InstallTarget/Home /Work/InstallTarget/Work /Work/InstallTarget/Programs
  "${BB}" mount "${home_partition}" /Work/InstallTarget/Home
  "${BB}" mount "${work_partition}" /Work/InstallTarget/Work
  is_mounted /Work/InstallTarget/Home || { echo "Home partition did not mount at /Work/InstallTarget/Home." >&2; exit 1; }
  is_mounted /Work/InstallTarget/Work || { echo "Work partition did not mount at /Work/InstallTarget/Work." >&2; exit 1; }
fi

install_stage 5 "${INSTALL_TOTAL_STAGES}" "copying AUZiX root"
echo "Copying live Auzix root to ${partition}"
(
  cd /
  tar \
    --exclude='./dev/*' \
    --exclude='./proc/*' \
    --exclude='./sys/*' \
    --exclude='./run/*' \
    --exclude='./Work/Temp/*' \
    --exclude='./Users/*/.config/mozilla/*/storage/*' \
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
  install_stage 6 "${INSTALL_TOTAL_STAGES}" "finalizing installed root"
  AUZIX_LINK_MODE="${AUZIX_LINK_MODE:-strict}" \
    /Work/InstallTarget/System/Tools/finalize-installed-root /Work/InstallTarget
fi
install_stage 6 "${INSTALL_TOTAL_STAGES}" "activating installed desktop surfaces"
activate_installed_desktop_surfaces /Work/InstallTarget
if [ -x /Work/InstallTarget/Programs/AuzixPackageTools/current/Commands/auzix-pkg ]; then
  install_stage 6 "${INSTALL_TOTAL_STAGES}" "bootstrapping installed package receipts"
  "${BB}" chroot /Work/InstallTarget /Programs/BusyBox/current/Commands/busybox env \
    /Programs/AuzixPackageTools/current/Commands/auzix-pkg bootstrap-receipts /System/PackageDB
  "${BB}" chroot /Work/InstallTarget /Programs/BusyBox/current/Commands/busybox env \
    /Programs/AuzixPackageTools/current/Commands/auzix-pkg refresh-ldcache 2>/dev/null || true
fi
if [ -x /System/Tools/probe-auzix-desktop-launchers ]; then
  "${BB}" mkdir -p /Work/InstallTarget/System/Logs/packages
  /System/Tools/probe-auzix-desktop-launchers /Work/InstallTarget \
    >/Work/InstallTarget/System/Logs/packages/desktop-launcher-probe-install.txt 2>&1 || true
fi
install_stage 7 "${INSTALL_TOTAL_STAGES}" "writing installed configuration"
write_installed_fstab "${root_fstype}"
copy_boot_payload
"${BB}" mkdir -p /Work/InstallTarget/boot/grub
write_grub_cfg 2>/dev/null || true
"${BB}" mkdir -p /Work/InstallTarget/System/State/install
"${BB}" date > /Work/InstallTarget/System/State/install/installed-at.txt 2>/dev/null || true
receipt_home=""
receipt_work=""
if [ "${storage_layout}" = "user-work-programs" ]; then
  receipt_home="${home_partition}"
  receipt_work="${work_partition}"
fi
cat > /Work/InstallTarget/System/State/install/storage-layout.txt <<EOF
root_build_mode=live-copy-compat
layout=${storage_layout}
root=${partition}
home=${receipt_home}
work=${receipt_work}
users_percent=${users_percent}
work_percent=${work_percent}
programs_percent=${programs_percent}
programs_note=/Programs remains inside AUZIXROOT in this installer slice because early init currently requires /Programs/BusyBox before secondary filesystems are mounted.
EOF
if [ -s /Work/InstallTarget/System/State/packages/installed.json ]; then
  "${BB}" cp /Work/InstallTarget/System/State/packages/installed.json \
    /Work/InstallTarget/System/State/install/installed-packages.json 2>/dev/null || true
elif [ -s /Work/InstallTarget/System/Settings/packages/installed.json ]; then
  "${BB}" cp /Work/InstallTarget/System/Settings/packages/installed.json \
    /Work/InstallTarget/System/State/install/installed-packages.json 2>/dev/null || true
fi
if [ -n "${AUZIX_INSTALL_PLAN:-}" ] && [ -s "${AUZIX_INSTALL_PLAN}" ]; then
  "${BB}" mkdir -p \
    /Work/InstallTarget/System/Settings/install \
    /Work/InstallTarget/System/Settings/packages \
    /Work/InstallTarget/System/State/install
  "${BB}" cp "${AUZIX_INSTALL_PLAN}" \
    /Work/InstallTarget/System/Settings/install/install-plan.json 2>/dev/null || true
  if command -v jq >/dev/null 2>&1; then
    jq -r '.packages.selected[]? // empty' "${AUZIX_INSTALL_PLAN}" \
      > /Work/InstallTarget/System/Settings/packages/first-boot-selection.list 2>/dev/null || true
    jq -c '{format:"auzix-first-boot-package-queue-v1", selected:(.packages.selected // []), source_plan:"/System/Settings/install/install-plan.json"}' \
      "${AUZIX_INSTALL_PLAN}" \
      > /Work/InstallTarget/System/Settings/packages/first-boot-queue.json 2>/dev/null || true
  else
    echo "jq missing in live root; preserved install plan but did not derive first-boot package queue." \
      > /Work/InstallTarget/System/State/install/package-queue-warning.txt
  fi
fi
if [ -n "${repo_url}" ]; then
  "${BB}" mkdir -p /Work/InstallTarget/System/Settings/packages /Work/InstallTarget/System/State/install
  printf '%s\n' "${repo_url}" > /Work/InstallTarget/System/Settings/packages/default-repository.url 2>/dev/null || true
fi
if [ -n "${profile_path}" ]; then
  "${BB}" mkdir -p /Work/InstallTarget/System/Settings/install /Work/InstallTarget/System/State/install
  printf '%s\n' "${profile_path}" > /Work/InstallTarget/System/Settings/install/requested-profile.path 2>/dev/null || true
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
  install_stage 8 "${INSTALL_TOTAL_STAGES}" "installing bootloader"
  install_grub_bootloader
elif [ "${bootloader}" != "iso" ] && [ "${bootloader}" != "none" ]; then
  echo "Unsupported bootloader: ${bootloader}" >&2
  exit 2
fi

install_stage 9 "${INSTALL_TOTAL_STAGES}" "syncing and unmounting"
"${BB}" sync
"${BB}" umount /Work/InstallTarget/Home 2>/dev/null || true
"${BB}" umount /Work/InstallTarget/Work 2>/dev/null || true
"${BB}" umount /Work/InstallTarget/proc 2>/dev/null || true
"${BB}" umount /Work/InstallTarget/sys 2>/dev/null || true
"${BB}" umount /Work/InstallTarget/dev 2>/dev/null || true
"${BB}" umount /Work/InstallTarget
echo "Installed Auzix root to ${partition}"
echo "Next boot argument: auzix.root=${partition}"
echo "INSTALL_DONE root=${partition} boot_spec=${root_boot_spec} layout=${storage_layout} bootloader=${bootloader}"
SCRIPT

chmod 0755 "${AUZIX_ROOT}/System/Tools/auzix-install-disk"
if [ -f "${ROOT_DIR}/scripts/auzix-existing-installer-preflight.sh" ]; then
  cp "${ROOT_DIR}/scripts/auzix-existing-installer-preflight.sh" \
    "${AUZIX_ROOT}/System/Tools/auzix-existing-installer-preflight"
  chmod 0755 "${AUZIX_ROOT}/System/Tools/auzix-existing-installer-preflight"
fi

cat > "${AUZIX_ROOT}/System/Settings/install/live-tools.txt" <<'TXT'
auzix-install-disk transposes the live strict root to local storage.
Use --bootloader grub for an experimental BIOS GRUB install when grub-install
is available inside the live image.
Use auzix-existing-installer-preflight before destructive disk installs to prove
the live preflight spine and to sanity-check /Work/InstallTarget after install.
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
