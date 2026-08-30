#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
BASH_VERSION="${AUZIX_BASH_VERSION:-5.2-host}"
OPENSSH_VERSION="${AUZIX_OPENSSH_VERSION:-host}"
BASH_PROGRAM="${AUZIX_ROOT}/Programs/Bash/${BASH_VERSION}"
OPENSSH_PROGRAM="${AUZIX_ROOT}/Programs/OpenSSH/${OPENSSH_VERSION}"
RUNTIME_LIB="${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
RUNTIME_LIB64="${AUZIX_ROOT}/System/Compatibility/lib64"
CORE_GLIBC="${AUZIX_ROOT}/System/Libraries/Runtime/glibc"
AUTHORIZED_KEYS_SOURCE="${AUZIX_AUTHORIZED_KEYS_SOURCE:-${HOME}/.ssh/id_rsa.pub}"
ACCESS_PROFILE="${AUZIX_ACCESS_PROFILE:-key-only}"
ROOT_PASSWORD_HASH_FILE="${AUZIX_ROOT_PASSWORD_HASH_FILE:-}"
LINK_MODE="${AUZIX_LINK_MODE:-strict}"
# AUZiX live/HDD media are BusyBox-first.  OpenSSH is not part of the default
# boot/access spine; if we add it later it belongs in an explicit service
# package lane (eventually /Services/OpenSSH), not as accidental live root soup.
INCLUDE_OPENSSH="${AUZIX_INCLUDE_OPENSSH:-0}"

case "${ACCESS_PROFILE}" in
  key-only)
    ROOT_SHADOW='*'
    ROOT_LOGIN_POLICY='prohibit-password'
    PASSWORD_AUTH='no'
    ;;
  lab-password)
    if [[ -z "${ROOT_PASSWORD_HASH_FILE}" || ! -s "${ROOT_PASSWORD_HASH_FILE}" ]]; then
      printf 'lab-password access profile requires AUZIX_ROOT_PASSWORD_HASH_FILE.\n' >&2
      exit 1
    fi
    ROOT_SHADOW="$(<"${ROOT_PASSWORD_HASH_FILE}")"
    if [[ "${ROOT_SHADOW}" != '$'* ]]; then
      printf 'lab-password access profile received an invalid password hash.\n' >&2
      exit 1
    fi
    ROOT_LOGIN_POLICY='yes'
    PASSWORD_AUTH='yes'
    ;;
  *)
    printf 'Unsupported AUZIX_ACCESS_PROFILE: %s\n' "${ACCESS_PROFILE}" >&2
    exit 1
    ;;
esac

case "${INCLUDE_OPENSSH}" in
  1|yes|true|on) INCLUDE_OPENSSH=1 ;;
  0|no|false|off) INCLUDE_OPENSSH=0 ;;
  *)
    printf 'Unsupported AUZIX_INCLUDE_OPENSSH: %s\n' "${INCLUDE_OPENSSH}" >&2
    exit 1
    ;;
esac

log() {
  printf '[auzix-access] %s\n' "$*" >&2
}

compat_links_enabled() {
  case "${LINK_MODE}" in
    full|compat|legacy|on|yes|1) return 0 ;;
    *) return 1 ;;
  esac
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

copy_binary() {
  local source="$1"
  local target="$2"
  install -D -m 0755 "${source}" "${target}"
  copy_runtime_deps "${source}"
  patchelf \
    --set-interpreter "/System/Libraries/Runtime/glibc/ld-linux-x86-64.so.2" \
    --set-rpath '/System/Libraries:/System/Libraries/Runtime/glibc:$ORIGIN/../Libraries:/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64' \
    "${target}"
}

