# syntax=docker/dockerfile:1.6
FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      file \
      jq \
      libncursesw6 \
      libreadline8

WORKDIR /workspace

CMD ["./scripts/build-auzix-installer-package.sh"]
