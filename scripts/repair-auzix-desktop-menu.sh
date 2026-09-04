#!/Programs/BusyBox/current/Commands/busybox sh
set -eu

PATH="/Programs/BusyBox/current/Commands:/System/Compatibility/bin:/System/Compatibility/usr/bin:/bin:/usr/bin:${PATH:-}"
export PATH
BB="${BB:-/Programs/BusyBox/current/Commands/busybox}"

awk() { "${BB}" awk "$@"; }
basename() { "${BB}" basename "$@"; }
cat() { "${BB}" cat "$@"; }
chmod() { "${BB}" chmod "$@"; }
date() { "${BB}" date "$@"; }
find() { "${BB}" find "$@"; }
grep() { "${BB}" grep "$@"; }
head() { "${BB}" head "$@"; }
mkdir() { "${BB}" mkdir "$@"; }
mv() { "${BB}" mv "$@"; }
sed() { "${BB}" sed "$@"; }
sort() { "${BB}" sort "$@"; }
wc() { "${BB}" wc "$@"; }

# Rebuild the AUZiX desktop/menu surface on an installed root.
#
# This intentionally does not install packages.  It repairs the shared menu
# taxonomy, normalizes existing AUZiX desktop entries, and refreshes desktop
# databases when the relevant helpers are available.

AUZIX_ROOT="${1:-/}"

case "${AUZIX_ROOT}" in
  /) root_prefix="" ;;
  *) root_prefix="${AUZIX_ROOT}" ;;
esac

p() {
  printf '%s%s\n' "${root_prefix}" "$1"
}

mkdir -p \
  "$(p /System/Settings/xdg/menus)" \
  "$(p /System/Compatibility/usr/share/desktop-directories)" \
  "$(p /System/Compatibility/usr/share/applications)" \
  "$(p /System/Logs/packages)"

cat >"$(p /System/Settings/xdg/menus/e-applications.menu)" <<'EOF_MENU'
<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
 "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">
<Menu>
  <Name>Applications</Name>
  <DefaultAppDirs/>
  <DefaultDirectoryDirs/>
  <Directory>auzix-applications.directory</Directory>

  <Menu>
    <Name>System</Name>
    <Directory>auzix-system.directory</Directory>
    <Include>
      <Category>System</Category>
      <Category>TerminalEmulator</Category>
    </Include>
  </Menu>

  <Menu>
    <Name>Internet</Name>
    <Directory>auzix-internet.directory</Directory>
    <Include>
      <Category>Network</Category>
      <Category>WebBrowser</Category>
    </Include>
  </Menu>

  <Menu>
    <Name>Office</Name>
    <Directory>auzix-office.directory</Directory>
    <Include>
      <Category>Office</Category>
      <Category>Spreadsheet</Category>
      <Category>WordProcessor</Category>
      <Category>Presentation</Category>
    </Include>
  </Menu>

  <Menu>
    <Name>Graphics</Name>
    <Directory>auzix-graphics.directory</Directory>
    <Include>
      <Category>Graphics</Category>
      <Category>RasterGraphics</Category>
      <Category>VectorGraphics</Category>
      <Category>Photography</Category>
    </Include>
  </Menu>

  <Menu>
    <Name>Development</Name>
    <Directory>auzix-development.directory</Directory>
    <Include>
      <Category>Development</Category>
      <Category>IDE</Category>
      <Category>TextEditor</Category>
    </Include>
  </Menu>

  <Menu>
    <Name>Multimedia</Name>
    <Directory>auzix-multimedia.directory</Directory>
    <Include>
      <Category>AudioVideo</Category>
      <Category>Audio</Category>
      <Category>Video</Category>
    </Include>
  </Menu>

  <Menu>
    <Name>Settings</Name>
    <Directory>auzix-settings.directory</Directory>
    <Include>
      <Category>Settings</Category>
    </Include>
  </Menu>

  <Menu>
    <Name>Other</Name>
    <Directory>auzix-other.directory</Directory>
    <OnlyUnallocated/>
    <Include>
      <All/>
    </Include>
  </Menu>