copy_runtime_deps() {
  local binary="$1"
  local dep
  ldd "${binary}" | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i }' | sort -u |
  while IFS= read -r dep; do
    [[ -e "${dep}" ]] || continue
    case "${dep}" in
      /lib64/*)
        install -D -m 0755 "${dep}" "${RUNTIME_LIB64}/$(basename "${dep}")"
        ;;
      /lib/x86_64-linux-gnu/*|/usr/lib/x86_64-linux-gnu/*)
        install -D -m 0755 "${dep}" "${RUNTIME_LIB}/$(basename "${dep}")"
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

for cmd in bash ldd install patchelf; do
  require_cmd "${cmd}"
done

if [[ "${INCLUDE_OPENSSH}" == "1" ]]; then
  for cmd in ssh scp sftp ssh-keygen; do
    require_cmd "${cmd}"
  done
  SSHD_PATH="$(command -v sshd || true)"
  if [[ -z "${SSHD_PATH}" && -x /usr/sbin/sshd ]]; then
    SSHD_PATH=/usr/sbin/sshd
  fi
  if [[ -z "${SSHD_PATH}" || ! -x "${SSHD_PATH}" ]]; then
    printf 'Missing required command: sshd\n' >&2
    exit 1
  fi
  SSH_KEYGEN_PATH="$(command -v ssh-keygen)"
  SSH_PATH="$(command -v ssh)"
  SCP_PATH="$(command -v scp)"
  SFTP_PATH="$(command -v sftp)"
  SFTP_SERVER_PATH="${AUZIX_SFTP_SERVER:-/usr/lib/openssh/sftp-server}"
  if [[ ! -x "${SFTP_SERVER_PATH}" ]]; then
    printf 'Missing sftp-server. Expected %s or set AUZIX_SFTP_SERVER.\n' "${SFTP_SERVER_PATH}" >&2
    exit 1
  fi
  SSHD_SESSION_PATH="${AUZIX_SSHD_SESSION:-}"
  if [[ -z "${SSHD_SESSION_PATH}" ]]; then
    for candidate in \
      /usr/lib/openssh/sshd-session \
      /usr/libexec/openssh/sshd-session \
      /usr/lib/ssh/sshd-session; do
      if [[ -x "${candidate}" ]]; then
        SSHD_SESSION_PATH="${candidate}"
        break
      fi
    done
  fi
  if [[ -z "${SSHD_SESSION_PATH}" || ! -x "${SSHD_SESSION_PATH}" ]]; then
    printf 'Missing sshd-session helper. Set AUZIX_SSHD_SESSION or install OpenSSH server helpers.\n' >&2
    exit 1
  fi
  SSHD_AUTH_PATH="${AUZIX_SSHD_AUTH:-}"
  if [[ -z "${SSHD_AUTH_PATH}" ]]; then
    for candidate in \
      /usr/lib/openssh/sshd-auth \
      /usr/libexec/openssh/sshd-auth \
      /usr/lib/ssh/sshd-auth; do
      if [[ -x "${candidate}" ]]; then
        SSHD_AUTH_PATH="${candidate}"
        break
      fi
    done
  fi
  if [[ -z "${SSHD_AUTH_PATH}" || ! -x "${SSHD_AUTH_PATH}" ]]; then
    printf 'Missing sshd-auth helper. Set AUZIX_SSHD_AUTH or install OpenSSH server helpers.\n' >&2
    exit 1
  fi
fi

mkdir -p \
  "${BASH_PROGRAM}/Commands" \
  "${CORE_GLIBC}" \
  "${RUNTIME_LIB}" \
  "${RUNTIME_LIB64}" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${AUZIX_ROOT}/System/Compatibility/sbin" \
  "${AUZIX_ROOT}/System/Settings" \
  "${AUZIX_ROOT}/Users/root/.ssh" \
  "${AUZIX_ROOT}/Users/auzix/.cache/efreet" \
  "${AUZIX_ROOT}/Users/auzix/.config" \
  "${AUZIX_ROOT}/Users/auzix/.e/e/config" \
  "${AUZIX_ROOT}/Users/auzix/.elementary/config/standard" \
  "${AUZIX_ROOT}/Users/auzix/.local/share" \
  "${AUZIX_ROOT}/Users/auzix/.midori"

if [[ "${INCLUDE_OPENSSH}" == "1" ]]; then
  mkdir -p \
    "${OPENSSH_PROGRAM}/Commands" \
    "${OPENSSH_PROGRAM}/Libexec" \
    "${AUZIX_ROOT}/System/Settings/ssh" \
    "${AUZIX_ROOT}/System/State/ssh" \
    "${AUZIX_ROOT}/System/Logs/ssh" \
    "${AUZIX_ROOT}/Services/ssh" \
    "${AUZIX_ROOT}/run/sshd"
fi

if [[ -e /lib64/ld-linux-x86-64.so.2 ]]; then
  install -D -m 0755 /lib64/ld-linux-x86-64.so.2 "${RUNTIME_LIB64}/ld-linux-x86-64.so.2"
  install -D -m 0755 /lib64/ld-linux-x86-64.so.2 "${CORE_GLIBC}/ld-linux-x86-64.so.2"
elif [[ -e /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 ]]; then
  install -D -m 0755 /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 "${RUNTIME_LIB64}/ld-linux-x86-64.so.2"
  install -D -m 0755 /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 "${CORE_GLIBC}/ld-linux-x86-64.so.2"
fi
for core_lib in /lib/x86_64-linux-gnu/libc.so.6 /lib/x86_64-linux-gnu/libm.so.6 /lib/x86_64-linux-gnu/libgcc_s.so.1; do
  [[ -e "${core_lib}" ]] && install -D -m 0755 "${core_lib}" "${CORE_GLIBC}/$(basename "${core_lib}")"
done

if compat_links_enabled; then
  ln -sfn /System/Compatibility/lib64 "${AUZIX_ROOT}/lib64"
  if [[ ! -L "${AUZIX_ROOT}/lib" ]]; then
    mkdir -p "${AUZIX_ROOT}/lib"
    ln -sfn /System/Compatibility/lib/x86_64-linux-gnu "${AUZIX_ROOT}/lib/x86_64-linux-gnu"
  fi
  ln -sfn /System/Compatibility/bin "${AUZIX_ROOT}/bin"
  ln -sfn /System/Compatibility/sbin "${AUZIX_ROOT}/sbin"
  ln -sfn /System/Compatibility/usr "${AUZIX_ROOT}/usr"
  ln -sfn /System/Settings "${AUZIX_ROOT}/etc"
  ln -sfn /System/State "${AUZIX_ROOT}/var"
  ln -sfn /Work/Temp "${AUZIX_ROOT}/tmp"
  ln -sfn /Users "${AUZIX_ROOT}/home"
  ln -sfn /Programs "${AUZIX_ROOT}/opt"
  if [[ -d "${AUZIX_ROOT}/root" && ! -L "${AUZIX_ROOT}/root" ]]; then
    rmdir "${AUZIX_ROOT}/root" 2>/dev/null || true
  fi
  if [[ ! -e "${AUZIX_ROOT}/root" && ! -L "${AUZIX_ROOT}/root" ]]; then
    ln -s /Users/root "${AUZIX_ROOT}/root"
  fi
else
  log "strict alias mode: not creating root compatibility links"
fi
mkdir -p "${AUZIX_ROOT}/System/State/cache" "${AUZIX_ROOT}/System/State/lib" "${AUZIX_ROOT}/System/State/log"
ln -sfn /Work/Temp "${AUZIX_ROOT}/System/State/tmp"
ln -sfn /run "${AUZIX_ROOT}/System/State/run"
ln -sfn /run/lock "${AUZIX_ROOT}/System/State/lock"
chown 0:0 "${AUZIX_ROOT}/System/Compatibility/usr/local" 2>/dev/null || true

log "Installing Bash runtime"
copy_binary /usr/bin/bash "${BASH_PROGRAM}/Commands/bash"
ln -sfn "/Programs/Bash/${BASH_VERSION}/Commands/bash" "${AUZIX_ROOT}/System/Compatibility/bin/bash"
ln -sfn /Programs/BusyBox/1.36.1/Commands/busybox "${AUZIX_ROOT}/System/Compatibility/bin/false"

if [[ "${INCLUDE_OPENSSH}" == "1" ]]; then
  log "Installing OpenSSH runtime"
  copy_binary "${SSHD_PATH}" "${OPENSSH_PROGRAM}/Commands/sshd"
  copy_binary "${SSH_PATH}" "${OPENSSH_PROGRAM}/Commands/ssh"
  copy_binary "${SCP_PATH}" "${OPENSSH_PROGRAM}/Commands/scp"
  copy_binary "${SFTP_PATH}" "${OPENSSH_PROGRAM}/Commands/sftp"
  copy_binary "${SSH_KEYGEN_PATH}" "${OPENSSH_PROGRAM}/Commands/ssh-keygen"
  copy_binary "${SFTP_SERVER_PATH}" "${OPENSSH_PROGRAM}/Libexec/sftp-server"
  copy_binary "${SSHD_SESSION_PATH}" "${OPENSSH_PROGRAM}/Libexec/sshd-session"
  copy_binary "${SSHD_AUTH_PATH}" "${OPENSSH_PROGRAM}/Libexec/sshd-auth"
  ln -sfn "/Programs/OpenSSH/${OPENSSH_VERSION}/Commands/ssh" "${AUZIX_ROOT}/System/Compatibility/bin/ssh"
  ln -sfn "/Programs/OpenSSH/${OPENSSH_VERSION}/Commands/scp" "${AUZIX_ROOT}/System/Compatibility/bin/scp"
  ln -sfn "/Programs/OpenSSH/${OPENSSH_VERSION}/Commands/sftp" "${AUZIX_ROOT}/System/Compatibility/bin/sftp"
  ln -sfn "/Programs/OpenSSH/${OPENSSH_VERSION}/Commands/ssh-keygen" "${AUZIX_ROOT}/System/Compatibility/bin/ssh-keygen"
  ln -sfn "/Programs/OpenSSH/${OPENSSH_VERSION}/Commands/sshd" "${AUZIX_ROOT}/System/Compatibility/sbin/sshd"
  mkdir -p "${AUZIX_ROOT}/System/Compatibility/usr/lib/openssh"
  ln -sfn "/Programs/OpenSSH/${OPENSSH_VERSION}/Libexec/sshd-session" "${AUZIX_ROOT}/System/Compatibility/usr/lib/openssh/sshd-session"
  ln -sfn "/Programs/OpenSSH/${OPENSSH_VERSION}/Libexec/sshd-auth" "${AUZIX_ROOT}/System/Compatibility/usr/lib/openssh/sshd-auth"
  ln -sfn "/Programs/OpenSSH/${OPENSSH_VERSION}/Libexec/sftp-server" "${AUZIX_ROOT}/System/Compatibility/usr/lib/openssh/sftp-server"
else
  log "Skipping OpenSSH runtime; AUZIX_INCLUDE_OPENSSH=0"
fi

for nss_lib in /lib/x86_64-linux-gnu/libnss_files.so.2 /lib/x86_64-linux-gnu/libnss_dns.so.2; do
  [[ -e "${nss_lib}" ]] && install -D -m 0755 "${nss_lib}" "${RUNTIME_LIB}/$(basename "${nss_lib}")"
done

if [[ "${INCLUDE_OPENSSH}" == "1" && ! -s "${AUZIX_ROOT}/System/State/ssh/ssh_host_ed25519_key" ]]; then
  log "Generating SSH host keys"
  "${SSH_KEYGEN_PATH}" -q -t ed25519 -N '' -f "${AUZIX_ROOT}/System/State/ssh/ssh_host_ed25519_key"
fi
if [[ "${INCLUDE_OPENSSH}" == "1" && ! -s "${AUZIX_ROOT}/System/State/ssh/ssh_host_rsa_key" ]]; then
  "${SSH_KEYGEN_PATH}" -q -t rsa -b 3072 -N '' -f "${AUZIX_ROOT}/System/State/ssh/ssh_host_rsa_key"
fi
if [[ "${INCLUDE_OPENSSH}" == "1" ]]; then
  chmod 0600 "${AUZIX_ROOT}/System/State/ssh/ssh_host_"*"_key"
fi

if [[ -s "${AUTHORIZED_KEYS_SOURCE}" ]]; then
  install -m 0600 "${AUTHORIZED_KEYS_SOURCE}" "${AUZIX_ROOT}/Users/root/.ssh/authorized_keys"
else
  log "No authorized key found at ${AUTHORIZED_KEYS_SOURCE}; SSH key login will need manual setup."
  : > "${AUZIX_ROOT}/Users/root/.ssh/authorized_keys"
  chmod 0600 "${AUZIX_ROOT}/Users/root/.ssh/authorized_keys"
fi
chmod 0700 "${AUZIX_ROOT}/Users/root/.ssh"

cat > "${AUZIX_ROOT}/System/Settings/auzix-paths.sh" <<'EOF'
# Canonical AUZiX bootstrap path contract.
#
# This file is intentionally sourced by login shells, rescue shells, LightDM,
# X11/E startup helpers, installer launchers, and package/app wrappers.  The
# AUZiX paths come first; classic paths are retained only as compatibility
# aliases for upstream software that still hardwires them.

AUZIX_COMPAT="${AUZIX_COMPAT:-/System/Compatibility}"
AUZIX_COMPAT_USR="${AUZIX_COMPAT_USR:-${AUZIX_COMPAT}/usr}"
AUZIX_ARCH_LIB="${AUZIX_ARCH_LIB:-${AUZIX_COMPAT_USR}/lib/x86_64-linux-gnu}"
AUZIX_BASE_PATH="${AUZIX_COMPAT}/bin:${AUZIX_COMPAT}/sbin:${AUZIX_COMPAT_USR}/bin:${AUZIX_COMPAT_USR}/sbin"

AUZIX_COMMAND_PATH="${AUZIX_BASE_PATH}"
for auzix_commands in /Programs/*/current/Commands /Programs/*/*/Commands; do
  [ -d "${auzix_commands}" ] || continue
  case ":${AUZIX_COMMAND_PATH}:" in
    *":${auzix_commands}:"*) ;;
    *) AUZIX_COMMAND_PATH="${AUZIX_COMMAND_PATH}:${auzix_commands}" ;;
  esac
