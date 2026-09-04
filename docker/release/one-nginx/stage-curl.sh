#!/usr/bin/env bash
# Validation-era curl payload for one-nginx. Temporary: drop from small
# images once the ladder is stable. Uses /Libraries/ld-linux like nginx,
# not the older /System/Libraries/Runtime/glibc path.
set -euo pipefail

AUZIX_ROOT="${1:?usage: stage-auzix-curl-validation.sh STAGING_ROOT}"
CURL_BIN="${2:-/usr/bin/curl}"
[[ -x "$CURL_BIN" ]] || { echo "curl binary missing: $CURL_BIN" >&2; exit 1; }

version="$(
  {
    dpkg-query -W -f='${Version}\n' curl 2>/dev/null || true
    "$CURL_BIN" --version 2>/dev/null | awk '{print $2; exit}'
  } | awk 'NF {print; exit}'
)"
version="${version:-validation}"
program="$AUZIX_ROOT/Programs/Curl/$version"
mkdir -p "$program/Commands" "$program/Libraries" \
  "$AUZIX_ROOT/System/Compatibility/bin" "$AUZIX_ROOT/System/PackageDB"

install -D -m 0755 "$CURL_BIN" "$program/Commands/curl.real"

if command -v ldd >/dev/null 2>&1; then
  ldd "$CURL_BIN" 2>/dev/null |
    awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i }' |
    sort -u |
    while IFS= read -r dep; do
      [[ -f "$dep" ]] || continue
      install -D -m 0755 "$dep" "$program/Libraries/$(basename "$dep")"
    done
fi

cat >"$program/Commands/curl" <<'EOF'
#!/Programs/BusyBox/current/Commands/busybox sh
set -eu
exec /Libraries/ld-linux-x86-64.so.2 \
  --library-path /Libraries:/Programs/Curl/current/Libraries \
  /Programs/Curl/current/Commands/curl.real "$@"
EOF
chmod 0755 "$program/Commands/curl"
ln -sfn "/Programs/Curl/$version" "$AUZIX_ROOT/Programs/Curl/current"
ln -sfn /Programs/Curl/current/Commands/curl \
  "$AUZIX_ROOT/System/Compatibility/bin/curl"

cat >"$AUZIX_ROOT/System/PackageDB/Curl-$version.json" <<EOF
{"name":"Curl","version":"$version","prefix":"/Programs/Curl/$version","commands":["/Programs/Curl/$version/Commands/curl"],"compatibility_exports":["/System/Compatibility/bin/curl"],"notes":"Validation-era curl for one-nginx. Drop from small images once the ladder is stable."}
EOF

test -x "$program/Commands/curl.real"
printf '%s\n' "$AUZIX_ROOT"