</Menu>
EOF_MENU

write_directory() {
  file="$1"
  name="$2"
  icon="$3"
  cat >"$(p "/System/Compatibility/usr/share/desktop-directories/${file}")" <<EOF_DIRECTORY
[Desktop Entry]
Type=Directory
Name=${name}
Icon=${icon}
EOF_DIRECTORY
}

write_directory auzix-applications.directory Applications applications-other
write_directory auzix-system.directory System applications-system
write_directory auzix-internet.directory Internet applications-internet
write_directory auzix-office.directory Office applications-office
write_directory auzix-graphics.directory Graphics applications-graphics
write_directory auzix-development.directory Development applications-development
write_directory auzix-multimedia.directory Multimedia applications-multimedia
write_directory auzix-settings.directory Settings preferences-system
write_directory auzix-other.directory Other applications-other

normalize_desktop_file() {
  desktop_file="$1"
  tmp_file="${desktop_file}.tmp.$$"
  program_name=""
  desktop_base="$(basename "${desktop_file}")"

  case "${desktop_base}" in
    auzix-*-*.desktop)
      program_name="$(printf '%s\n' "${desktop_base}" | sed -E 's/^auzix-([^-]+)-.*$/\1/')"
      ;;
  esac

  exec_target=""
  terminal_wrapper=""
  if [ -x "$(p /Programs/XTerm/current/Commands/xterm)" ]; then
    terminal_wrapper="env TERM=xterm-256color TERMINFO_DIRS=/System/Compatibility/usr/share/terminfo /Programs/XTerm/current/Commands/xterm -tn xterm-256color -fa Monospace -fs 11 -bg black -fg white -e"
  elif [ -x "$(p /Programs/Terminology/current/Commands/terminology)" ]; then
    terminal_wrapper="env TERM=xterm-256color TERMINFO_DIRS=/System/Compatibility/usr/share/terminfo /Programs/Terminology/current/Commands/terminology -e"
  fi
  terminal_true=0
  if grep -q '^Terminal=true' "${desktop_file}" 2>/dev/null; then
    terminal_true=1
  fi
  if [ -n "${program_name}" ] && [ -d "$(p "/Programs/${program_name}/current/Commands")" ]; then
    original_command="$(
      awk -F= '/^Exec=/ { print $2; exit }' "${desktop_file}" |
        awk '{ print $1 }' |
        sed 's#.*/##'
    )"
    if [ -n "${original_command}" ] &&
      [ -x "$(p "/Programs/${program_name}/current/Commands/${original_command}")" ]; then
      exec_target="/Programs/${program_name}/current/Commands/${original_command}"
    fi
    if [ -z "${exec_target}" ]; then
      case "${desktop_base}" in
        *[Ll]ibre*[Cc]alc*.desktop|*[Cc]alc*.desktop) preferred_command="localc" ;;
        *[Ll]ibre*[Ww]riter*.desktop|*[Ww]riter*.desktop) preferred_command="lowriter" ;;
        *[Ll]ibre*[Ii]mpress*.desktop|*[Ii]mpress*.desktop) preferred_command="loimpress" ;;
        *[Ll]ibre*[Dd]raw*.desktop|*[Dd]raw*.desktop) preferred_command="lodraw" ;;
        *[Gg]numeric*.desktop) preferred_command="gnumeric" ;;
        *[Mm]idori*.desktop) preferred_command="midori" ;;
        *[Nn]et[Ss]urf*.desktop) preferred_command="netsurf" ;;
        *[Gg]eany*.desktop) preferred_command="geany" ;;
        *[Ll]3afpad*.desktop) preferred_command="l3afpad" ;;
        *[Aa]bi[Ww]ord*.desktop) preferred_command="abiword" ;;
        *[Gg]alculator*.desktop) preferred_command="galculator" ;;
        *) preferred_command="" ;;
      esac
      if [ -n "${preferred_command}" ] &&
        [ -x "$(p "/Programs/${program_name}/current/Commands/${preferred_command}")" ]; then
        exec_target="/Programs/${program_name}/current/Commands/${preferred_command}"
      fi
    fi
    if [ -z "${exec_target}" ]; then
      first_command="$("${BB}" find "$(p "/Programs/${program_name}/current/Commands")" -maxdepth 1 -type f -perm /111 -print 2>/dev/null | sed 's#.*/##' | sort | head -n 1 || true)"
      if [ -n "${first_command}" ]; then
        exec_target="/Programs/${program_name}/current/Commands/${first_command}"
      fi
    fi
  fi

  awk -v exec_target="${exec_target}" -v terminal_wrapper="${terminal_wrapper}" -v terminal_true="${terminal_true}" '
    BEGIN { saw_type=0; saw_terminal=0; saw_nodisplay=0 }
    /^Type=/ { saw_type=1 }
    /^Terminal=/ {
      saw_terminal=1
      if ($0 ~ /^Terminal=true/ && terminal_wrapper != "") {
        print "Terminal=false"
        next
      }
    }
    /^NoDisplay=/ { saw_nodisplay=1; next }
    /^Exec=/ && exec_target != "" {
      # Replace only argv[0]. Debian desktop entries often carry meaningful
      # component selectors such as `libreoffice --calc %U`; retaining only
      # field codes silently changes which application the wrapper starts.
      original=$0
      sub(/^Exec=[^[:space:]]+/, "", original)
      suffix=original
      if (terminal_wrapper != "" && terminal_true == 1) {
        print "Exec=" terminal_wrapper " " exec_target suffix
      } else {
        print "Exec=" exec_target suffix
      }
      next
    }
    /^TryExec=/ && exec_target != "" {
      print "TryExec=" exec_target
      next
    }
    { print }
    END {
      if (!saw_type) print "Type=Application"
      if (!saw_terminal) print "Terminal=false"
    }
  ' "${desktop_file}" >"${tmp_file}"
  mv "${tmp_file}" "${desktop_file}"
  chmod 0644 "${desktop_file}"
}

