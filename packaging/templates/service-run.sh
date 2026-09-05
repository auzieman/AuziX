#!/bin/sh
# /Services/@NAME@/run — package-owned service.
# Not invoke-rc.d, not update-rc.d, not deb-systemd-helper.
# apk does not start this. activation/base.py walks /Services/*/run.
# Image/first-boot owns whether this guest enables it.
set -eu
NAME=@NAME@
PACKAGE_ROOT=${AUZIX_PACKAGE_ROOT:-@PACKAGE_ROOT@}
for candidate in \
	"$PACKAGE_ROOT/Commands/$NAME" \
	"$PACKAGE_ROOT/RootFS/usr/sbin/$NAME" \
	"$PACKAGE_ROOT/RootFS/usr/bin/$NAME"
do
	if [ -x "$candidate" ]; then
		exec "$candidate"
	fi
done
exit 0
