#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT_INPUT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
mkdir -p "${AUZIX_ROOT_INPUT}"
AUZIX_ROOT="$(cd "${AUZIX_ROOT_INPUT}" && pwd)"

VERSION="${AUZIX_FLATPAK_RUNTIME_SUPPORT_VERSION:-0.1.0}"
PROGRAM="${AUZIX_ROOT}/Programs/FlatpakRuntimeSupport/${VERSION}"
PACKAGE_DB="${AUZIX_ROOT}/System/PackageDB"

mkdir -p "${PROGRAM}/Commands" "${PACKAGE_DB}"
rm -f "${PACKAGE_DB}"/FlatpakRuntimeSupport-*.auzix.json

cat >"${PROGRAM}/Commands/repair-var-alias" <<'EOF'
#!/Programs/BusyBox/current/Commands/busybox sh
set -eu

BB="/Programs/BusyBox/current/Commands/busybox"
STATE="/System/State"

[ -d "${STATE}" ] || {
  echo "FlatpakRuntimeSupport: missing ${STATE}" >&2
  exit 1
}

if [ -L /var ]; then
  target="$("${BB}" readlink /var || true)"
  if [ "${target}" = "${STATE}" ]; then
    "${BB}" rm /var
    "${BB}" mkdir -p /var
  else
    echo "FlatpakRuntimeSupport: refusing to replace unexpected /var symlink -> ${target}" >&2
    exit 1
  fi
elif [ -e /var ] && [ ! -d /var ]; then
  echo "FlatpakRuntimeSupport: refusing to replace non-directory /var" >&2
  exit 1
else
  "${BB}" mkdir -p /var
fi

"${BB}" chmod 0755 /var

for name in cache lib lock log run tmp packages flatpak ostree containers dbus acpid display install agent ssh gnupg; do
  if [ -e "${STATE}/${name}" ] || [ -L "${STATE}/${name}" ]; then
    "${BB}" ln -sfn "${STATE}/${name}" "/var/${name}"
  fi
done

"${BB}" mkdir -p "${STATE}/tmp" "${STATE}/lib" "${STATE}/cache" "${STATE}/log" "${STATE}/run"
for name in tmp lib cache log run; do
  "${BB}" ln -sfn "${STATE}/${name}" "/var/${name}"
done

"${BB}" ln -sfn "${STATE}/flatpak" "${STATE}/lib/flatpak"

echo "FlatpakRuntimeSupport: /var is a real alias directory for ${STATE}"
EOF
chmod 0755 "${PROGRAM}/Commands/repair-var-alias"
ln -sfn "/Programs/FlatpakRuntimeSupport/${VERSION}" \
  "${AUZIX_ROOT}/Programs/FlatpakRuntimeSupport/current"

cat >"${PACKAGE_DB}/FlatpakRuntimeSupport-${VERSION}.auzix.json" <<EOF
{
  "name": "FlatpakRuntimeSupport",
  "version": "${VERSION}",
  "kind": "runtime-support",
  "migration_stage": "flatpak-bwrap-root-alias-support",
  "description": "Runtime support for Flatpak/Bubblewrap on AUZiX, including a real /var alias directory that maps children into /System/State.",
  "depends": ["BusyBox", "Flatpak"],
  "prefix": "/Programs/FlatpakRuntimeSupport/${VERSION}",
  "commands": [
    "/Programs/FlatpakRuntimeSupport/${VERSION}/Commands/repair-var-alias"
  ],
  "hooks": {
    "post_install": "/Programs/FlatpakRuntimeSupport/${VERSION}/Commands/repair-var-alias"
  },
  "paths": {
    "current": "/Programs/FlatpakRuntimeSupport/current"
  },
  "compatibility_exports": [],
  "validation": {
    "smoke_commands": [
      "test -d /var",
      "test ! -L /var",
      "test -L /var/lib",
      "test -L /var/lib/flatpak",
      "/Programs/Micro/current/Commands/micro --version"
    ]
  },
  "notes": "AUZiX still owns state under /System/State. /var is not an authority root; it is a compatibility alias directory because Bubblewrap refuses a top-level /var symlink during Flatpak app execution. /var/lib/flatpak aliases /System/State/flatpak for Flatpak apps that request the conventional system installation path."
}
EOF

printf '[flatpak-runtime-support] staged FlatpakRuntimeSupport %s\n' "${VERSION}"
