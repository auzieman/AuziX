#!/bin/sh
# AuziX apk trigger. apk runs this when a watched path changes.
# Debian analog: control/triggers `interest /path`. Not a helper binary.
# Body may be shell, lua, or python; this default is a no-op shell.
# Package-specific refresh belongs in this file, not an auzix_* wrapper.
set -eu
exit 0