done
export PATH="${AUZIX_COMMAND_PATH}${PATH:+:${PATH}}"

export LD_LIBRARY_PATH="/System/Libraries:/System/Libraries/Runtime/glibc:${AUZIX_ARCH_LIB}:${AUZIX_COMPAT}/lib/x86_64-linux-gnu:${AUZIX_COMPAT}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export XDG_DATA_DIRS="${AUZIX_COMPAT_USR}/local/share:${AUZIX_COMPAT_USR}/share:/Programs/Enlightenment/current/Resources/share:/Programs/EFL/current/Resources/share${XDG_DATA_DIRS:+:${XDG_DATA_DIRS}}"
export XDG_CONFIG_DIRS="/System/Settings/xdg:${AUZIX_COMPAT}/etc/xdg${XDG_CONFIG_DIRS:+:${XDG_CONFIG_DIRS}}"
export TERM="${TERM:-xterm-256color}"
case "${TERM}" in
  ""|dumb|linux) export TERM=xterm-256color ;;
esac
export TERMINFO_DIRS="${TERMINFO_DIRS:-/Programs/NcursesBase/current/RootFS/usr/share/terminfo:/Programs/NcursesTerm/current/RootFS/usr/share/terminfo:/Programs/KittyTerminfo/current/RootFS/usr/share/terminfo:${AUZIX_COMPAT_USR}/share/terminfo:${AUZIX_COMPAT}/lib/terminfo}"

