# syntax=docker/dockerfile:1.6
FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      dosfstools \
      e2fsprogs \
      binutils \
      busybox \
      ca-certificates \
      curl \
      file \
      grep \
      conmon \
      crun \
      jq \
      netavark \
      aardvark-dns \
      podman \
      nginx-light \
      patchelf \
      python3 \
      rsync \
      xz-utils && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
CMD ["./scripts/build-auzix-filesystem-tools-slice.sh"]
