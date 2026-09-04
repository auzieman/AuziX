# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=auzix/alpha:pre-hdd-salvage-20260831-r8
FROM ${BASE_IMAGE} AS final

COPY overlay/Programs/ /Programs/
COPY overlay/System/ /System/
COPY overlay/Users/ /Users/
COPY overlay/etc/passwd overlay/etc/group overlay/etc/shadow overlay/etc/gshadow /etc/
COPY overlay/etc/ssh/sshd_config /etc/ssh/sshd_config
COPY --chmod=0755 finalize-alpha-final.sh /Work/finalize-alpha-final
COPY --chmod=0755 validate-alpha-final-root.sh /Work/validate-alpha-final-root

RUN ["/Programs/BusyBox/current/Commands/busybox", "sh", "/Work/finalize-alpha-final"]

FROM final AS validation
RUN ["/Programs/BusyBox/current/Commands/busybox", "sh", "/Work/validate-alpha-final-root", "/"]
