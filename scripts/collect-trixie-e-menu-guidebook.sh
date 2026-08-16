#!/usr/bin/env bash
set -euo pipefail

# Read-only guidebook collector for reproducing Trixie's desktop/E menu
# semantics in AUZiX package lifecycle metadata.
#
# Laptop-safe default: use the 192.168.1.x LAN address for vmid132.
# If this is run from ns1/BKC/lab-side, override TRIXIE_HOST=auzieman@10.20.0.117.

TRIXIE_HOST="${TRIXIE_HOST:-auzieman@192.168.1.169}"
OUT_DIR="${OUT_DIR:-out/vmid132-startup-crawl/e-menu-guidebook}"
mkdir -p "${OUT_DIR}"

ssh_opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

ssh "${ssh_opts[@]}" "${TRIXIE_HOST}" 'set -e
echo "# identity"
hostname
date -u
id

echo
echo "# xdg/menu/env packages"
dpkg-query -W -f="${binary:Package}\t${Version}\t${Status}\n" \
  enlightenment enlightenment-data libefreet1a libefreet-bin libelementary1 \
  desktop-file-utils shared-mime-info hicolor-icon-theme adwaita-icon-theme \
  glib2.0-bin xdg-user-dirs menu-xdg dbus dbus-user-session lightdm \
  lightdm-gtk-greeter x11-common 2>/dev/null || true

echo
echo "# important directories"
for p in \
  /etc/xdg \
  /etc/xdg/menus \
  /etc/X11/Xsession.d \
  /usr/share/applications \
  /usr/share/desktop-directories \
  /usr/share/mime \
  /usr/share/icons \
  /usr/share/glib-2.0/schemas \
  /usr/share/enlightenment \
  /usr/lib/*/enlightenment/modules \
  /usr/share/dbus-1 \
  /usr/share/polkit-1; do
  for q in $p; do [ -e "$q" ] && stat -c "%A %U:%G %n" "$q"; done
done
' >"${OUT_DIR}/summary.txt"

ssh "${ssh_opts[@]}" "${TRIXIE_HOST}" 'set -e
{
  find /etc/xdg/menus /usr/share/applications /usr/share/desktop-directories \
    /usr/share/dbus-1 /usr/share/polkit-1 \
    -maxdepth 3 -type f 2>/dev/null
  find /usr/share/glib-2.0/schemas \
    -maxdepth 1 -type f \( -name "*.gschema.xml" -o -name "gschemas.compiled" \) 2>/dev/null
  for f in \
    /usr/share/applications/mimeinfo.cache \
    /usr/share/mime/mime.cache \
    /usr/share/icons/hicolor/icon-theme.cache; do
    [ -e "$f" ] && echo "$f"
  done
} |
sort -u |
while IFS= read -r f; do
  owner="$(dpkg-query -S "$f" 2>/dev/null | sed -n "1s/: .*//p" || true)"
  printf "%s\t%s\n" "${owner:-UNOWNED}" "$f"
done
' >"${OUT_DIR}/owned-desktop-surface.tsv"

ssh "${ssh_opts[@]}" "${TRIXIE_HOST}" 'set -e
find /usr/share/applications -maxdepth 1 -type f -name "*.desktop" 2>/dev/null |
sort |
while IFS= read -r f; do
  owner="$(dpkg-query -S "$f" 2>/dev/null | sed -n "1s/: .*//p" || true)"
  name="$(awk -F= "/^Name=/ {print \$2; exit}" "$f" 2>/dev/null || true)"
  exec_line="$(awk -F= "/^Exec=/ {print \$2; exit}" "$f" 2>/dev/null || true)"
  categories="$(awk -F= "/^Categories=/ {print \$2; exit}" "$f" 2>/dev/null || true)"
  nodisplay="$(awk -F= "/^NoDisplay=/ {print \$2; exit}" "$f" 2>/dev/null || true)"
  printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${owner:-UNOWNED}" "$f" "$name" "$exec_line" "$categories" "$nodisplay"
done
' >"${OUT_DIR}/desktop-entries.tsv"

ssh "${ssh_opts[@]}" "${TRIXIE_HOST}" 'set -e
for f in \
  /etc/X11/Xsession \
  /etc/X11/Xsession.options \
  /etc/X11/Xsession.d/20dbus_xdg-runtime \
  /etc/X11/Xsession.d/35x11-common_xhost-local \
  /etc/X11/Xsession.d/50x11-common_determine-startup \
  /etc/X11/Xsession.d/75dbus_dbus-launch \
  /etc/X11/Xsession.d/95dbus_update-activation-env; do
  [ -f "$f" ] || continue
  echo "===== $f ====="
  sed -n "1,220p" "$f"
done
' >"${OUT_DIR}/xsession-chain.txt"

ssh "${ssh_opts[@]}" "${TRIXIE_HOST}" 'set -e
for pkg in desktop-file-utils shared-mime-info glib2.0-bin hicolor-icon-theme adwaita-icon-theme enlightenment libefreet-bin lightdm lightdm-gtk-greeter dbus dbus-user-session; do
  echo "===== $pkg ====="
  for s in postinst triggers postrm prerm preinst conffiles; do
    f="/var/lib/dpkg/info/$pkg.$s"
    [ -f "$f" ] || continue
    echo "--- $f ---"
    sed -n "1,240p" "$f"
  done
done
' >"${OUT_DIR}/maintainer-menu-cache-hooks.txt"

cat >"${OUT_DIR}/README.md" <<EOF
# Trixie E/menu guidebook

Captured from: \`${TRIXIE_HOST}\`

Files:

- \`summary.txt\` — identity, package versions, important directory ownership.
- \`owned-desktop-surface.tsv\` — package owner to desktop/menu/cache/policy files.
- \`desktop-entries.tsv\` — package, path, Name, Exec, Categories, NoDisplay.
- \`xsession-chain.txt\` — Xsession environment chain relevant to E/LightDM.
- \`maintainer-menu-cache-hooks.txt\` — Debian maintainer scripts/triggers for menu/cache/session packages.

AUZiX use:

1. map owned files into AUZiX package receipts;
2. translate maintainer script actions into install-time lifecycle hooks;
3. regenerate desktop/mime/icon/schema/Efreet caches after package install;
4. publish E menu entries only when the AUZiX front-door command probe passes.
EOF

echo "wrote ${OUT_DIR}" >&2
