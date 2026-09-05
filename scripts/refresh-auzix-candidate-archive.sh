#!/usr/bin/env bash
set -euo pipefail
[[ "$(hostname -s)" == r730-ai-01 || "$(hostname -s)" == lab-ai-worker ]]
source_root="$(cd "$(dirname "$0")/.." && pwd)"
work=${1:?candidate work directory}
name=${2:?canonical archive identity}
spool=${3:?corrected intake spool or native stage}
mode=${4:-archive}
[[ "$name" =~ ^[A-Za-z0-9]+$ ]]
repair="$work/repairs/$name"
test ! -e "$work/receipts/pre-hdd.receipt"
test ! -e "$repair"
mkdir -p "$repair/input/packages" "$repair/previous"
if [[ "$mode" == native ]]; then
  mkdir -p "$repair/output/x86_64"
  docker run --rm -v "$source_root/auzix:/workspace/auzix:ro" \
    -v "$source_root/packaging:/workspace/packaging:ro" \
    -v "$spool:/staging:ro" -v "$repair/output/x86_64:/packages" \
    "auzix/package-factory:pre-hdd-$(basename "$work")" emit-package "$name" /staging /packages
else
  [[ "$mode" == archive ]]
jq --arg name "$name" '.packages=[$name]' "$work/selected-repo/profile.json" >"$repair/profile.json"
jq -s --arg name "$name" '[.[] | select(.name == $name)] | if length == 1 then {format:"auzix-repo-v1",packages:.} else error("expected one corrected identity") end' \
  "$spool"/entries/*.json >"$repair/input/index.json"
archive=$(jq -r '.packages[0].package' "$repair/input/index.json")
jq --slurpfile corrected "$repair/input/index.json" --arg name "$name" \
  '.packages = ([.packages[] | select(.name != $name)] + $corrected[0].packages)' \
  "$work/selected-repo/index.json" >"$repair/input/with-dependency-identities.json"
mv "$repair/input/with-dependency-identities.json" "$repair/input/index.json"
[[ "$archive" == "$(basename "$archive")" ]]
cp "$spool/packages/$archive" "$repair/input/packages/"
docker run --rm -v "$source_root/auzix:/workspace/auzix:ro" \
  -v "$source_root/packaging:/workspace/packaging:ro" \
  -v "$repair:/repair" -v "$work/apk-tool/apk:/tools/apk:ro" \
  "auzix/package-factory:pre-hdd-$(basename "$work")" \
  convert-archive-profile /repair/input /repair/profile.json /repair/output --apk-command /tools/apk
jq -e '.status == "passed" and (.packages | length) == 1' "$repair/output/conversion-proof.json" >/dev/null
fi
apk_file=$(find "$repair/output/x86_64" -name '*.apk' -type f)
test "$(printf '%s\n' "$apk_file" | wc -l)" -eq 1
filename=$(basename "$apk_file")
# Keep the pinned donor version; retain the previous package and signed index.
test -f "$work/repository/x86_64/$filename"
cp -a "$work/repository/x86_64/$filename" "$work/repository/x86_64/APKINDEX.tar.gz" "$repair/previous/"
cp "$apk_file" "$work/repository/x86_64/$filename"
docker run --rm -v "$work:/work" alpine:3.22 sh -ec '
  apk add --no-cache abuild >/dev/null
  cd /work/repository/x86_64
  apk index --allow-untrusted -o APKINDEX.tar.gz ./*.apk
  abuild-sign -k /work/keys/repository.rsa APKINDEX.tar.gz
'
sha256sum "$work/repository/x86_64/$filename" "$work/repository/x86_64/APKINDEX.tar.gz" >"$repair/SHA256SUMS"
printf 'status=refreshed\npackage=%s\nsource_spool=%s\n' "$name" "$spool" >"$repair/receipt"
