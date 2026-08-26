FROM scratch

COPY root/ /

WORKDIR /Work
ENV HOME=/Users/root
ENV TERM=xterm-256color
ENV PATH=/Programs/Glances/current/Commands:/Programs/Htop/current/Commands:/Programs/Python3/current/Commands:/Programs/LibreOfficeWriter/current/Commands:/System/Compatibility/bin:/System/Compatibility/sbin:/Programs/Busybox/current/Commands:/Programs/BusyBox/current/Commands
ENV SSL_CERT_DIR=/System/Compatibility/etc/ssl/certs
ENV SSL_CERT_FILE=/System/Compatibility/etc/ssl/certs/ca-certificates.crt
CMD ["/Programs/Busybox/current/Commands/busybox", "sh"]
