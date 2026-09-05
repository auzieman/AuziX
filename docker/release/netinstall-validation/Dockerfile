ARG BASE_IMAGE=auzix/service:zero-busybox
FROM ${BASE_IMAGE}

# Match the installed-root runtime contract, not the external chroot tooling.
ENV HOME=/Users/root TERM=xterm-256color TMPDIR=/Work/Temp
ENV PATH=/System/Compatibility/bin:/System/Compatibility/sbin:/Programs/BusyBox/current/Commands
ENV LD_LIBRARY_PATH=/Libraries:/System/Libraries/Runtime/glibc
ENV SSL_CERT_FILE=/System/Compatibility/etc/ssl/certs/ca-certificates.crt
ENV SSL_CERT_DIR=/System/Compatibility/etc/ssl/certs
COPY --chmod=0755 docker/release/common/runtime-entrypoint.sh /Services/Container/runtime-entrypoint

COPY --from=auzix_repository_trust /ca.crt /System/Settings/apk/repository-ca.crt
COPY --from=auzix_repository_trust /repository.rsa.pub /System/Settings/apk/keys/repository.rsa.pub
COPY docker/release/netinstall-validation/packages.list /System/Settings/apk/netinstall-validation.packages
COPY --chmod=0755 docker/release/common/install-package-list.sh /System/Tools/install-package-list
COPY --chmod=0755 docker/release/netinstall-validation/validate.sh /System/Validation/validate-netinstall

ARG AUZIX_APK_REPOSITORY=https://auzix-repo.test:8443
ARG AUZIX_APK_INDEX_SHA256
RUN AUZIX_PACKAGE_LIST=/System/Settings/apk/netinstall-validation.packages \
    SSL_CERT_FILE=/System/Settings/apk/repository-ca.crt \
    /System/Tools/install-package-list
RUN ["/Services/Container/runtime-entrypoint", "/Programs/BusyBox/current/Commands/busybox", "sh", "/System/Validation/validate-netinstall"]

# The expanded package transaction is complete in the image. Runtime inherits
# zero's normal container service and performs no installation.
CMD ["/Services/Container/run"]
