# syntax=docker/dockerfile:1.7

# The bootstrap packages are local trust anchors. The workstation transaction
# itself must cross the same HTTPS APK repository boundary used by HDD builds.
# This is an external APK-tooling stage only. No files from its base filesystem
# enter the final AUZiX image; /target is composed exclusively from AUZiX APKs.
FROM alpine:3.22 AS apk-tooling

RUN apk add --no-cache python3
WORKDIR /bootstrap
COPY auzix /factory/auzix
COPY --from=auzix_bootstrap / /factory/repository/bootstrap/
COPY --from=auzix_repository_trust /ca.crt /factory/trust/ca.crt
COPY --from=auzix_repository_trust /repository.rsa.pub /factory/trust/repository.rsa.pub
COPY docker/release/pre-hdd/groups /factory/groups/
COPY --chmod=0755 docker/release/pre-hdd/install-groups.sh /factory/install-groups

ARG AUZIX_APK_REPOSITORY=https://auzix-repo.test:8443
ARG AUZIX_APK_INDEX_SHA256

RUN test "$(find /factory/repository/bootstrap -type f -name '*.apk' | wc -l)" -eq 3

# External apk introduces the bootstrap and then installs four ordered AUZiX
# package groups over the signed HTTPS repository.
RUN /factory/install-groups

# The reusable image base contains only AUZiX BaseLayout, BusyBox and ApkTools.
FROM scratch AS auzix-base
COPY --from=apk-tooling /target /

# The resulting root is copied only after the network package transaction.
FROM auzix-base AS workstation

# Assertions only: validation may not manufacture identities, configuration,
# keys, library links or desktop caches.
COPY scripts/validate-auzix-pre-hdd-root.sh /Work/validate-root
RUN ["/Programs/BusyBox/current/Commands/busybox", "sh", "-ec", "/Work/validate-root /; rm -f /Work/validate-root"]

FROM scratch
COPY --from=workstation / /
COPY --chmod=0755 docker/release/common/runtime-entrypoint.sh /Services/Container/runtime-entrypoint
COPY --chmod=0755 docker/release/pre-hdd/run /Services/Container/run

WORKDIR /Work
ENV HOME=/Users/root
ENV TERM=xterm-256color
ENV PATH=/Programs/Midori/current/Commands:/Programs/AbiWord/current/Commands:/Programs/Flatpak/current/Commands:/Programs/LibreOfficeWriter/current/Commands:/Programs/LibreOfficeCalc/current/Commands:/Programs/LibreOfficeImpress/current/Commands:/Programs/Terminology/current/Commands:/Programs/Enlightenment/current/Commands:/Programs/Glances/current/Commands:/Programs/Htop/current/Commands:/Programs/Python313Minimal/current/Commands:/System/Compatibility/bin:/System/Compatibility/sbin:/Programs/Busybox/current/Commands:/Programs/BusyBox/current/Commands
ENV TMPDIR=/Work/Temp
ENV TERMINFO_DIRS=/Programs/NcursesBase/current/RootFS/usr/share/terminfo:/Programs/NcursesTerm/current/RootFS/usr/share/terminfo:/Programs/KittyTerminfo/current/RootFS/usr/share/terminfo
ENV SSL_CERT_DIR=/System/Compatibility/etc/ssl/certs
ENV SSL_CERT_FILE=/System/Compatibility/etc/ssl/certs/ca-certificates.crt
ENV PYTHONHOME=/Programs/Libpython313Minimal/current/RootFS/usr
ENV PYTHONPATH=/Programs/Libpython313Stdlib/current/RootFS/usr/lib/python3.13:/Programs/Libpython313Stdlib/current/RootFS/usr/lib/python3.13/lib-dynload:/Programs/Libpython313Minimal/current/RootFS/usr/lib/python3.13:/Programs/Libpython313Minimal/current/RootFS/usr/lib/python3.13/lib-dynload
ENV LD_LIBRARY_PATH=/Libraries:/System/Libraries/Runtime/glibc:/Programs/Libncursesw6/current/RootFS/usr/lib/x86_64-linux-gnu:/Programs/Libtinfo6/current/RootFS/usr/lib/x86_64-linux-gnu:/Programs/Libsqlite30/current/RootFS/usr/lib/x86_64-linux-gnu:/Programs/Libssl3t64/current/RootFS/usr/lib/x86_64-linux-gnu
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD ["/Programs/Busybox/current/Commands/busybox", "test", "-s", "/System/State/apk/db/installed"]
ENTRYPOINT ["/Services/Container/runtime-entrypoint"]
CMD ["/Services/Container/run"]
