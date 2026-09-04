#!/usr/bin/env bash
set -euo pipefail

[[ "$(hostname -s)" == "r730-ai-01" || "$(hostname -s)" == "lab-ai-worker" ]] || {
  echo "refusing local build: run this script on R730" >&2; exit 2;
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
[[ "$MODE" == run || "$MODE" == preflight ]] || {
  echo "usage: $0 [preflight|run]" >&2; exit 2;
}
RUN_ID="${AUZIX_PRE_HDD_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
WORK="${AUZIX_PRE_HDD_WORK:-/var/lib/auzix-build/pre-hdd-apk/${RUN_ID}}"
BOOTSTRAP_VOLUME="${AUZIX_BOOTSTRAP_VOLUME:-auzix-lifecycle-bootstrap-repo-20260829}"
PACKAGE_VOLUME="${AUZIX_PACKAGE_VOLUME:-auzix-workstation-layered-r18-20260830}"
DELTA_SPOOL="${AUZIX_DELTA_SPOOL:-/var/lib/auzix-build/factory-delta/pre-hdd-missing-r2/spool}"
DELTA_PROFILE="${AUZIX_DELTA_PROFILE:-${ROOT_DIR}/packaging/archive-profiles/pre-hdd-missing.json}"
REFERENCE_SQUASHFS="${AUZIX_REFERENCE_SQUASHFS:-/var/lib/auzix-build/pre-hdd-reference/20260831-known-good-small-moon-ca/auzix-root.squashfs}"
RETAINED_ALPHA_ARCHIVES="${AUZIX_RETAINED_ALPHA_ARCHIVES:-/var/lib/auzix-build/pre-hdd-apk/20260830-r46-source/artifacts/auzix/extended-repo/packages}"
ZERO_IMAGE="${AUZIX_ZERO_IMAGE:-auzix/service:zero-busybox-apk-${RUN_ID}}"
NGINX_IMAGE="${AUZIX_NGINX_IMAGE:-auzix/service:one-nginx-apk-repository-${RUN_ID}}"
PRE_HDD_IMAGE="${AUZIX_PRE_HDD_IMAGE:-auzix/validation:pre-hdd-apk-${RUN_ID}}"
VALIDATION_IMAGE="${AUZIX_VALIDATION_IMAGE:-auzix/validation:netinstall-${RUN_ID}}"
EFL_BUILDER_IMAGE="${AUZIX_EFL_BUILDER_IMAGE:-auzix/builder:lab}"

fail() { echo "pre-hdd-apk: $*" >&2; exit 1; }
for command_name in docker jq python3 tar sha256sum unsquashfs; do
  command -v "$command_name" >/dev/null 2>&1 || fail "missing command: $command_name"
done
for required_source in \
  docker/extended-builder/Dockerfile \
  docker/package-factory/Dockerfile \
  docker/release/zero-busybox/Dockerfile \
  docker/release/one-nginx/Dockerfile \
  docker/release/netinstall-validation/Dockerfile \
  docker/release/pre-hdd/Dockerfile \
  scripts/build-auzix-nginx-package.sh \
  scripts/build-auzix-command-suite-package.sh \
  scripts/build-auzix-pre-hdd-support-packages.sh \
  scripts/validate-auzix-pre-hdd-root.sh; do
  [[ -e "$ROOT_DIR/$required_source" ]] \
    || fail "required source is absent: $ROOT_DIR/$required_source"
done
docker volume inspect "$BOOTSTRAP_VOLUME" >/dev/null \
  || fail "bootstrap volume is absent: $BOOTSTRAP_VOLUME"
docker volume inspect "$PACKAGE_VOLUME" >/dev/null \
  || fail "package volume is absent: $PACKAGE_VOLUME"
docker image inspect "$EFL_BUILDER_IMAGE" >/dev/null \
  || fail "EFL builder image is absent: $EFL_BUILDER_IMAGE"
test -d "$DELTA_SPOOL/packages" || fail "delta package spool is absent: $DELTA_SPOOL/packages"
test -d "$DELTA_SPOOL/entries" || fail "delta entry spool is absent: $DELTA_SPOOL/entries"
test -s "$DELTA_PROFILE" || fail "delta profile is absent: $DELTA_PROFILE"
test -s "$REFERENCE_SQUASHFS" || fail "reference root is absent: $REFERENCE_SQUASHFS"
for retained_package in Podman Conmon Crun Netavark AardvarkDNS ContainersCommon E2fsprogs Dosfstools; do
  compgen -G "$RETAINED_ALPHA_ARCHIVES/${retained_package}-*.auzix.tar.gz" >/dev/null \
    || fail "retained alpha archive is absent: $retained_package"
done
if [[ "$MODE" == preflight ]]; then
  echo "pre-hdd-apk: PREFLIGHT PASS host=$(hostname -s) run=$RUN_ID"
  exit 0
fi
[[ ! -e "$WORK" ]] || fail "immutable run directory already exists: $WORK"
mkdir -p "$WORK"/{bootstrap,layer,delta-repo/packages,delta-repo/entries,delta-apks,apk-tool,nginx-build-root,nginx-stage,nginx-packages,support-stages,support-packages,retained-stages,retained-packages,reference-root,reference-stages,reference-packages,repository/x86_64,keys,tls,trust,receipts}
copy_volume() {
  docker run --rm -v "$1:/source:ro" -v "$2:/destination" alpine:3.22 \
    sh -ec 'cp -a /source/. /destination/'
}
copy_volume "$BOOTSTRAP_VOLUME" "$WORK/bootstrap"
copy_volume "$PACKAGE_VOLUME" "$WORK/layer"
test "$(find "$WORK/bootstrap" -type f -name '*.apk' | wc -l)" -eq 3
test -s "$WORK/layer/packages/layer-lock.json"
test -d "$DELTA_SPOOL/packages"
test -d "$DELTA_SPOOL/entries"
test -s "$DELTA_PROFILE"
test -s "$REFERENCE_SQUASHFS"
cp -a "$DELTA_SPOOL/packages"/. "$WORK/delta-repo/packages/"
cp -a "$DELTA_SPOOL/entries"/. "$WORK/delta-repo/entries/"
jq -s '{format:"auzix-repo-v1", packages:.}' \
  "$WORK"/delta-repo/entries/*.json >"$WORK/delta-repo/index.json"

# Reproduce the declared Nginx payload and emit it through the current factory.
docker build --pull=false -t "auzix/extended-builder:pre-hdd-${RUN_ID}" \
  -f "$ROOT_DIR/docker/extended-builder/Dockerfile" "$ROOT_DIR"
docker run --rm -v "$WORK/bootstrap:/bootstrap:ro" \
  -v "$WORK/layer/packages:/layer:ro" -v "$WORK/nginx-build-root:/target" \
  alpine:3.22 sh -ec '
    apk add --initdb --root /target --allow-untrusted --no-scripts \
      /bootstrap/*.apk \
      /layer/auzix-libgcc-s1-*.apk /layer/auzix-runtime-glibc-*.apk \
      /layer/gcc-14-base-*.apk /layer/libcrypt1-*.apk /layer/libssl3t64-*.apk
  '
docker run --rm -v "$ROOT_DIR:/workspace:ro" -v "$WORK/nginx-build-root:/staging" \
  "auzix/extended-builder:pre-hdd-${RUN_ID}" \
  /workspace/scripts/build-auzix-nginx-package.sh /staging
# BusyBox was a producer/validation dependency, not part of the Nginx payload.
for path in Programs/Nginx Services/Nginx System/Settings/Nginx System/State/Nginx System/Logs/Nginx Work/Nginx; do
  mkdir -p "$WORK/nginx-stage/$(dirname "$path")"
  cp -a "$WORK/nginx-build-root/$path" "$WORK/nginx-stage/$path"
done
mkdir -p "$WORK/nginx-stage/System/PackageDB"
cp -a "$WORK/nginx-build-root"/System/PackageDB/Nginx-*.json "$WORK/nginx-stage/System/PackageDB/"
docker build --pull=false -t "auzix/package-factory:pre-hdd-${RUN_ID}" \
  -f "$ROOT_DIR/docker/package-factory/Dockerfile" "$ROOT_DIR"

# Convert the corrected AUZiX archives through the same lifecycle-aware APK
# factory used by the existing workstation waves.  The bootstrap ApkTools
# binary is static and is used only to verify the emitted APK archives.
docker run --rm -v "$WORK/bootstrap:/bootstrap:ro" -v "$WORK/apk-tool:/output" \
  alpine:3.22 sh -ec '
    apk add --initdb --root /tool-root --allow-untrusted /bootstrap/*.apk >/dev/null
    cp /tool-root/Programs/ApkTools/current/Commands/apk /output/apk
    chmod 0755 /output/apk
  '
docker run --rm \
  -v "$WORK/delta-repo:/delta-repo:ro" \
  -v "$WORK/delta-apks:/delta-output" \
  -v "$WORK/apk-tool/apk:/tools/apk:ro" \
  -v "$DELTA_PROFILE:/delta-profile.json:ro" \
  "auzix/package-factory:pre-hdd-${RUN_ID}" \
  convert-archive-profile /delta-repo \
    /delta-profile.json \
    /delta-output/repository --apk-command /tools/apk
delta_package_count="$(jq '.packages | length' "$DELTA_PROFILE")"
test "$(find "$WORK/delta-apks/repository/x86_64" -type f -name '*.apk' | wc -l)" -eq "$delta_package_count"
test "$(jq -r '(.summary.passed // 0) + (.summary.static // 0)' "$WORK/delta-apks/repository/conversion-proof.json")" -eq "$delta_package_count"

docker run --rm -v "$WORK/nginx-stage:/staging:ro" -v "$WORK/nginx-packages:/packages" \
  "auzix/package-factory:pre-hdd-${RUN_ID}" emit-package Nginx /staging /packages
test "$(find "$WORK/nginx-packages" -type f -name '*.apk' | wc -l)" -eq 1

# Native validation and workstation policy packages are small package-owned
# payloads, not Debian archive conversions. Emit them through the same factory
# before composing the signed repository.
"$ROOT_DIR/scripts/build-auzix-pre-hdd-support-packages.sh" "$WORK/support-stages" >/dev/null
docker run --rm \
  -v "$ROOT_DIR:/workspace:ro" \
  -v "$WORK/support-stages/Sudo:/staging" \
  "$EFL_BUILDER_IMAGE" \
  /workspace/scripts/build-auzix-sudo-package.sh /staging
for package_stage in AUZiXDebugTools AUZiXPythonFrontDoors WorkstationUserPolicy Sudo; do
  package_name="$(basename "$package_stage")"
  docker run --rm \
    -v "$WORK/support-stages/$package_stage:/staging:ro" \
    -v "$WORK/support-packages:/packages" \
    "auzix/package-factory:pre-hdd-${RUN_ID}" \
    emit-package "$package_name" /staging /packages
done
test "$(find "$WORK/support-packages" -type f -name '*.apk' | wc -l)" -eq 4

# Re-emit only the receipt-proven alpha disk/container closure through the
# current factory. These are immutable AUZiX payloads previously validated on
# VM135; no donor rebuild or feature expansion occurs in this release lane.
for retained_package in Podman Conmon Crun Netavark AardvarkDNS ContainersCommon E2fsprogs Dosfstools; do
  archive="$(find "$RETAINED_ALPHA_ARCHIVES" -maxdepth 1 -type f \
    -name "${retained_package}-*.auzix.tar.gz" -print -quit)"
  mkdir -p "$WORK/retained-stages/$retained_package"
  tar --numeric-owner -xzf "$archive" -C "$WORK/retained-stages/$retained_package"
  docker run --rm \
    -v "$WORK/retained-stages/$retained_package:/staging:ro" \
    -v "$WORK/retained-packages:/packages" \
    "auzix/package-factory:pre-hdd-${RUN_ID}" \
    emit-package "$retained_package" /staging /packages
done
test "$(find "$WORK/retained-packages" -type f -name '*.apk' | wc -l)" -eq 8

# Preserve the proven VMID135/small-moon desktop contract as package-owned
# surfaces.  Do not import the old root wholesale: only its existing installer
# and AUZiX desktop asset packages cross this boundary.
unsquashfs -f -d "$WORK/reference-root" "$REFERENCE_SQUASHFS" \
  Programs/AuzixInstaller Programs/AuzixInstallerEfl Programs/DesktopAssets \
  System/PackageDB/AuzixInstaller-0.2.auzix.json \
  System/PackageDB/AuzixInstallerEfl-0.1.auzix.json \
  System/PackageDB/DesktopAssets-auzietek.auzix.json \
  System/Compatibility/usr/share/applications/auzix-installer.desktop \
  System/Compatibility/usr/share/elementary/themes \
  System/Compatibility/usr/share/enlightenment/data/backgrounds \
  System/Compatibility/usr/share/terminology/themes \
  System/Tools/auzix-installer System/Tools/auzix-installer-gui \
  System/Tools/auzix-package-setup System/Tools/launch-auzix-installer >/dev/null

for package_stage in DesktopAssets AuzixInstaller AuzixInstallerEfl AuzixPackageManagerEfl; do
  mkdir -p "$WORK/reference-stages/$package_stage/Programs" \
    "$WORK/reference-stages/$package_stage/System/PackageDB"
done
cp -a "$WORK/reference-root/Programs/DesktopAssets" \
  "$WORK/reference-stages/DesktopAssets/Programs/"
mkdir -p "$WORK/reference-stages/DesktopAssets/System/Compatibility/usr/share"
cp -a "$WORK/reference-root/System/Compatibility/usr/share/elementary" \
  "$WORK/reference-root/System/Compatibility/usr/share/enlightenment" \
  "$WORK/reference-root/System/Compatibility/usr/share/terminology" \
  "$WORK/reference-stages/DesktopAssets/System/Compatibility/usr/share/"
cp "$WORK/reference-root/System/PackageDB/DesktopAssets-auzietek.auzix.json" \
  "$WORK/reference-stages/DesktopAssets/System/PackageDB/"

cp -a "$WORK/reference-root/Programs/AuzixInstaller" \
  "$WORK/reference-stages/AuzixInstaller/Programs/"
mkdir -p "$WORK/reference-stages/AuzixInstaller/System/Tools" \
  "$WORK/reference-stages/AuzixInstaller/System/Compatibility/usr/share/applications"
cp -a "$WORK/reference-root/System/Tools/auzix-installer" \
  "$WORK/reference-root/System/Tools/auzix-installer-gui" \
  "$WORK/reference-root/System/Tools/auzix-package-setup" \
  "$WORK/reference-stages/AuzixInstaller/System/Tools/"
cp "$WORK/reference-root/System/Compatibility/usr/share/applications/auzix-installer.desktop" \
  "$WORK/reference-stages/AuzixInstaller/System/Compatibility/usr/share/applications/"
cp "$WORK/reference-root/System/PackageDB/AuzixInstaller-0.2.auzix.json" \
  "$WORK/reference-stages/AuzixInstaller/System/PackageDB/"

cp -a "$WORK/reference-root/Programs/AuzixInstallerEfl" \
  "$WORK/reference-stages/AuzixInstallerEfl/Programs/"
mkdir -p "$WORK/reference-stages/AuzixInstallerEfl/System/Tools"
cp -a "$WORK/reference-root/System/Tools/launch-auzix-installer" \
  "$WORK/reference-stages/AuzixInstallerEfl/System/Tools/"
cp "$WORK/reference-root/System/PackageDB/AuzixInstallerEfl-0.1.auzix.json" \
  "$WORK/reference-stages/AuzixInstallerEfl/System/PackageDB/"

# Rebuild the frontend from this checkout. The reference image supplies its
# proven package layout, never an authoritative stale installer executable.
docker run --rm \
  -v "$ROOT_DIR:/workspace:ro" \
  -v "$WORK/reference-stages/AuzixInstallerEfl:/staging" \
  "$EFL_BUILDER_IMAGE" sh -ec '
    gcc -D_GNU_SOURCE -O2 -Wall -Wextra -Werror \
      -o /tmp/auzix-installer-efl /workspace/installer/efl/auzix-installer-efl.c \
      $(pkg-config --cflags --libs elementary)
    AUZIX_EFL_INSTALLER_BINARY=/tmp/auzix-installer-efl \
      /workspace/scripts/build-auzix-installer-efl-package.sh /staging
  '

mkdir -p "$WORK/reference-stages/AuzixPackageManagerEfl/System"
docker run --rm \
  -v "$ROOT_DIR:/workspace:ro" \
  -v "$WORK/reference-stages/AuzixPackageManagerEfl:/staging" \
  "$EFL_BUILDER_IMAGE" sh -ec '
    gcc -D_GNU_SOURCE -O2 -Wall -Wextra -Werror \
      -o /tmp/auzix-package-manager-efl /workspace/installer/efl/auzix-package-manager-efl.c \
      $(pkg-config --cflags --libs elementary)
    AUZIX_EFL_PACKAGE_MANAGER_BINARY=/tmp/auzix-package-manager-efl \
      /workspace/scripts/build-auzix-package-manager-efl-package.sh /staging
  '

for package_stage in DesktopAssets AuzixInstaller AuzixInstallerEfl AuzixPackageManagerEfl; do
  docker run --rm \
    -v "$WORK/reference-stages/$package_stage:/staging:ro" \
    -v "$WORK/reference-packages:/packages" \
    "auzix/package-factory:pre-hdd-${RUN_ID}" \
    emit-package "$package_stage" /staging /packages
done
test "$(find "$WORK/reference-packages" -type f -name '*.apk' | wc -l)" -eq 4

cp -a "$WORK/bootstrap"/*.apk "$WORK/repository/x86_64/"
cp -a "$WORK/layer/packages"/*.apk "$WORK/repository/x86_64/"
cp -a "$WORK/delta-apks/repository/x86_64"/*.apk "$WORK/repository/x86_64/"
cp -a "$WORK/nginx-packages"/*.apk "$WORK/repository/x86_64/"
cp -a "$WORK/support-packages"/*.apk "$WORK/repository/x86_64/"
cp -a "$WORK/retained-packages"/*.apk "$WORK/repository/x86_64/"
cp -a "$WORK/reference-packages"/*.apk "$WORK/repository/x86_64/"

# Signing and TLS private keys are immutable run evidence, never source files.
docker run --rm -v "$WORK:/work" alpine:3.22 sh -ec '
  apk add --no-cache alpine-sdk openssl >/dev/null
  openssl genrsa -out /work/keys/repository.rsa 3072 >/dev/null 2>&1
  openssl rsa -in /work/keys/repository.rsa -pubout -out /work/keys/repository.rsa.pub >/dev/null 2>&1
  cd /work/repository/x86_64
  apk index --allow-untrusted -o APKINDEX.tar.gz ./*.apk
  abuild-sign -k /work/keys/repository.rsa APKINDEX.tar.gz
  openssl req -x509 -newkey rsa:3072 -nodes -days 7 -sha256 \
    -keyout /work/tls/server.key -out /work/tls/server.crt \
    -subj /CN=auzix-repo.test \
    -addext subjectAltName=DNS:auzix-repo.test,IP:127.0.0.1 >/dev/null 2>&1
  chmod 0600 /work/keys/repository.rsa /work/tls/server.key
  chmod 0644 /work/keys/repository.rsa.pub /work/tls/server.crt
'
cp "$WORK/tls/server.crt" "$WORK/trust/ca.crt"
cp "$WORK/keys/repository.rsa.pub" "$WORK/trust/repository.rsa.pub"
tar -xOzf "$WORK/repository/x86_64/APKINDEX.tar.gz" APKINDEX |
  awk -F: '$1 == "P" {print $2}' | sort -u >"$WORK/repository-packages.list"
cat "$ROOT_DIR"/docker/release/pre-hdd/groups/*.list |
  sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' |
  sort -u >"$WORK/packages.list"
test -s "$WORK/packages.list"
missing_packages="$(comm -23 "$WORK/packages.list" "$WORK/repository-packages.list")"
[[ -z "$missing_packages" ]] || fail "requested packages absent from signed repository: $missing_packages"

docker build --pull=false --build-context "auzix_bootstrap=$WORK/bootstrap" \
  -f "$ROOT_DIR/docker/release/zero-busybox/Dockerfile" -t "$ZERO_IMAGE" "$ROOT_DIR"
docker run --rm "$ZERO_IMAGE" /Programs/BusyBox/current/Commands/busybox sh -ec \
  'test -s /System/State/apk/db/installed; busybox true'

docker build --pull=false --build-arg "BASE_IMAGE=$ZERO_IMAGE" \
  --build-context "auzix_repository=$WORK/repository" \
  --build-context "auzix_repository_tls=$WORK/tls" \
  -f "$ROOT_DIR/docker/release/one-nginx/Dockerfile" -t "$NGINX_IMAGE" \
  "$ROOT_DIR/docker/release/one-nginx"
docker rm -f auzix-one-nginx >/dev/null 2>&1 || true
docker run -d --name auzix-one-nginx --restart unless-stopped \
  -p 127.0.0.1:8443:8443 "$NGINX_IMAGE" >/dev/null
for attempt in 1 2 3 4 5 6; do
  [[ "$(docker inspect --format '{{.State.Health.Status}}' auzix-one-nginx)" == healthy ]] && break
  sleep 5
done
[[ "$(docker inspect --format '{{.State.Health.Status}}' auzix-one-nginx)" == healthy ]] \
  || fail "one-nginx did not become healthy"
curl --fail --silent --show-error \
  --cacert "$WORK/trust/ca.crt" \
  --resolve auzix-repo.test:8443:127.0.0.1 \
  https://auzix-repo.test:8443/x86_64/APKINDEX.tar.gz \
  -o "$WORK/receipts/APKINDEX.tar.gz"
docker build --pull=false --network host \
  --add-host auzix-repo.test:127.0.0.1 \
  --build-arg "BASE_IMAGE=$ZERO_IMAGE" \
  --build-arg AUZIX_APK_REPOSITORY=https://auzix-repo.test:8443 \
  --build-context "auzix_repository_trust=$WORK/trust" \
  -f "$ROOT_DIR/docker/release/netinstall-validation/Dockerfile" \
  -t "$VALIDATION_IMAGE" "$ROOT_DIR"
docker run --rm "$VALIDATION_IMAGE" \
  /Programs/BusyBox/current/Commands/busybox sh /System/Validation/validate-netinstall

# Build context contains contracts only; package payload crosses HTTPS.
mkdir -p "$WORK/build-context/docker/release/pre-hdd" \
  "$WORK/build-context/docker/release/common"
cp -a "$ROOT_DIR/docker/release/pre-hdd/groups" "$WORK/build-context/docker/release/pre-hdd/"
cp "$ROOT_DIR/docker/release/pre-hdd/install-groups.sh" "$WORK/build-context/docker/release/pre-hdd/"
cp "$ROOT_DIR/docker/release/pre-hdd/run" "$WORK/build-context/docker/release/pre-hdd/"
cp "$ROOT_DIR/docker/release/common/runtime-entrypoint.sh" "$WORK/build-context/docker/release/common/"
cp -a "$ROOT_DIR/auzix" "$WORK/build-context/"
cp "$ROOT_DIR/scripts/validate-auzix-pre-hdd-root.sh" "$WORK/build-context/scripts-validate"
cp "$ROOT_DIR/docker/release/pre-hdd/Dockerfile" "$WORK/build-context/Dockerfile"
sed -i 's#COPY scripts/validate-auzix-pre-hdd-root.sh /Work/validate-root#COPY scripts-validate /Work/validate-root#' "$WORK/build-context/Dockerfile"
docker build --pull=false --network host --add-host auzix-repo.test:127.0.0.1 \
  --build-context "auzix_bootstrap=$WORK/bootstrap" \
  --build-context "auzix_repository_trust=$WORK/trust" \
  --build-arg AUZIX_APK_REPOSITORY=https://auzix-repo.test:8443 \
  -f "$WORK/build-context/Dockerfile" -t "$PRE_HDD_IMAGE" "$WORK/build-context"
docker run --rm "$PRE_HDD_IMAGE" /Programs/BusyBox/current/Commands/busybox sh -ec '
  test -s /System/State/apk/db/installed
  grep -qx replay=no-op /System/State/packages/pre-hdd-transaction.receipt
  /Programs/OpensshServer/current/Commands/sshd -t
  echo pre-hdd-https-apk-ok
'
for pair in "zero:$ZERO_IMAGE" "nginx:$NGINX_IMAGE" "netinstall:$VALIDATION_IMAGE" "pre-hdd:$PRE_HDD_IMAGE"; do
  name=${pair%%:*}; image=${pair#*:}
  docker image inspect --format '{{.Id}} {{.Size}}' "$image" |
    awk -v n="$name" -v i="$image" -v r="$RUN_ID" \
    '{printf "format=auzix-container-receipt-v2\nname=%s\nimage=%s\nimage_id=%s\nsize=%s\nrun_id=%s\nassembly=apk\nrepository_transport=https\nrepository_signature=verified\nstatus=pass\n",n,i,$1,$2,r}' \
    >"$WORK/receipts/$name.receipt"
done
echo "pre-hdd-apk: PASS run=$RUN_ID work=$WORK image=$PRE_HDD_IMAGE"
