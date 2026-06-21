# syntax=docker/dockerfile:1.6
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      jq \
      lua5.4 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY packages/source-workbench.seed.json /workspace/packages/source-workbench.seed.json
COPY packages/source-workbench.schema.json /workspace/packages/source-workbench.schema.json
COPY scripts/source-workbench-boot.sh /workspace/scripts/source-workbench-boot.sh

RUN chmod 0755 /workspace/scripts/source-workbench-boot.sh

ENTRYPOINT ["/workspace/scripts/source-workbench-boot.sh"]
