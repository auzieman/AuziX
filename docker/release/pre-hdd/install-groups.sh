#!/bin/sh
set -eu

mkdir -p /target

# Establish only the AUZiX package-management spine from local bootstrap APKs.
apk add \
  --initdb \
  --root /target \
  --allow-untrusted \
  /factory/repository/bootstrap/*.apk

PYTHONPATH=/factory python3 -m auzix activate-layout /target
install -D -m 0644 /factory/trust/repository.rsa.pub \
  /target/System/Settings/apk/keys/repository.rsa.pub
install -D -m 0644 /factory/trust/ca.crt \
  /target/System/Settings/apk/repository-ca.crt
install -D -m 0644 /etc/resolv.conf \
  /target/System/Settings/resolv.conf
# Preserve BuildKit's build-local repository mapping inside the chroot. The
# repository name is intentionally not dependent on public or host DNS.
install -D -m 0644 /etc/hosts \
  /target/System/Settings/hosts
printf '%s\n' "$AUZIX_APK_REPOSITORY" \
  > /target/System/Settings/apk/repositories

install_group() {
  group="$1"
  packages=$(
    sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$group"
  )
  test -n "$packages"
  echo "pre-hdd package block: $(basename "$group")"
  chroot /target /Programs/BusyBox/current/Commands/busybox env \
    SSL_CERT_FILE=/System/Settings/apk/repository-ca.crt \
    /Programs/ApkTools/current/Commands/apk add \
      --keys-dir /System/Settings/apk/keys \
      --repository "$AUZIX_APK_REPOSITORY" \
      $packages
}

for group in /factory/groups/*.list; do
  install_group "$group"
done

test -s /target/System/State/apk/db/installed
# Package current links are absolute within the target, not the tooling root.
before=$(chroot /target /Programs/BusyBox/current/Commands/busybox sha256sum \
  /System/State/apk/db/installed)
before=${before%% *}

# A package-composed root must be replay-safe. Reapply the same declared blocks
# and prove APK did not rewrite its installed-state database.
for group in /factory/groups/*.list; do
  install_group "$group"
done
after=$(chroot /target /Programs/BusyBox/current/Commands/busybox sha256sum \
  /System/State/apk/db/installed)
after=${after%% *}
test "$before" = "$after"

# Exercise account writes in the installed-root layout. Shadow rejects leaf
# symlinks; Docker's runtime /etc shim is not the HDD's directory alias.
chroot /target /Programs/BusyBox/current/Commands/busybox sh -ec '
  adduser --system --no-create-home auzix-validation >/dev/null
  id auzix-validation >/dev/null
  deluser auzix-validation >/dev/null
  ! grep -q "^auzix-validation:" /System/Settings/passwd
'

mkdir -p /target/System/State/packages
cat >/target/System/State/packages/pre-hdd-transaction.receipt <<EOF
format=auzix-pre-hdd-transaction-v1
repository=$AUZIX_APK_REPOSITORY
installed_db_sha256=$after
replay=no-op
account_roundtrip=pass
EOF
