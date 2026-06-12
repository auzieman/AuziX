#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

REPO_DIR="${TMP_DIR}/repo"
PUBLISH_DIR="${TMP_DIR}/published"
mkdir -p "${REPO_DIR}/packages"
printf 'package-data\n' >"${REPO_DIR}/packages/Test-1.auzix.tar.gz"
sha="$(sha256sum "${REPO_DIR}/packages/Test-1.auzix.tar.gz" | awk '{print $1}')"
jq -n --arg sha "${sha}" '{
  format: "auzix-repo-v1",
  packages: [{
    name: "Test",
    version: "1",
    package: "Test-1.auzix.tar.gz",
    sha256: $sha,
    size: 13
  }]
}' >"${REPO_DIR}/index.json"

"${ROOT_DIR}/scripts/publish-auzix-package-repo.sh" "${REPO_DIR}" "${PUBLISH_DIR}"
jq -e '.format == "auzix-repo-v1" and (.packages | length == 1)' \
  "${PUBLISH_DIR}/index.json" >/dev/null
test -f "${PUBLISH_DIR}/packages/Test-1.auzix.tar.gz"

echo "AuziX package publish contract: PASS"