if [ -d "$(p /System/Compatibility/usr/share/applications)" ]; then
  "${BB}" find "$(p /System/Compatibility/usr/share/applications)" -maxdepth 1 -type f -name '*.desktop' -print |
    while IFS= read -r desktop_file; do
      normalize_desktop_file "${desktop_file}"
    done
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$(p /System/Compatibility/usr/share/applications)" >/dev/null 2>&1 || true
elif [ -x "$(p /Programs/DesktopFileUtils/current/Commands/update-desktop-database)" ]; then
  "$(p /Programs/DesktopFileUtils/current/Commands/update-desktop-database)" \
    "$(p /System/Compatibility/usr/share/applications)" >/dev/null 2>&1 || true
fi

if command -v update-mime-database >/dev/null 2>&1 && [ -d "$(p /System/Compatibility/usr/share/mime)" ]; then
  update-mime-database "$(p /System/Compatibility/usr/share/mime)" >/dev/null 2>&1 || true
elif [ -x "$(p /Programs/SharedMimeInfo/current/Commands/update-mime-database)" ] &&
  [ -d "$(p /System/Compatibility/usr/share/mime)" ]; then
  "$(p /Programs/SharedMimeInfo/current/Commands/update-mime-database)" \
    "$(p /System/Compatibility/usr/share/mime)" >/dev/null 2>&1 || true
fi

{
  printf 'auzix desktop menu repaired: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)"
  printf 'desktop entries: '
  "${BB}" find "$(p /System/Compatibility/usr/share/applications)" -maxdepth 1 -type f -name '*.desktop' 2>/dev/null | wc -l
} >>"$(p /System/Logs/packages/desktop-menu-repair.log)"
