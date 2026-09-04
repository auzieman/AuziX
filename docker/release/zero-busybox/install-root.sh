#!/bin/sh
set -eu

mkdir -p /target

# These three packages establish the AUZiX shell and package-manager spine.
apk add \
  --initdb \
  --root /target \
  --allow-untrusted \
  /Repository/*.apk

PYTHONPATH=/factory python3 -m auzix activate-layout /target

test -s /target/System/State/apk/db/installed
rm -rf /Repository
