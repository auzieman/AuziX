#!/Programs/BusyBox/current/Commands/busybox sh
set -eu

BB="${BB:-/Programs/BusyBox/current/Commands/busybox}"
JQ="${JQ:-/usr/bin/jq}"
ROOT="${1:-/}"
PROFILE="${2:-/System/Settings/auzix/desktop-first-wave-launchers.profile.json}"
MODE="${3:-dry-run}"
REPORT="${REPORT:-/System/State/reports/desktop-launcher-publish-first-wave.md}"
JSON_REPORT="${JSON_REPORT:-/System/State/reports/desktop-launcher-publish-first-wave.jsonl}"

case "${ROOT}" in
  /) prefix="" ;;
  *) prefix="${ROOT}" ;;
esac

p() {
  printf '%s%s\n' "${prefix}" "$1"
}

mkdir_p() { "${BB}" mkdir -p "$@"; }
grep_q() { "${BB}" grep "$@" >/dev/null 2>&1; }

APP_DIR="$(p /System/Compatibility/usr/share/applications)"
mkdir_p "${APP_DIR}" "$(p /System/State/reports)"

if [ ! -x "${JQ}" ]; then
  echo "jq is required for profile parsing: ${JQ}" >&2
  exit 2
fi
if [ ! -f "${PROFILE}" ]; then
  echo "profile missing: ${PROFILE}" >&2
  exit 2
fi

apply=0
[ "${MODE}" = "--apply" ] || [ "${MODE}" = "apply" ] && apply=1

hide_desktop() {
  file="$1"
  reason="$2"
  [ -f "${file}" ] || return 0
  tmp="${file}.tmp.$$"
  if grep_q -q '^NoDisplay=' "${file}"; then
    "${BB}" sed -E 's/^NoDisplay=.*/NoDisplay=true/' "${file}" >"${tmp}"
  else
    "${BB}" cat "${file}" >"${tmp}"
    echo 'NoDisplay=true' >>"${tmp}"
  fi
  if grep_q -q '^X-AUZiX-Launcher-State=' "${tmp}"; then
    "${BB}" sed -E "s/^X-AUZiX-Launcher-State=.*/X-AUZiX-Launcher-State=${reason}/" "${tmp}" >"${tmp}.2"
    "${BB}" mv "${tmp}.2" "${tmp}"
  else
    echo "X-AUZiX-Launcher-State=${reason}" >>"${tmp}"
  fi
  "${BB}" mv "${tmp}" "${file}"
  "${BB}" chmod 0644 "${file}"
}

write_canonical() {
  target_id="$1"
  name="$2"
  command="$3"
  icon="$4"
  categories="$5"
  state="$6"
  hidden="$7"
  file="${APP_DIR}/auzix-${target_id}.desktop"
  {
    echo '[Desktop Entry]'
    echo 'Type=Application'
    echo "Name=${name}"
    echo "Exec=${command} %U"
    echo "Icon=${icon}"
    echo 'Terminal=false'
    echo "Categories=${categories};"
    echo "NoDisplay=${hidden}"
    echo "X-AUZiX-Launcher-State=${state}"
    echo "X-AUZiX-Launcher-Id=${target_id}"
  } >"${file}"
  "${BB}" chmod 0644 "${file}"
}

find_candidates() {
  target_id="$1"
  desktop_files="$2"
  desktop_names="$3"
  for file in ${desktop_files}; do
    [ -f "${APP_DIR}/${file}" ] && echo "${APP_DIR}/${file}"
  done
  [ -d "${APP_DIR}" ] || return 0
  "${BB}" find "${APP_DIR}" -maxdepth 1 -type f -name '*.desktop' 2>/dev/null |
    while IFS= read -r desktop; do
      name="$("${BB}" awk -F= '/^Name=/ { print $2; exit }' "${desktop}" 2>/dev/null || true)"
      for wanted in ${desktop_names}; do
        [ "${name}" = "${wanted}" ] && echo "${desktop}"
      done
    done |
    "${BB}" sort -u
}

probe_command() {
  command="$1"
  probe_args="$2"
  out_file="$3"
  if [ ! -x "$(p "${command}")" ]; then
    echo 'missing-command' >"${out_file}"
    return 2
  fi
  if [ -z "${probe_args}" ]; then
    echo 'no-probe' >"${out_file}"
    return 0
  fi
  HOME=/Users/auzix USER=auzix LOGNAME=auzix XDG_RUNTIME_DIR=/run/user/1000 \
    "${BB}" timeout 15 "$(p "${command}")" ${probe_args} >"${out_file}" 2>&1 && return 0
  return $?
}

append_logs() {
  {
    echo
    echo '## Embedded Enlightenment/session log tails'
    echo
    found=0
    for log in \
      "$(p /Users/auzix/.e-log.log)" \
      "$(p /Users/auzix/.e/e.log)" \
      "$(p /System/Logs/packages/enlightenment-menu-restart.log)" \
      "$(p /System/Logs/packages/enlightenment-launcher-sync.log)" \
      "$(p /System/Logs/packages/desktop-menu-repair.log)" \
      "$(p /System/Logs/display/Xorg-lightdm.log)"; do
      [ -f "${log}" ] || continue
      found=1
      echo "### \`${log#${prefix}}\`"
      echo
      echo '```text'
      "${BB}" tail -n 80 "${log}" 2>/dev/null || true
      echo '```'
      echo
    done
    if [ "${found}" = "0" ]; then
      echo 'No Enlightenment/session logs were found in the scanned locations.'
    fi
  } >>"${REPORT}"
}

