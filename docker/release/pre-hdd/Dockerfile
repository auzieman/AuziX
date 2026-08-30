FROM scratch

COPY root/ /

RUN ["/Programs/Busybox/current/Commands/busybox", "chown", "-R", "1000:1000", "/Users/auzix", "/Work/Temp", "/Work/Validation"]

WORKDIR /Work
ENV HOME=/Users/root
ENV TERM=xterm-256color
ENV PATH=/Programs/Glances/current/Commands:/Programs/Htop/current/Commands:/Programs/Python313Minimal/current/Commands:/Programs/LibreOfficeWriter/current/Commands:/System/Compatibility/bin:/System/Compatibility/sbin:/Programs/Busybox/current/Commands:/Programs/BusyBox/current/Commands
ENV TMPDIR=/Work/Temp
ENV TERMINFO_DIRS=/Programs/NcursesBase/current/RootFS/usr/share/terminfo:/Programs/NcursesTerm/current/RootFS/usr/share/terminfo:/Programs/KittyTerminfo/current/RootFS/usr/share/terminfo
ENV SSL_CERT_DIR=/System/Compatibility/etc/ssl/certs
ENV SSL_CERT_FILE=/System/Compatibility/etc/ssl/certs/ca-certificates.crt
ENV PYTHONHOME=/Programs/Libpython313Minimal/current/RootFS/usr
ENV PYTHONPATH=/Programs/Libpython313Stdlib/current/RootFS/usr/lib/python3.13:/Programs/Libpython313Stdlib/current/RootFS/usr/lib/python3.13/lib-dynload:/Programs/Libpython313Minimal/current/RootFS/usr/lib/python3.13:/Programs/Libpython313Minimal/current/RootFS/usr/lib/python3.13/lib-dynload
ENV LD_LIBRARY_PATH=/System/Libraries/Runtime/glibc:/Programs/Libncursesw6/current/RootFS/usr/lib/x86_64-linux-gnu:/Programs/Libtinfo6/current/RootFS/usr/lib/x86_64-linux-gnu:/Programs/Libsqlite30/current/RootFS/usr/lib/x86_64-linux-gnu:/Programs/Libssl3t64/current/RootFS/usr/lib/x86_64-linux-gnu
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD ["/Programs/Busybox/current/Commands/busybox", "test", "-s", "/System/State/packages/installed.json"]
CMD ["/Services/Container/run"]
