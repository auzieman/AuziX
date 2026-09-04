#!/usr/bin/env bash
set -euo pipefail

[[ "$(hostname -s)" == "r730-ai-01" || "$(hostname -s)" == "lab-ai-worker" ]] || {
  echo "refusing local build: run this script on R730" >&2
  exit 2
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_RUN="${AUZIX_SOURCE_RUN:-20260830-r17}"
RUN_ID="${AUZIX_PRE_HDD_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
SOURCE_WORK="/var/lib/auzix-build/pre-hdd-apk/${SOURCE_RUN}"
WORK="/var/lib/auzix-build/pre-hdd-apk/${RUN_ID}"
IMAGE="${AUZIX_PRE_HDD_IMAGE:-auzix/validation:pre-hdd-apk-${RUN_ID}}"

test -s "$SOURCE_WORK/repository/x86_64/APKINDEX.tar.gz"
test -s "$SOURCE_WORK/trust/ca.crt"
test -s "$SOURCE_WORK/trust/repository.rsa.pub"
test "$(find "$SOURCE_WORK/bootstrap" -type f -name '*.apk' | wc -l)" -eq 3
[[ ! -e "$WORK" ]] || {
  echo "immutable run directory already exists: $WORK" >&2
  exit 1
}

mkdir -p "$WORK/build-context/docker/release/pre-hdd" \
  "$WORK/build-context/docker/release/common" "$WORK/receipts"
cp -a "$ROOT_DIR/auzix" "$WORK/build-context/"
cp -a "$ROOT_DIR/docker/release/pre-hdd/groups" \
  "$WORK/build-context/docker/release/pre-hdd/"
cp "$ROOT_DIR/docker/release/pre-hdd/install-groups.sh" \
  "$WORK/build-context/docker/release/pre-hdd/"
cp "$ROOT_DIR/docker/release/pre-hdd/run" \
  "$WORK/build-context/docker/release/pre-hdd/"
cp "$ROOT_DIR/docker/release/common/runtime-entrypoint.sh" \
  "$WORK/build-context/docker/release/common/"
cp "$ROOT_DIR/scripts/validate-auzix-pre-hdd-root.sh" \
  "$WORK/build-context/scripts-validate"
cp "$ROOT_DIR/docker/release/pre-hdd/Dockerfile" "$WORK/build-context/Dockerfile"
sed -i \
  's#COPY scripts/validate-auzix-pre-hdd-root.sh /Work/validate-root#COPY scripts-validate /Work/validate-root#' \
  "$WORK/build-context/Dockerfile"

test "$(docker inspect --format '{{.State.Health.Status}}' auzix-one-nginx)" = healthy
curl --fail --silent --show-error \
  --cacert "$SOURCE_WORK/trust/ca.crt" \
  --resolve auzix-repo.test:8443:127.0.0.1 \
  https://auzix-repo.test:8443/x86_64/APKINDEX.tar.gz \
  -o "$WORK/receipts/APKINDEX.tar.gz"

docker build --pull=false --network host \
  --add-host auzix-repo.test:127.0.0.1 \
  --build-context "auzix_bootstrap=$SOURCE_WORK/bootstrap" \
  --build-context "auzix_repository_trust=$SOURCE_WORK/trust" \
  --build-arg AUZIX_APK_REPOSITORY=https://auzix-repo.test:8443 \
  -f "$WORK/build-context/Dockerfile" -t "$IMAGE" "$WORK/build-context"

docker run --rm "$IMAGE" /Programs/BusyBox/current/Commands/busybox sh -ec '
  test -s /System/State/apk/db/installed
  /Programs/OpensshServer/current/Commands/sshd -t
  echo pre-hdd-https-apk-ok
'
docker image inspect --format '{{.Id}} {{.Size}}' "$IMAGE" |
  awk -v i="$IMAGE" -v r="$RUN_ID" -v s="$SOURCE_RUN" \
    '{printf "format=auzix-container-receipt-v2\nname=pre-hdd\nimage=%s\nimage_id=%s\nsize=%s\nrun_id=%s\nrepository_run=%s\nassembly=apk\nrepository_transport=https\nrepository_signature=verified\nstatus=pass\n",i,$1,$2,r,s}' \
    >"$WORK/receipts/pre-hdd.receipt"

echo "pre-hdd-resume: PASS run=$RUN_ID repository_run=$SOURCE_RUN image=$IMAGE"
