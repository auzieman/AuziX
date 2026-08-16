#!/usr/bin/env bash
set -euo pipefail

# A thin live-media delta for an already-integrated AuziX root.  This script
# deliberately does not replace OpenSSH, Bash, or their runtime libraries:
# those are proven members of the supplied root baseline.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-iso/iso/AuzixRoot}"
ACCESS_PROFILE="${AUZIX_ACCESS_PROFILE:-lab-password}"
ROOT_PASSWORD_HASH_FILE="${AUZIX_ROOT_PASSWORD_HASH_FILE:-}"
AUTHORIZED_KEYS_SOURCE="${AUZIX_AUTHORIZED_KEYS_SOURCE:-}"
SSH_KEYGEN="${AUZIX_SSH_KEYGEN:-$(command -v ssh-keygen || true)}"

fail() { printf '[auzix-live-access] FAIL: %s\n' "$*" >&2; exit 1; }
log() { printf '[auzix-live-access] %s\n' "$*"; }

[[ -x "${AUZIX_ROOT}/Programs/OpenSSH/host/Commands/sshd" ]] || fail 'baseline OpenSSH daemon is missing'
[[ -x "${AUZIX_ROOT}/Services/ssh/run" ]] || fail 'baseline SSH service runner is missing'
[[ -f "${AUZIX_ROOT}/System/Settings/ssh/sshd_config" ]] || fail 'baseline sshd_config is missing'
[[ -f "${AUZIX_ROOT}/System/Settings/shadow" ]] || fail 'baseline shadow file is missing'

case "${ACCESS_PROFILE}" in
  lab-password)
    [[ -s "${ROOT_PASSWORD_HASH_FILE}" ]] || fail 'lab-password profile needs AUZIX_ROOT_PASSWORD_HASH_FILE'
    root_hash="$(<"${ROOT_PASSWORD_HASH_FILE}")"
    [[ "${root_hash}" == '$'* ]] || fail 'runtime root password input is not a password hash'
    root_login=yes
    password_auth=yes
    ;;
  key-only)
    root_hash='*'
    root_login=prohibit-password
    password_auth=no
    ;;
  *)
    fail "unsupported AUZIX_ACCESS_PROFILE: ${ACCESS_PROFILE}"
    ;;
esac

tmp_shadow="$(mktemp)"
awk -F: -v OFS=: -v hash="${root_hash}" '
  $1 == "root" || $1 == "auzix" { $2=hash }
  { print }
' "${AUZIX_ROOT}/System/Settings/shadow" >"${tmp_shadow}"
install -m 0600 "${tmp_shadow}" "${AUZIX_ROOT}/System/Settings/shadow"
rm -f "${tmp_shadow}"

config="${AUZIX_ROOT}/System/Settings/ssh/sshd_config"
sed -i \
  -e "s/^PermitRootLogin .*/PermitRootLogin ${root_login}/" \
  -e "s/^PasswordAuthentication .*/PasswordAuthentication ${password_auth}/" \
  "${config}"
grep -q '^PermitRootLogin ' "${config}" || printf 'PermitRootLogin %s\n' "${root_login}" >>"${config}"
grep -q '^PasswordAuthentication ' "${config}" || printf 'PasswordAuthentication %s\n' "${password_auth}" >>"${config}"

mkdir -p \
  "${AUZIX_ROOT}/Users/root/.ssh" \
  "${AUZIX_ROOT}/Users/auzix/.ssh" \
  "${AUZIX_ROOT}/System/State/ssh"
if [[ ! -s "${AUZIX_ROOT}/System/State/ssh/ssh_host_ed25519_key" ]]; then
  [[ -x "${SSH_KEYGEN}" ]] || fail 'ssh host key missing and ssh-keygen is unavailable'
  "${SSH_KEYGEN}" -q -t ed25519 -N '' \
    -f "${AUZIX_ROOT}/System/State/ssh/ssh_host_ed25519_key"
fi
if [[ ! -s "${AUZIX_ROOT}/System/State/ssh/ssh_host_rsa_key" ]]; then
  [[ -x "${SSH_KEYGEN}" ]] || fail 'ssh host key missing and ssh-keygen is unavailable'
  "${SSH_KEYGEN}" -q -t rsa -b 3072 -N '' \
    -f "${AUZIX_ROOT}/System/State/ssh/ssh_host_rsa_key"
fi
if [[ -n "${AUTHORIZED_KEYS_SOURCE}" && -s "${AUTHORIZED_KEYS_SOURCE}" ]]; then
  install -m 0600 "${AUTHORIZED_KEYS_SOURCE}" "${AUZIX_ROOT}/Users/root/.ssh/authorized_keys"
  install -m 0600 "${AUTHORIZED_KEYS_SOURCE}" "${AUZIX_ROOT}/Users/auzix/.ssh/authorized_keys"
fi
chown -R 1000:1000 "${AUZIX_ROOT}/Users/auzix/.ssh"
chmod 0700 \
  "${AUZIX_ROOT}/Users/root/.ssh" \
  "${AUZIX_ROOT}/Users/auzix/.ssh" \
  "${AUZIX_ROOT}/System/State/ssh"
chmod 0600 "${AUZIX_ROOT}/System/State/ssh/ssh_host_"*_key 2>/dev/null || true
chmod 0644 "${AUZIX_ROOT}/System/State/ssh/ssh_host_"*_key.pub 2>/dev/null || true

log "preserved baseline OpenSSH and staged ${ACCESS_PROFILE} live access"