export XORG_RUN_AS_USER_OK="${XORG_RUN_AS_USER_OK:-1}"
export XKB_BINDIR="${XKB_BINDIR:-/Programs/Xorg/current/Commands}"
export XKB_CONFIG_ROOT="${XKB_CONFIG_ROOT:-/System/Settings/X11/xkb}"
export XLOCALEDIR="${XLOCALEDIR:-${AUZIX_COMPAT_USR}/share/X11/locale}"

export E_PREFIX="${E_PREFIX:-${AUZIX_COMPAT_USR}}"
export E_BIN_DIR="${E_BIN_DIR:-${AUZIX_COMPAT_USR}/bin}"
export E_LIB_DIR="${E_LIB_DIR:-${AUZIX_ARCH_LIB}}"
export E_DATA_DIR="${E_DATA_DIR:-${AUZIX_COMPAT_USR}/share/enlightenment}"
export E_CONF_DIR="${E_CONF_DIR:-/System/Settings/desktop/enlightenment}"

export SSL_CERT_DIR="${SSL_CERT_DIR:-/System/Compatibility/etc/ssl/certs}"
export SSL_CERT_FILE="${SSL_CERT_FILE:-/System/Compatibility/etc/ssl/certs/ca-certificates.crt}"
export CURL_CA_BUNDLE="${CURL_CA_BUNDLE:-${SSL_CERT_FILE}}"
export REQUESTS_CA_BUNDLE="${REQUESTS_CA_BUNDLE:-${SSL_CERT_FILE}}"
export GCONV_PATH="${GCONV_PATH:-${AUZIX_ARCH_LIB}/gconv:${AUZIX_COMPAT}/lib/x86_64-linux-gnu/gconv}"

