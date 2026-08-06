#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
TARGET="${1:?usage: export-auzix-committed-source.sh [USER@HOST:]TARGET_DIRECTORY}"
COMMIT="$(git -C "${ROOT_DIR}" rev-parse HEAD)"

[[ -z "$(git -C "${ROOT_DIR}" status --porcelain)" ]] || {
  printf 'Refusing to export a dirty AuziX checkout.\n' >&2
  exit 1
}

if [[ "${TARGET}" == *:* ]]; then
  REMOTE="${TARGET%%:*}"
  REMOTE_PATH="${TARGET#*:}"
  ssh "${REMOTE}" mkdir -p "${REMOTE_PATH}"
else
  mkdir -p "${TARGET}"
fi
rsync -a --delete \
  --exclude='.git/' \
  --exclude='out/' \
  --exclude='artifacts/' \
  --exclude='downloads/' \
  "${ROOT_DIR}/" "${TARGET}/"
if [[ "${TARGET}" == *:* ]]; then
  printf '%s\n' "${COMMIT}" | ssh "${REMOTE}" "umask 022; tee '${REMOTE_PATH}/.auzix-source-commit' >/dev/null"
else
  printf '%s\n' "${COMMIT}" >"${TARGET}/.auzix-source-commit"
fi
printf 'exported_commit=%s target=%s\n' "${COMMIT}" "${TARGET}"
