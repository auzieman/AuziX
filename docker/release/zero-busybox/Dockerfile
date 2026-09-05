# syntax=docker/dockerfile:1.7

# External APK tooling only; the final scratch image receives /target, which is
# composed exclusively from AUZiX packages.
FROM alpine:3.22 AS apk-tooling
RUN apk add --no-cache python3
COPY auzix /factory/auzix
COPY --from=auzix_bootstrap / /Repository/
COPY --chmod=0755 docker/release/zero-busybox/install-root.sh /factory/install-root
RUN /factory/install-root

FROM scratch
COPY --from=apk-tooling /target /
COPY --chmod=0755 docker/release/common/runtime-entrypoint.sh /Services/Container/runtime-entrypoint
COPY --chmod=0755 docker/release/pre-hdd/run /Services/Container/run

WORKDIR /Work
# BusyBox already provides wget/stat/strings as Compatibility applets.
# ldd needs a glibc loader; it lives on one-nginx (auzix-debug-tools), not here.
ENV PATH=/System/Compatibility/bin:/Programs/Busybox/current/Commands:/Programs/BusyBox/current/Commands
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=5s --start-period=2s --retries=3 \
  CMD ["/Programs/BusyBox/current/Commands/busybox", "sh", "-ec", "test -s /System/State/apk/db/installed; busybox true"]
ENTRYPOINT ["/Services/Container/runtime-entrypoint"]
CMD ["/Services/Container/run"]