unset AUZIX_COMMAND_PATH AUZIX_BASE_PATH AUZIX_COMPAT AUZIX_COMPAT_USR AUZIX_ARCH_LIB auzix_commands
EOF
chmod 0644 "${AUZIX_ROOT}/System/Settings/auzix-paths.sh"

cat > "${AUZIX_ROOT}/System/Settings/environment.sh" <<'EOF'
# Canonical AUZiX interactive command environment.
. /System/Settings/auzix-paths.sh
EOF
chmod 0644 "${AUZIX_ROOT}/System/Settings/environment.sh"

cat > "${AUZIX_ROOT}/Users/root/.bash_profile" <<'EOF'
. /System/Settings/environment.sh
export HOME=/Users/root
export LANG=C
export LC_ALL=C
cd "${HOME}" 2>/dev/null || cd /
EOF

cat > "${AUZIX_ROOT}/Users/root/.bashrc" <<'EOF'
. /System/Settings/environment.sh
export LANG=C
export LC_ALL=C
alias ll='ls -l'
EOF

cat > "${AUZIX_ROOT}/Users/auzix/.bash_profile" <<'EOF'
. /System/Settings/environment.sh
export HOME=/Users/auzix
export LANG=C
export LC_ALL=C
cd "${HOME}" 2>/dev/null || cd /
EOF

