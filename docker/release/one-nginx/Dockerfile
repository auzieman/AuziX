# syntax=docker/dockerfile:1.7
#
# one-nginx: zero-busybox plus package-installed Nginx, serving the exact
# signed repository consumed by netinstall and pre-HDD stages.

ARG BASE_IMAGE=auzix/service:zero-busybox-apk-edge
FROM ${BASE_IMAGE}

# Validation extras (curl + auzix-debug-tools/ldd) are apk-added here for
# ladder proofs and fall off later small images. wget/stat/strings stay
# BusyBox applets from zero — do not extra-package them, and do not bloat zero.
#
# Program payloads enter through apk add. Named contexts carry immutable build
# output without copying generated archives into the source checkout.
COPY packages.list /System/Settings/apk/one-nginx.packages
COPY --from=auzix_repository / /Repository/
COPY --from=auzix_repository_tls /server.crt /System/Settings/Nginx/TLS/server.crt
COPY --from=auzix_repository_tls /server.key /System/Settings/Nginx/TLS/server.key
COPY --chmod=0755 install.sh /Work/install-one-nginx

RUN ["/Programs/BusyBox/current/Commands/busybox", "sh", "/Work/install-one-nginx"]

WORKDIR /Work
EXPOSE 8443
ENV PATH=/System/Compatibility/bin:/Programs/Busybox/current/Commands:/Programs/BusyBox/current/Commands:/Programs/Nginx/current/Commands:/Programs/Curl/current/Commands:/Programs/AUZiXDebugTools/current/Commands
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=5s --start-period=3s --retries=3 \
  CMD ["/Programs/BusyBox/current/Commands/busybox", "nc", "-z", "127.0.0.1", "8443"]
CMD ["/Services/Nginx/run"]
