# syntax=docker/dockerfile:1.6
FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      apt \
      ca-certificates \
      dpkg-dev \
      file \
      jq \
      rsync \
      tar \
      xz-utils && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

CMD ["./scripts/run-auzix-trixie-intake.sh"]