cat > "${AUZIX_ROOT}/Users/auzix/.bashrc" <<'EOF'
. /System/Settings/environment.sh
export LANG=C
export LC_ALL=C
alias ll='ls -l'
EOF
chown -R 1000:1000 "${AUZIX_ROOT}/Users/auzix"
chmod 0755 "${AUZIX_ROOT}/Users/auzix"
chmod -R u+rwX \
  "${AUZIX_ROOT}/Users/auzix/.cache" \
  "${AUZIX_ROOT}/Users/auzix/.config" \
  "${AUZIX_ROOT}/Users/auzix/.e" \
  "${AUZIX_ROOT}/Users/auzix/.elementary" \
  "${AUZIX_ROOT}/Users/auzix/.local" \
  "${AUZIX_ROOT}/Users/auzix/.midori" 2>/dev/null || true

cat > "${AUZIX_ROOT}/System/Settings/passwd" <<'EOF'
root:x:0:0:root:/Users/root:/System/Compatibility/bin/bash
auzix:x:1000:1000:Auzix User:/Users/auzix:/System/Compatibility/bin/bash
sshd:x:74:74:sshd privilege separation:/run/sshd:/System/Compatibility/bin/false
messagebus:x:101:101:DBus message bus:/run/dbus:/System/Compatibility/bin/false
lightdm:x:102:102:LightDM display manager:/System/State/lightdm:/System/Compatibility/bin/false
EOF

cat > "${AUZIX_ROOT}/System/Settings/group" <<'EOF'
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

cat > "${AUZIX_ROOT}/System/Settings/subuid" <<'EOF'
auzix:100000:65536
EOF
cat > "${AUZIX_ROOT}/System/Settings/subgid" <<'EOF'
auzix:100000:65536
EOF

cat > "${AUZIX_ROOT}/System/Settings/shadow" <<EOF
root:${ROOT_SHADOW}:19700:0:99999:7:::
auzix:\$6\$KWazk/HqqlvaI6Ea\$vkl9YiHeS22wtMLINxyZMO6PnbMea1YYMXM5c0Osgf2AiQCDQc.ThzmQgl.21MBekV0Oi/PoVoFB6wzxzGnUT0:19700:0:99999:7:::
sshd:*:19700:0:99999:7:::
messagebus:*:19700:0:99999:7:::
lightdm:*:19700:0:99999:7:::
EOF
chmod 0600 "${AUZIX_ROOT}/System/Settings/shadow"

cat > "${AUZIX_ROOT}/System/Settings/shells" <<'EOF'
/System/Compatibility/bin/sh
/System/Compatibility/bin/bash
EOF

cat > "${AUZIX_ROOT}/System/Settings/nsswitch.conf" <<'EOF'
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

cat > "${AUZIX_ROOT}/System/Settings/hosts" <<'EOF'
127.0.0.1 localhost auzix auzix-live
::1 localhost ip6-localhost ip6-loopback
EOF

