#!/usr/bin/env bash
# Preserve the established host-terminology launcher as a package-owned asset.
set -euo pipefail
root=${1:?target root}
mkdir -p "$root/System/Tools"
cat >"$root/System/Tools/launch-auzix-terminal" <<'EOF'
#!/Programs/BusyBox/current/Commands/busybox sh
set -eu
if [ -r /System/Settings/auzix-paths.sh ]; then
  . /System/Settings/auzix-paths.sh
fi
export PATH="/Programs/Terminology/current/Commands:/Programs/XTerm/current/Commands:/System/Compatibility/bin:/System/Compatibility/usr/bin:/Programs/BusyBox/current/Commands:${PATH:-}"
export HOME="${HOME:-/Users/auzix}"
export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/System/Compatibility/usr/local/share:/System/Compatibility/usr/share:/Programs/Enlightenment/current/Resources/share:/Programs/EFL/current/Resources/share}"
export XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/System/Settings/xdg:/System/Compatibility/etc/xdg}"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-/Libraries:/System/Libraries:/System/Libraries/Runtime/glibc:/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64}"
export SSL_CERT_DIR="${SSL_CERT_DIR:-/System/Compatibility/etc/ssl/certs}"
export SSL_CERT_FILE="${SSL_CERT_FILE:-/System/Compatibility/etc/ssl/certs/ca-certificates.crt}"
export CURL_CA_BUNDLE="${CURL_CA_BUNDLE:-${SSL_CERT_FILE}}"
export TERMINFO_DIRS="${TERMINFO_DIRS:-/System/Compatibility/usr/share/terminfo:/System/Compatibility/lib/terminfo:/usr/share/terminfo:/lib/terminfo}"
export SHELL=/System/Compatibility/bin/sh
case "${TERM:-}" in ""|dumb|linux) export TERM=xterm-256color ;; esac
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export ELM_ACCEL="${ELM_ACCEL:-none}"
export ECORE_EVAS_ENGINE="${ECORE_EVAS_ENGINE:-software_x11}"
export ELM_ENGINE="${ELM_ENGINE:-software_x11}"
export E_COMP_ENGINE="${E_COMP_ENGINE:-sw}"
if command -v terminology >/dev/null 2>&1; then
  exec terminology -e "$SHELL" -i "$@"
fi
exec xterm -tn xterm-256color -T "AUZiX Terminal" -e "$SHELL" -i "$@"
EOF
chmod 0755 "$root/System/Tools/launch-auzix-terminal"
