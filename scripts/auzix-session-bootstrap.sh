#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="review"
LOCK=""

usage() {
  printf 'Usage: %s [--mode review|build] [--lock PATH]\n' "$0"
}

while (($#)); do
  case "$1" in
    --mode) MODE="${2:?missing mode}"; shift 2 ;;
    --lock) LOCK="${2:?missing lock path}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "${MODE}" in review|build) ;; *) printf 'Invalid mode: %s\n' "${MODE}" >&2; exit 2 ;; esac

cd "${ROOT_DIR}"
command -v git >/dev/null
command -v jq >/dev/null

POLICY="packages/session-bootstrap.policy.json"
jq -e '.format == "auzix-session-bootstrap-policy-v1"' "${POLICY}" >/dev/null

branch="$(git symbolic-ref --quiet --short HEAD || printf detached)"
commit="$(git rev-parse HEAD)"
dirty_count="$(git status --porcelain=v1 | wc -l | tr -d ' ')"

printf 'AUZiX session bootstrap\n'
printf '  mode: %s\n' "${MODE}"
printf '  root: %s\n' "${ROOT_DIR}"
printf '  branch: %s\n' "${branch}"
printf '  commit: %s\n' "${commit}"
printf '  dirty paths: %s\n' "${dirty_count}"
printf '  release lane: %s\n' "$(jq -r .release_lane "${POLICY}")"
printf '  research lane: %s\n' "$(jq -r .research_lane "${POLICY}")"
printf '  core glibc: %s (parallel providers forbidden)\n' "$(jq -r .core_provider.glibc "${POLICY}")"
printf '  canonical flow:\n'
jq -r '.canonical_flow[] | "    - " + .' "${POLICY}"

printf '  authority files:\n'
missing=0
while IFS= read -r path; do
  if [[ -s "${path}" ]]; then
    printf '    - present: %s\n' "${path}"
  else
    printf '    - MISSING: %s\n' "${path}"
    missing=1
  fi
done < <(jq -r '.authority_order[]' "${POLICY}")

if ((missing)); then
  printf 'STOP: AUZiX authority set is incomplete.\n' >&2
  exit 3
fi

if [[ "${MODE}" == review ]]; then
  if ((dirty_count)); then
    printf '  review warning: working tree is dirty; do not produce release assets from it.\n'
  fi
  exit 0
fi

if ((dirty_count)); then
  printf 'STOP: release build requires a clean committed working tree.\n' >&2
  exit 4
fi

if [[ -z "${LOCK}" || ! -s "${LOCK}" ]]; then
  printf 'STOP: --lock must name an existing build-tree.lock.json.\n' >&2
  exit 5
fi

jq -e '
  .format == "auzix-native-rebase-lock-v1" and
  (.status | test("^locked")) and
  (.git_tag | type == "string" and length > 0) and
  (.manifest_lock_sha256 | type == "string" and length == 64)
' "${LOCK}" >/dev/null || {
  printf 'STOP: invalid or incomplete AUZiX build lock.\n' >&2
  exit 6
}

lock_tag="$(jq -r .git_tag "${LOCK}")"
tag_commit="$(git rev-list -n 1 "refs/tags/${lock_tag}" 2>/dev/null || true)"
if [[ -z "${tag_commit}" || "${tag_commit}" != "${commit}" ]]; then
  printf 'STOP: HEAD is not the exact committed lock tag %s.\n' "${lock_tag}" >&2
  exit 7
fi

printf 'PASS: AUZiX release-build bootstrap is locked to %s at %s.\n' "${lock_tag}" "${commit}"
