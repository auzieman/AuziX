#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/extended-ports/AuZiXRoot}"
SOURCE_PACKAGE=golang-github-containers-common
VERSION="$(dpkg-query -W -f='${Version}' "${SOURCE_PACKAGE}")"
PROGRAM="${AUZIX_ROOT}/Programs/ContainersCommon/${VERSION}"
SETTINGS="${AUZIX_ROOT}/System/Settings/containers"
RECEIPT="${AUZIX_ROOT}/System/PackageDB/ContainersCommon-${VERSION}.auzix.json"

mkdir -p \
  "${PROGRAM}/Resources" \
  "${SETTINGS}/registries.conf.d" \
  "${SETTINGS}/rootless/auzix" \
  "${AUZIX_ROOT}/System/PackageDB"

install -m 0644 /usr/share/containers/containers.conf \
  "${PROGRAM}/Resources/containers.conf"
install -m 0644 /usr/share/containers/seccomp.json \
  "${PROGRAM}/Resources/seccomp.json"
install -m 0644 /etc/containers/policy.json \
  "${PROGRAM}/Resources/policy.json"
install -m 0644 /etc/containers/registries.conf \
  "${PROGRAM}/Resources/registries.conf"
install -m 0644 /etc/containers/registries.conf.d/shortnames.conf \
  "${PROGRAM}/Resources/shortnames.conf"

for file in seccomp.json policy.json registries.conf; do
  install -m 0644 "${PROGRAM}/Resources/${file}" "${SETTINGS}/${file}"
done
install -m 0644 "${PROGRAM}/Resources/shortnames.conf" \
  "${SETTINGS}/registries.conf.d/shortnames.conf"

cat >"${SETTINGS}/containers.conf" <<'EOF'
[containers]
default_sysctls = ["net.ipv4.ping_group_range=0 0"]
seccomp_profile = "/System/Settings/containers/seccomp.json"

[engine]
conmon_path = ["/Programs/Conmon/current/Commands/conmon"]
helper_binaries_dir = [
  "/Programs/Netavark/current/Commands",
  "/Programs/AardvarkDNS/current/Commands"
]
runtime = "crun"
events_logger = "file"
events_logfile_path = "/System/State/containers/events/events.log"
volume_path = "/Work/Containers/volumes"

[engine.runtimes]
crun = ["/Programs/Crun/current/Commands/crun"]

[network]
network_backend = "netavark"
network_config_dir = "/System/Settings/containers/networks"
EOF

cat >"${SETTINGS}/storage.conf" <<'EOF'
[storage]
driver = "overlay"
runroot = "/System/State/containers/runroot"
graphroot = "/Work/Containers/storage"

[storage.options.overlay]
mountopt = "nodev"
EOF

cat >"${SETTINGS}/rootless/auzix/containers.conf" <<'EOF'
[containers]
default_sysctls = ["net.ipv4.ping_group_range=0 0"]
seccomp_profile = "/System/Settings/containers/seccomp.json"

[engine]
conmon_path = ["/Programs/Conmon/current/Commands/conmon"]
helper_binaries_dir = [
  "/Programs/Netavark/current/Commands",
  "/Programs/AardvarkDNS/current/Commands"
]
runtime = "crun"
events_logger = "file"
events_logfile_path = "/Users/auzix/.local/state/containers/events/events.log"
volume_path = "/Users/auzix/.local/share/containers/volumes"

[engine.runtimes]
crun = ["/Programs/Crun/current/Commands/crun"]

[network]
network_backend = "netavark"
network_config_dir = "/Users/auzix/.local/state/containers/networks"
EOF

cat >"${SETTINGS}/rootless/auzix/storage.conf" <<'EOF'
[storage]
driver = "overlay"
runroot = "/Users/auzix/.local/state/containers/runroot"
graphroot = "/Users/auzix/.local/share/containers/storage"

[storage.options.overlay]
mountopt = "nodev"
EOF

ln -sfn "/Programs/ContainersCommon/${VERSION}" \
  "${AUZIX_ROOT}/Programs/ContainersCommon/current"

jq -n \
  --arg version "${VERSION}" \
  '{
    name: "ContainersCommon",
    version: $version,
    kind: "system",
    migration_stage: "first-pass-debian-repack",
    description: "Shared Podman container configuration, registry policy, and seccomp defaults.",
    prefix: ("/Programs/ContainersCommon/" + $version),
    paths: {
      current: "/Programs/ContainersCommon/current",
      settings: "/System/Settings/containers",
      resources: ("/Programs/ContainersCommon/" + $version + "/Resources")
    },
    depends: [],
    source: {
      type: "debian-binary",
      suite: "trixie",
      package: "golang-github-containers-common",
      graduation: "upstream-source"
    },
    validation: {
      files: [
        "/System/Settings/containers/containers.conf",
        "/System/Settings/containers/storage.conf",
        "/System/Settings/containers/rootless/auzix/containers.conf",
        "/System/Settings/containers/rootless/auzix/storage.conf",
        "/System/Settings/containers/seccomp.json",
        "/System/Settings/containers/policy.json",
        "/System/Settings/containers/registries.conf"
      ]
    }
  }' >"${RECEIPT}"

for file in containers.conf seccomp.json policy.json registries.conf; do
  test -s "${SETTINGS}/${file}"
done

printf '[containers-common] built %s\n' "${VERSION}"
