#!/bin/sh
set -eu
mkdir -p /System/State/package-tests
printf '%s\n' "$@" > /System/State/package-tests/apk-trigger.paths
