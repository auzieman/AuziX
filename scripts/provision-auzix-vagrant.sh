#!/usr/bin/env bash
set -euo pipefail

PROFILE_PATH="/workspace/profiles/rootfs/auzix-thin-desktop.debian-packages"
USERNAME="${AUZIX_USERNAME:-auzi}"
USER_PASSWORD="${AUZIX_PASSWORD:-auzi}"
ROOT_PASSWORD="${AUZIX_ROOT_PASSWORD:-root}"

log() {
  printf '[auzix-vagrant] %s\n' "$*"
}

if [[ ! -f "${PROFILE_PATH}" ]]; then
  echo "Package profile not found at ${PROFILE_PATH}" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

log "Updating apt metadata"
apt-get update

base_packages=(
  sudo
  locales
  dbus
  rsync
)

installable_packages=()
while IFS= read -r pkg; do
  [[ -z "${pkg}" || "${pkg}" == \#* ]] && continue
  if apt-cache show "${pkg}" >/dev/null 2>&1; then
    installable_packages+=("${pkg}")
  else
    log "Skipping unavailable package: ${pkg}"
  fi
done < "${PROFILE_PATH}"

log "Installing base and profile packages"
apt-get install -y "${base_packages[@]}" "${installable_packages[@]}"

log "Creating Auzix directory skeleton"
mkdir -p \
  /system/c \
  /system/libs \
  /system/s \
  /system/devices \
  /system/prefs \
  /system/apps \
  /system/docs \
  /ram \
  /work/home \
  /work/state \
  /work/log \
  /work/cache \
  /work/env \
  /work/root

mkdir -p /ram/tmp /ram/env
chmod 1777 /ram/tmp

if [[ ! -L /home ]]; then
  rm -rf /home
  ln -s /work/home /home
fi

if [[ ! -L /tmp ]]; then
  rm -rf /tmp
  ln -s /ram/tmp /tmp
fi

cat > /etc/profile.d/auzix-env.sh <<'EOF'
export AUZIX_SYSTEM=/system
export AUZIX_WORK=/work
export AUZIX_RAM=/ram
export PATH=/system/c:${PATH}
export LD_LIBRARY_PATH=/system/libs${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
export TMPDIR=/ram/tmp
export XDG_CACHE_HOME=${HOME}/.cache
export XDG_CONFIG_HOME=${HOME}/.config
export XDG_DATA_HOME=${HOME}/.local/share
EOF

cat > /system/c/auzix-report <<'EOF'
#!/bin/sh
echo "Auzix path report"
echo "================="
printf 'PATH=%s\n' "$PATH"
printf 'LD_LIBRARY_PATH=%s\n' "${LD_LIBRARY_PATH:-}"
printf 'HOME=%s\n' "$HOME"
printf 'TMPDIR=%s\n' "${TMPDIR:-}"
mount | egrep ' on /(work|ram) '
EOF
chmod +x /system/c/auzix-report

cat > /system/c/start-gui <<'EOF'
#!/bin/sh
exec systemctl isolate graphical.target
EOF
chmod +x /system/c/start-gui

log "Ensuring auzi user exists"
if ! id -u "${USERNAME}" >/dev/null 2>&1; then
  useradd -m -s /bin/bash -G sudo "${USERNAME}"
fi

echo "root:${ROOT_PASSWORD}" | chpasswd
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

mkdir -p "/work/home/${USERNAME}"
chown -R "${USERNAME}:${USERNAME}" "/work/home/${USERNAME}"

if [[ -d /var/log ]]; then
  mkdir -p /work/log
fi

log "Setting locale"
echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

log "Setting default target to multi-user"
systemctl set-default multi-user.target

log "Provisioning complete"
