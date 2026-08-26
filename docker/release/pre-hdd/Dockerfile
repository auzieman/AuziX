FROM scratch

COPY root/ /

WORKDIR /Work
ENV HOME=/Users/root
ENV TERM=xterm-256color
ENV PATH=/Programs/Glances/current/Commands:/Programs/Htop/current/Commands:/Programs/Python313Minimal/current/Commands:/Programs/LibreOfficeWriter/current/Commands:/System/Compatibility/bin:/System/Compatibility/sbin:/Programs/Busybox/current/Commands:/Programs/BusyBox/current/Commands
ENV TMPDIR=/Work/Temp
ENV TERMINFO_DIRS=/Programs/NcursesBase/current/RootFS/usr/share/terminfo:/Programs/NcursesTerm/current/RootFS/usr/share/terminfo:/Programs/KittyTerminfo/current/RootFS/usr/share/terminfo
ENV SSL_CERT_DIR=/System/Compatibility/etc/ssl/certs
ENV SSL_CERT_FILE=/System/Compatibility/etc/ssl/certs/ca-certificates.crt
CMD ["/Programs/Busybox/current/Commands/busybox", "sh"]
