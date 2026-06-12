# syntax=docker/dockerfile:1.6
FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      file \
      jq

WORKDIR /workspace

CMD ["./scripts/build-auzix-installer-package.sh"]
