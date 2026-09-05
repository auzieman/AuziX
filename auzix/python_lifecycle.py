"""Reviewed Trixie Python removal effects; unknown donors are not accepted."""
import hashlib

REVIEWED_PRERM = {
    "Libpython313Minimal": "8f9a796f05b430bfdf348927d5a0e3e07d1f49a090224db243a4b18c86c421f3",
    "Libpython313Stdlib": "06cf99effc867eb9e56bb10996b76edcf5bb78d971dcdd847fe1dc3eda1b23f6",
}

# Debian queries multiarch package ownership before shared-directory cleanup.
# AuziX owns a distinct version RootFS: do not query dpkg or traverse neighbors.
# find defaults to no symlink traversal; preserve dist-packages and source files.
CLEANUP = r'''#!/bin/sh
set -eu
cache_root="${AUZIX_PACKAGE_ROOT:?}/RootFS"
[ -d "$cache_root" ] || exit 0
[ ! -L "$cache_root" ] || exit 1
find "$cache_root" -type d -name dist-packages -prune -o \
    -type f -path '*/__pycache__/*' \( -name '*.pyc' -o -name '*.pyo' \) \
    -exec rm -f -- {} +
find "$cache_root" -type d -name dist-packages -prune -o \
    -type d -name __pycache__ -empty -exec rmdir -- {} +
'''


def adapt_python_prerm(original: str, package: str, stage: str) -> str | None:
    digest = hashlib.sha256((original.rstrip() + "\n").encode()).hexdigest()
    if stage == "before_remove" and REVIEWED_PRERM.get(package) == digest:
        return CLEANUP
    return None