if [[ "${INCLUDE_OPENSSH}" == "1" ]]; then
  cat > "${AUZIX_ROOT}/System/Settings/ssh/sshd_config" <<EOF
Port 22
Protocol 2
ListenAddress 0.0.0.0
HostKey /System/State/ssh/ssh_host_ed25519_key
HostKey /System/State/ssh/ssh_host_rsa_key
PidFile /run/sshd.pid
AuthorizedKeysFile .ssh/authorized_keys
PermitRootLogin ${ROOT_LOGIN_POLICY}
PasswordAuthentication ${PASSWORD_AUTH}
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM no
PrintMotd no
PermitUserEnvironment yes
StrictModes no
Subsystem sftp /Programs/OpenSSH/${OPENSSH_VERSION}/Libexec/sftp-server
EOF

  # Boot-critical service runners must not depend on /System/Compatibility/bin/sh.
  # In strict-link live media the compatibility surface is optional/late, while
  # this service is the rescue rope we need before the desktop is trustworthy.
  cat > "${AUZIX_ROOT}/Services/ssh/run" <<EOF
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -u
BB=/Programs/BusyBox/1.36.1/Commands/busybox

"\${BB}" mkdir -p /run/sshd /System/Logs/ssh
"\${BB}" chmod 0755 /run/sshd
"\${BB}" chown -R 0:0 /System/State/ssh 2>/dev/null || true
"\${BB}" chmod 0700 /System/State/ssh 2>/dev/null || true
"\${BB}" chmod 0600 /System/State/ssh/ssh_host_*_key 2>/dev/null || true
"\${BB}" chmod 0644 /System/State/ssh/ssh_host_*_key.pub 2>/dev/null || true
exec /Programs/OpenSSH/${OPENSSH_VERSION}/Commands/sshd -D -e -f /System/Settings/ssh/sshd_config
EOF
  chmod 0755 "${AUZIX_ROOT}/Services/ssh/run"
fi

cat > "${AUZIX_ROOT}/System/PackageDB/Bash-${BASH_VERSION}.auzix.json" <<EOF
{
  "name": "Bash",
  "version": "${BASH_VERSION}",
  "kind": "program",
  "migration_stage": "stage-1-compat-install",
  "prefix": "/Programs/Bash/${BASH_VERSION}",
  "commands": [
    "/Programs/Bash/${BASH_VERSION}/Commands/bash"
  ],
  "compatibility_exports": [
    "/System/Compatibility/bin/bash"
  ],
  "settings": [
    "/System/Settings/auzix-paths.sh",
    "/System/Settings/environment.sh",
    "/System/Settings/subuid",
    "/System/Settings/subgid",
    "/Users/root/.bash_profile",
    "/Users/root/.bashrc",
    "/Users/auzix/.bash_profile",
    "/Users/auzix/.bashrc"
  ]
}
EOF

if [[ "${INCLUDE_OPENSSH}" == "1" ]]; then
  cat > "${AUZIX_ROOT}/System/PackageDB/OpenSSH-${OPENSSH_VERSION}.auzix.json" <<EOF
{
  "name": "OpenSSH",
  "version": "${OPENSSH_VERSION}",
  "kind": "service",
  "migration_stage": "stage-1-compat-install",
  "prefix": "/Programs/OpenSSH/${OPENSSH_VERSION}",
  "commands": [
    "/Programs/OpenSSH/${OPENSSH_VERSION}/Commands/sshd",
    "/Programs/OpenSSH/${OPENSSH_VERSION}/Commands/ssh",
    "/Programs/OpenSSH/${OPENSSH_VERSION}/Commands/scp",
    "/Programs/OpenSSH/${OPENSSH_VERSION}/Commands/sftp",
    "/Programs/OpenSSH/${OPENSSH_VERSION}/Commands/ssh-keygen"
  ],
  "service": "/Services/ssh",
  "settings": "/System/Settings/ssh",
  "state": "/System/State/ssh",
  "logs": "/System/Logs/ssh"
}
EOF
fi

log "Bash installed at ${BASH_PROGRAM}/Commands/bash"
if [[ "${INCLUDE_OPENSSH}" == "1" ]]; then
  log "OpenSSH service installed at /Services/ssh/run"
else
  log "OpenSSH not included; install/enable the service package later"
fi
