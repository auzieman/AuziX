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
AUTHORIZED_KEYS_SOURCE="${AUZIX_AUTHORIZED_KEYS_SOURCE:-${HOME}/.ssh/id_rsa.pub}"

log() {
  printf '[auzix-access] %s\n' "$*" >&2
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

for cmd in bash ssh scp sftp ssh-keygen ldd install; do
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

mkdir -p \
  "${BASH_PROGRAM}/Commands" \
  "${OPENSSH_PROGRAM}/Commands" \
  "${OPENSSH_PROGRAM}/Libexec" \
  "${RUNTIME_LIB}" \
  "${RUNTIME_LIB64}" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${AUZIX_ROOT}/System/Compatibility/sbin" \
  "${AUZIX_ROOT}/System/Settings/ssh" \
  "${AUZIX_ROOT}/System/State/ssh" \
  "${AUZIX_ROOT}/System/Logs/ssh" \
  "${AUZIX_ROOT}/Services/ssh" \
  "${AUZIX_ROOT}/Users/root/.ssh" \
  "${AUZIX_ROOT}/Users/auzix" \
  "${AUZIX_ROOT}/run/sshd"

if [[ -e /lib64/ld-linux-x86-64.so.2 ]]; then
  install -D -m 0755 /lib64/ld-linux-x86-64.so.2 "${RUNTIME_LIB64}/ld-linux-x86-64.so.2"
elif [[ -e /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 ]]; then
  install -D -m 0755 /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 "${RUNTIME_LIB64}/ld-linux-x86-64.so.2"
fi

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
mkdir -p "${AUZIX_ROOT}/System/State/cache" "${AUZIX_ROOT}/System/State/lib" "${AUZIX_ROOT}/System/State/log"
ln -sfn /Work/Temp "${AUZIX_ROOT}/System/State/tmp"
ln -sfn /run "${AUZIX_ROOT}/System/State/run"
ln -sfn /run/lock "${AUZIX_ROOT}/System/State/lock"
if [[ -d "${AUZIX_ROOT}/root" && ! -L "${AUZIX_ROOT}/root" ]]; then
  rmdir "${AUZIX_ROOT}/root" 2>/dev/null || true
fi
if [[ ! -e "${AUZIX_ROOT}/root" && ! -L "${AUZIX_ROOT}/root" ]]; then
  ln -s /Users/root "${AUZIX_ROOT}/root"
fi
chown 0:0 "${AUZIX_ROOT}/System/Compatibility/usr/local" 2>/dev/null || true

log "Installing Bash runtime"
copy_binary /usr/bin/bash "${BASH_PROGRAM}/Commands/bash"
ln -sfn "/Programs/Bash/${BASH_VERSION}/Commands/bash" "${AUZIX_ROOT}/System/Compatibility/bin/bash"
ln -sfn /Programs/BusyBox/1.36.1/Commands/busybox "${AUZIX_ROOT}/System/Compatibility/bin/false"

log "Installing OpenSSH runtime"
copy_binary "${SSHD_PATH}" "${OPENSSH_PROGRAM}/Commands/sshd"
copy_binary "${SSH_PATH}" "${OPENSSH_PROGRAM}/Commands/ssh"
copy_binary "${SCP_PATH}" "${OPENSSH_PROGRAM}/Commands/scp"
copy_binary "${SFTP_PATH}" "${OPENSSH_PROGRAM}/Commands/sftp"
copy_binary "${SSH_KEYGEN_PATH}" "${OPENSSH_PROGRAM}/Commands/ssh-keygen"
copy_binary "${SFTP_SERVER_PATH}" "${OPENSSH_PROGRAM}/Libexec/sftp-server"
ln -sfn "/Programs/OpenSSH/${OPENSSH_VERSION}/Commands/ssh" "${AUZIX_ROOT}/System/Compatibility/bin/ssh"
ln -sfn "/Programs/OpenSSH/${OPENSSH_VERSION}/Commands/scp" "${AUZIX_ROOT}/System/Compatibility/bin/scp"
ln -sfn "/Programs/OpenSSH/${OPENSSH_VERSION}/Commands/sftp" "${AUZIX_ROOT}/System/Compatibility/bin/sftp"
ln -sfn "/Programs/OpenSSH/${OPENSSH_VERSION}/Commands/ssh-keygen" "${AUZIX_ROOT}/System/Compatibility/bin/ssh-keygen"
ln -sfn "/Programs/OpenSSH/${OPENSSH_VERSION}/Commands/sshd" "${AUZIX_ROOT}/System/Compatibility/sbin/sshd"

for nss_lib in /lib/x86_64-linux-gnu/libnss_files.so.2 /lib/x86_64-linux-gnu/libnss_dns.so.2; do
  [[ -e "${nss_lib}" ]] && install -D -m 0755 "${nss_lib}" "${RUNTIME_LIB}/$(basename "${nss_lib}")"
done

if [[ ! -s "${AUZIX_ROOT}/System/State/ssh/ssh_host_ed25519_key" ]]; then
  log "Generating SSH host keys"
  "${SSH_KEYGEN_PATH}" -q -t ed25519 -N '' -f "${AUZIX_ROOT}/System/State/ssh/ssh_host_ed25519_key"
fi
if [[ ! -s "${AUZIX_ROOT}/System/State/ssh/ssh_host_rsa_key" ]]; then
  "${SSH_KEYGEN_PATH}" -q -t rsa -b 3072 -N '' -f "${AUZIX_ROOT}/System/State/ssh/ssh_host_rsa_key"
fi
chmod 0600 "${AUZIX_ROOT}/System/State/ssh/ssh_host_"*"_key"

if [[ -s "${AUTHORIZED_KEYS_SOURCE}" ]]; then
  install -m 0600 "${AUTHORIZED_KEYS_SOURCE}" "${AUZIX_ROOT}/Users/root/.ssh/authorized_keys"
else
  log "No authorized key found at ${AUTHORIZED_KEYS_SOURCE}; SSH key login will need manual setup."
  : > "${AUZIX_ROOT}/Users/root/.ssh/authorized_keys"
  chmod 0600 "${AUZIX_ROOT}/Users/root/.ssh/authorized_keys"
fi
chmod 0700 "${AUZIX_ROOT}/Users/root/.ssh"

cat > "${AUZIX_ROOT}/Users/root/.bash_profile" <<'EOF'
export PATH=/System/Compatibility/bin:/System/Compatibility/sbin:/Programs/BusyBox/1.36.1/Commands:/Programs/Bash/5.2-host/Commands:/Programs/OpenSSH/host/Commands
export HOME=/Users/root
export LANG=C
export LC_ALL=C
cd "${HOME}" 2>/dev/null || cd /
EOF

cat > "${AUZIX_ROOT}/Users/root/.bashrc" <<'EOF'
export PATH=/System/Compatibility/bin:/System/Compatibility/sbin:/Programs/BusyBox/1.36.1/Commands:/Programs/Bash/5.2-host/Commands:/Programs/OpenSSH/host/Commands
export LANG=C
export LC_ALL=C
alias ll='ls -l'
EOF

cat > "${AUZIX_ROOT}/Users/auzix/.bash_profile" <<'EOF'
export PATH=/System/Compatibility/bin:/System/Compatibility/sbin:/Programs/BusyBox/1.36.1/Commands:/Programs/Bash/5.2-host/Commands:/Programs/OpenSSH/host/Commands
export HOME=/Users/auzix
export LANG=C
export LC_ALL=C
cd "${HOME}" 2>/dev/null || cd /
EOF

cat > "${AUZIX_ROOT}/Users/auzix/.bashrc" <<'EOF'
export PATH=/System/Compatibility/bin:/System/Compatibility/sbin:/Programs/BusyBox/1.36.1/Commands:/Programs/Bash/5.2-host/Commands:/Programs/OpenSSH/host/Commands
export LANG=C
export LC_ALL=C
alias ll='ls -l'
EOF
chown -R 1000:1000 "${AUZIX_ROOT}/Users/auzix"

cat > "${AUZIX_ROOT}/System/Settings/passwd" <<'EOF'
root:x:0:0:root:/Users/root:/System/Compatibility/bin/bash
auzix:x:1000:1000:Auzix User:/Users/auzix:/System/Compatibility/bin/bash
sshd:x:74:74:sshd privilege separation:/run/sshd:/System/Compatibility/bin/false
messagebus:x:101:101:DBus message bus:/run/dbus:/System/Compatibility/bin/false
lightdm:x:102:102:LightDM display manager:/System/State/lightdm:/System/Compatibility/bin/false
EOF

cat > "${AUZIX_ROOT}/System/Settings/group" <<'EOF'
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

cat > "${AUZIX_ROOT}/System/Settings/shadow" <<'EOF'
root:*:19700:0:99999:7:::
auzix:$6$KWazk/HqqlvaI6Ea$vkl9YiHeS22wtMLINxyZMO6PnbMea1YYMXM5c0Osgf2AiQCDQc.ThzmQgl.21MBekV0Oi/PoVoFB6wzxzGnUT0:19700:0:99999:7:::
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

cat > "${AUZIX_ROOT}/System/Settings/ssh/sshd_config" <<EOF
Port 22
Protocol 2
ListenAddress 0.0.0.0
HostKey /System/State/ssh/ssh_host_ed25519_key
HostKey /System/State/ssh/ssh_host_rsa_key
PidFile /run/sshd.pid
AuthorizedKeysFile .ssh/authorized_keys
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM no
PrintMotd no
PermitUserEnvironment yes
StrictModes no
Subsystem sftp /Programs/OpenSSH/${OPENSSH_VERSION}/Libexec/sftp-server
EOF

cat > "${AUZIX_ROOT}/Services/ssh/run" <<EOF
#!/System/Compatibility/bin/sh
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
  ]
}
EOF

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

log "Bash installed at ${BASH_PROGRAM}/Commands/bash"
log "OpenSSH service installed at /Services/ssh/run"