{
  echo '# AUZiX first-wave desktop launcher publish report'
  echo
  echo "- root: \`${ROOT}\`"
  echo "- profile: \`${PROFILE}\`"
  echo "- apply: \`${apply}\`"
  echo
  echo '## Targets'
  echo
} >"${REPORT}"
: >"${JSON_REPORT}"

"${JQ}" -r '.quarantine_desktop_files[]? // empty' "${PROFILE}" |
while IFS= read -r quarantine_file; do
  [ -n "${quarantine_file}" ] || continue
  if [ "${apply}" = "1" ] && [ -f "${APP_DIR}/${quarantine_file}" ]; then
    hide_desktop "${APP_DIR}/${quarantine_file}" "quarantined-profile-first-wave"
  fi
done

"${JQ}" -r '
  .targets[] |
  [
    .id,
    .name,
    .command,
    (.probe // [] | join(" ")),
    (.categories // ["Utility"] | join(";")),
    (.icon // "application-x-executable"),
    (.desktop_files // [] | join(" ")),
    (.desktop_names // [] | join("|"))
  ] | @tsv
' "${PROFILE}" |
while IFS="$(printf '\t')" read -r target_id name command probe_args categories icon desktop_files desktop_names_raw; do
  desktop_names="$("${BB}" printf '%s\n' "${desktop_names_raw}" | "${BB}" sed 's/|/ /g')"
  probe_file="$(p "/Work/Temp/auzix-launcher-${target_id}.probe")"
  candidates="$(find_candidates "${target_id}" "${desktop_files}" "${desktop_names}" | "${BB}" sort -u | "${BB}" tr '\n' ' ')"
  rc=0
  probe_command "${command}" "${probe_args}" "${probe_file}" || rc=$?
  command_exists=false
  [ -x "$(p "${command}")" ] && command_exists=true
  state=desktop-visible
  promoted=true
  hidden=false
  if [ "${command_exists}" != "true" ]; then
    state=missing-command
    promoted=false
    hidden=true
  elif [ "${rc}" != "0" ] &&
    ! "${BB}" grep -qi 'cannot open display' "${probe_file}" 2>/dev/null; then
    state=command-present-probe-failed
    promoted=false
    hidden=true
  fi

  if [ "${apply}" = "1" ]; then
    for candidate in ${candidates}; do
      [ "${candidate}" = "${APP_DIR}/auzix-${target_id}.desktop" ] && continue
      hide_desktop "${candidate}" "quarantined-duplicate-of-${target_id}"
    done
    write_canonical "${target_id}" "${name}" "${command}" "${icon}" "${categories}" "${state}" "${hidden}"
  fi

  {
    echo "### ${name} \`${target_id}\`"
    echo
    echo "- state: \`${state}\`"
    echo "- promoted: \`${promoted}\`"
    echo "- command: \`${command}\`"
    echo "- command_exists: \`${command_exists}\`"
    echo "- candidates: \`${candidates}\`"
    echo "- canonical_desktop: \`/System/Compatibility/usr/share/applications/auzix-${target_id}.desktop\`"
    echo "- probe_rc: \`${rc}\`"
    echo
    echo '```text'
    "${BB}" head -n 40 "${probe_file}" 2>/dev/null || true
    echo '```'
    echo
  } >>"${REPORT}"

  "${JQ}" -cn \
    --arg id "${target_id}" \
    --arg name "${name}" \
    --arg command "${command}" \
    --arg state "${state}" \
    --arg promoted "${promoted}" \
    --arg command_exists "${command_exists}" \
    --arg candidates "${candidates}" \
    --argjson rc "${rc}" \
    '{id:$id,name:$name,command:$command,state:$state,promoted:$promoted,command_exists:$command_exists,candidates:$candidates,probe_rc:$rc}' \
    >>"${JSON_REPORT}"
done

if [ "${apply}" = "1" ]; then
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${APP_DIR}" >>"${REPORT}" 2>&1 || true
  elif [ -x "$(p /Programs/DesktopFileUtils/current/Commands/update-desktop-database)" ]; then
    "$(p /Programs/DesktopFileUtils/current/Commands/update-desktop-database)" "${APP_DIR}" >>"${REPORT}" 2>&1 || true
  fi
  if [ -x "$(p /Programs/Enlightenment/current/Commands/enlightenment_remote)" ]; then
    HOME=/Users/auzix USER=auzix LOGNAME=auzix DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
      "$(p /Programs/Enlightenment/current/Commands/enlightenment_remote)" -restart \
      >>"$(p /System/Logs/packages/enlightenment-launcher-publish-restart.log)" 2>&1 || true
  elif command -v enlightenment_remote >/dev/null 2>&1; then
    HOME=/Users/auzix USER=auzix LOGNAME=auzix DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
      enlightenment_remote -restart \
      >>"$(p /System/Logs/packages/enlightenment-launcher-publish-restart.log)" 2>&1 || true
  fi
fi

append_logs
echo "launcher report: ${REPORT}" >&2
echo "launcher jsonl: ${JSON_REPORT}" >&2
