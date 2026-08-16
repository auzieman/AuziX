#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="${AUZIX_PUBLIC_REPO_DIR:-${1:-${ROOT_DIR}/artifacts/auzix/repo}}"
ISO_DIR="${AUZIX_PUBLIC_ISO_DIR:-${2:-${ROOT_DIR}/artifacts/auzix}}"
RECEIPT_DIR="${AUZIX_PUBLIC_RECEIPT_DIR:-${3:-${ROOT_DIR}/out}}"
SHELF_DIR="${AUZIX_PUBLIC_SHELF_DIR:-${4:-${ROOT_DIR}/public/auzix}}"
MAX_ISOS="${AUZIX_PUBLIC_MAX_ISOS:-3}"
MAX_RECEIPTS="${AUZIX_PUBLIC_MAX_RECEIPTS:-80}"

log() {
  printf '[auzix-public-shelf] %s\n' "$*" >&2
}

require() {
  command -v "$1" >/dev/null 2>&1 || {
    log "missing command: $1"
    exit 1
  }
}

require date
require find
require jq
require rsync
require sha256sum

[[ -f "${REPO_DIR}/index.json" ]] || {
  log "missing AUZiX repo index: ${REPO_DIR}/index.json"
  exit 1
}

jq -e '.format == "auzix-repo-v1" and (.packages | type == "array")' \
  "${REPO_DIR}/index.json" >/dev/null

mkdir -p "${SHELF_DIR}/repo" "${SHELF_DIR}/isos" "${SHELF_DIR}/receipts"
rsync -a "${REPO_DIR}/" "${SHELF_DIR}/repo/"

iso_count=0
while IFS= read -r iso_path; do
  iso_name="$(basename "${iso_path}")"
  case "${iso_name}" in
    *public*|*beta*|*live-demo*|*themefix*|*installer*)
      install -m 0644 "${iso_path}" "${SHELF_DIR}/isos/${iso_name}"
      if [[ -f "${iso_path}.sha256" ]]; then
        install -m 0644 "${iso_path}.sha256" "${SHELF_DIR}/isos/${iso_name}.sha256"
      else
        sha256sum "${SHELF_DIR}/isos/${iso_name}" >"${SHELF_DIR}/isos/${iso_name}.sha256"
      fi
      iso_count=$((iso_count + 1))
      ;;
  esac
  [[ "${iso_count}" -ge "${MAX_ISOS}" ]] && break
done < <(find "${ISO_DIR}" -maxdepth 2 -type f -name '*.iso' -printf '%T@ %p\n' | sort -nr | awk '{sub(/^[^ ]+ /, ""); print}')

receipt_count=0
while IFS= read -r receipt_path; do
  receipt_name="$(basename "${receipt_path}")"
  install -m 0644 "${receipt_path}" "${SHELF_DIR}/receipts/${receipt_name}"
  receipt_count=$((receipt_count + 1))
  [[ "${receipt_count}" -ge "${MAX_RECEIPTS}" ]] && break
done < <(find "${RECEIPT_DIR}" -maxdepth 4 -type f \
  \( -name '*auzix*.json' -o -name '*auzix*.txt' -o -name '*auzix*.summary' -o -name '*repository-publish.report.json' \) \
  -printf '%T@ %p\n' | sort -nr | awk '{sub(/^[^ ]+ /, ""); print}')

package_count="$(jq '.packages | length' "${SHELF_DIR}/repo/index.json")"
build_commit="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
published_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

jq -n \
  --arg format "auzix-public-beta-shelf-v1" \
  --arg published_at "${published_at}" \
  --arg build_commit "${build_commit}" \
  --arg repo_path "repo/index.json" \
  --argjson package_count "${package_count}" \
  --argjson iso_count "${iso_count}" \
  '{
    format: $format,
    generated_at: $published_at,
    source_commit: $build_commit,
    repo_index: $repo_path,
    package_count: $package_count,
    iso_count: $iso_count,
    paths: {
      repo: "repo/",
      isos: "isos/",
      receipts: "receipts/"
    }
  }' >"${SHELF_DIR}/manifest.json"

cat >"${SHELF_DIR}/index.html.next" <<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>AUZiX Beta</title>
  <style>
    :root { color-scheme: dark; font-family: system-ui, sans-serif; background: #071019; color: #f3fbff; }
    body { margin: 0; min-height: 100vh; background: radial-gradient(circle at 20% 0%, #183a5b 0, transparent 38%), #071019; }
    main { max-width: 920px; margin: 0 auto; padding: 8vh 24px; }
    h1 { font-size: clamp(2.4rem, 7vw, 5.5rem); margin: 0 0 .25em; letter-spacing: .03em; }
    .tag { color: #7be7ff; text-transform: uppercase; letter-spacing: .22em; font-weight: 700; }
    .card { border: 1px solid #24506d; background: rgba(4, 12, 20, .72); border-radius: 18px; padding: 22px; margin: 20px 0; box-shadow: 0 20px 60px rgba(0,0,0,.35); }
    a { color: #88e8ff; }
    code { background: #0b2233; padding: .15em .35em; border-radius: 6px; }
    ul { line-height: 1.7; }
  </style>
</head>
<body>
  <main>
    <p class="tag">Auzietek Labs</p>
    <h1>AUZiX Beta</h1>
    <p>A small, stubbornly personal Linux-shaped operating system experiment:
    strict AUZiX paths, Enlightenment desktop, package factory, Podman proofs,
    and tiny containers that keep making people blink twice.</p>
    <section class="card">
      <h2>Downloads</h2>
      <ul>
        <li><a href="repo/index.json">Package repository index</a> (${package_count} packages)</li>
        <li><a href="isos/">ISO candidates</a> (${iso_count} staged)</li>
        <li><a href="receipts/">Build receipts and validation notes</a></li>
        <li><a href="manifest.json">Publication manifest</a></li>
      </ul>
    </section>
    <section class="card">
      <h2>Beta notes</h2>
      <p>This shelf is generated from lab-built artifacts after public-safety
      checks. Public ISOs must not include lab SSH keys, password hashes,
      private URLs, or internal BKC addresses.</p>
      <p>Generated <code>${published_at}</code> from AUZiX commit
      <code>${build_commit}</code>.</p>
    </section>
    <section class="card">
      <h2>Community</h2>
      <p>Start at <a href="https://auzietek.com/">Auzietek</a> or the
      <a href="https://linux-users.auzietek.com/blog">Linux Users field notes</a>.
      Community links are kept on the controlled Auzietek contact page so
      Discord invites and social links can rotate without rebuilding media.</p>
    </section>
  </main>
</body>
</html>
HTML
mv -f "${SHELF_DIR}/index.html.next" "${SHELF_DIR}/index.html"

log "staged public beta shelf at ${SHELF_DIR}"
log "packages=${package_count} isos=${iso_count} receipts=${receipt_count}"
