ARG BASE_IMAGE=auzix/service:zero-busybox
FROM ${BASE_IMAGE}

COPY root/ /

SHELL ["/Programs/BusyBox/current/Commands/busybox", "sh", "-c"]
RUN /Programs/BusyBox/current/Commands/busybox chown -R 65534:65534 \
    /Services/Nginx /System/State/Nginx /System/Logs/Nginx /Work/Nginx /Work/Temp

WORKDIR /Work
USER 65534:65534
EXPOSE 8080
ENV PATH=/System/Compatibility/bin:/Programs/Busybox/current/Commands:/Programs/BusyBox/current/Commands:/Programs/Nginx/current/Commands
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=5s --start-period=3s --retries=3 \
  CMD ["/Programs/Busybox/current/Commands/busybox", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8080/"]
CMD ["/Services/Nginx/run"]
