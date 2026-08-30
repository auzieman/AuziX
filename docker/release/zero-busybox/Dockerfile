FROM scratch

COPY root/ /

WORKDIR /Work
ENV PATH=/System/Compatibility/bin:/Programs/Busybox/current/Commands:/Programs/BusyBox/current/Commands
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=5s --start-period=2s --retries=3 \
  CMD ["/Programs/Busybox/current/Commands/busybox", "test", "-x", "/System/Libraries/Runtime/glibc/libc.so.6"]
CMD ["/Services/Container/run"]
