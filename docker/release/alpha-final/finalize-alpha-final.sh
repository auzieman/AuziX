#!/Programs/BusyBox/current/Commands/busybox sh
set -eu

bb=/Programs/BusyBox/current/Commands/busybox

$bb mkdir -p \
  /Libraries \
  /System/Compatibility/lib/x86_64-linux-gnu \
  /System/Compatibility/usr/lib/udev \
  /System/Settings/X11/xorg.conf.d \
  /System/Tools \
  /run/sshd

# Publish the current split EFL packages through AUZiX's runtime and
# compatibility views.  These are factory archives built from one Trixie
# generation; no older reference-image executable or library is imported.
find -L /Programs -path '*/current/RootFS/usr/lib/x86_64-linux-gnu/*.so*' \
  \( -type f -o -type l \) -print 2>/dev/null |
while IFS= read -r library; do
  ln -sfn "$library" "/Libraries/${library##*/}"
  ln -sfn "$library" "/System/Compatibility/lib/x86_64-linux-gnu/${library##*/}"
done

find /System/Compatibility/lib/x86_64-linux-gnu -maxdepth 1 \
  -type f -name 'libe*.so.1' -print |
while IFS= read -r library; do
  ln -sfn "$library" "/Libraries/${library##*/}"
done

# Publish the adjacent compatibility providers used by the proven E/EFL spine.
for library in \
  /System/Compatibility/lib/x86_64-linux-gnu/libbluetooth.so.3 \
  /System/Compatibility/lib/x86_64-linux-gnu/libeet.so.1 \
  /System/Compatibility/lib/x86_64-linux-gnu/libeeze.so.1 \
  /System/Compatibility/lib/x86_64-linux-gnu/libexif.so.12 \
  /System/Compatibility/lib/x86_64-linux-gnu/libgif.so.7 \
  /System/Compatibility/lib/x86_64-linux-gnu/libinput.so.10 \
  /System/Compatibility/lib/x86_64-linux-gnu/libmtdev.so.1 \
  /System/Compatibility/lib/x86_64-linux-gnu/libevdev.so.2 \
  /System/Compatibility/lib/x86_64-linux-gnu/libudev.so.1 \
  /System/Compatibility/lib/x86_64-linux-gnu/libwacom.so.9 \
  /System/Compatibility/lib/x86_64-linux-gnu/libgudev-1.0.so.0 \
  /System/Compatibility/lib/x86_64-linux-gnu/libpulse.so.0 \
  /System/Compatibility/lib/x86_64-linux-gnu/libunwind.so.8 \
  /System/Compatibility/lib/x86_64-linux-gnu/libunwind-x86_64.so.8 \
  /System/Compatibility/lib/x86_64-linux-gnu/libwayland-server.so.0 \
  /System/Compatibility/lib/x86_64-linux-gnu/libwebpdemux.so.2 \
  /System/Compatibility/lib/x86_64-linux-gnu/libXss.so.1 \
  /System/Compatibility/lib/x86_64-linux-gnu/libXtst.so.6 \
  /System/Compatibility/lib/x86_64-linux-gnu/libxkbcommon-x11.so.0 \
  /System/Compatibility/lib/x86_64-linux-gnu/libxkbcommon.so.0 \
  /System/Compatibility/lib/x86_64-linux-gnu/libxcb-xkb.so.1; do
  test -s "$library" || {
    echo "alpha-final: missing compatibility provider: $library" >&2
    exit 1
  }
  ln -sfn "$library" "/Libraries/${library##*/}"
done

libinput_conf="$($bb find /Programs/XserverXorgInputLibinput -type f \
  -name 40-libinput.conf -print -quit)"
test -s "$libinput_conf"
cp "$libinput_conf" /System/Settings/X11/xorg.conf.d/40-libinput.conf

udev_root="$($bb find -L /Programs/Udev -type d -path '*/RootFS/usr/lib/udev' -print -quit)"
test -n "$udev_root"
cp -a "$udev_root/." /System/Compatibility/usr/lib/udev/

ln -sfn /Programs/AuzixInstallerEfl/current/Commands/launch-auzix-installer \
  /System/Tools/launch-auzix-installer

# Terminology's package-owned desktop entry uses this front door.  Older APK
# emission waves retained the entry but omitted this non-RootFS package
# surface, so materialize the same launcher contract while those packages are
# replaced through the factory.
cat > /System/Tools/launch-auzix-terminal <<'EOF'
#!/Programs/BusyBox/current/Commands/busybox sh
set -eu

[ ! -r /System/Settings/auzix-runtime-env ] || . /System/Settings/auzix-runtime-env
[ ! -r /System/Settings/auzix-paths.sh ] || . /System/Settings/auzix-paths.sh

export HOME="${HOME:-/Users/auzix}"
export PATH="/Programs/Terminology/current/Commands:/Programs/XTerm/current/Commands:/System/Compatibility/bin:/System/Compatibility/usr/bin:/Programs/BusyBox/current/Commands:${PATH:-}"
export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/System/Compatibility/usr/local/share:/System/Compatibility/usr/share:/Programs/Enlightenment/current/Resources/share:/Programs/EFL/current/Resources/share}"
export XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/System/Settings/xdg:/System/Compatibility/etc/xdg}"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-/System/Libraries:/System/Libraries/Runtime/glibc:/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64}"
export TERMINFO_DIRS="${TERMINFO_DIRS:-/System/Compatibility/usr/share/terminfo:/System/Compatibility/lib/terminfo:/usr/share/terminfo:/lib/terminfo}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export ELM_ACCEL="${ELM_ACCEL:-none}"
export ECORE_EVAS_ENGINE="${ECORE_EVAS_ENGINE:-software_x11}"
export ELM_ENGINE="${ELM_ENGINE:-software_x11}"
export E_COMP_ENGINE="${E_COMP_ENGINE:-sw}"

if command -v terminology >/dev/null 2>&1; then
  exec terminology -e /System/Compatibility/bin/bash "$@"
fi
exec xterm -tn xterm-256color -T "AUZiX Terminal" -e /System/Compatibility/bin/bash "$@"
EOF
chmod 0755 /System/Tools/launch-auzix-terminal

# Fresh profiles require Efreet before E builds its first application menu.
sed -i 's/AUZIX_PRESTART_EFREETD:-0/AUZIX_PRESTART_EFREETD:-1/' \
  /System/Tools/start-enlightenment-session

# Keep donor desktop metadata, but point it at the validated AUZiX front doors.
# The factory sources carry the same mapping for subsequent package emissions;
# this closes the already-built alpha base without inventing parallel entries.
writer_desktop=/System/Compatibility/usr/share/applications/auzix-LibreOfficeWriter-libreoffice-writer.desktop
if test -s "$writer_desktop"; then
  sed -i \
    -e 's#/Programs/LibreOfficeWriter/current/Commands/loweb --writer#/Programs/LibreOfficeWriter/current/Commands/lowriter#g' \
    -e '/^NoDisplay=true$/d' \
    -e '/^X-AUZiX-Launcher-State=quarantined-unvalidated$/d' \
    "$writer_desktop"
fi

terminology_desktop=/System/Compatibility/usr/share/applications/terminology.desktop
if test -s "$terminology_desktop"; then
  sed -i \
    -e 's#^Exec=.*#Exec=/System/Tools/launch-auzix-terminal %U#' \
    -e '/^NoDisplay=true$/d' \
    "$terminology_desktop"
fi

rm -f /Work/finalize-alpha-final
