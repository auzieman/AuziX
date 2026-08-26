ARG BASE_IMAGE=auzix/service:zero-busybox
FROM ${BASE_IMAGE}

COPY root/ /

RUN /Programs/BusyBox/current/Commands/busybox chown -R 65534:65534 \
    /Services/Nginx /System/State/Nginx /System/Logs/Nginx /Work/Nginx /Work/Temp

WORKDIR /Work
USER 65534:65534
EXPOSE 8080
ENV PATH=/System/Compatibility/bin:/Programs/Busybox/current/Commands:/Programs/BusyBox/current/Commands:/Programs/Nginx/current/Commands
CMD ["/Services/Nginx/run"]
