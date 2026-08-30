FROM debian:trixie-slim

ARG FPM_VERSION=1.17.0

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl file gcc make patch python3 ruby ruby-dev tar \
 && gem install --no-document fpm --version "${FPM_VERSION}" \
 && fpm --version \
 && rm -rf /var/lib/apt/lists/*

COPY docker/package-factory/fpm-apk-long-path.patch /tmp/fpm-apk-long-path.patch
RUN FPM_ROOT="$(ruby -e 'print Gem::Specification.find_by_name("fpm").full_gem_path')" \
 && patch -d "${FPM_ROOT}" -p1 </tmp/fpm-apk-long-path.patch \
 && rm -f /tmp/fpm-apk-long-path.patch

WORKDIR /workspace
COPY auzix /workspace/auzix
COPY packaging /workspace/packaging
COPY scripts /workspace/scripts
COPY packages /workspace/packages

ENTRYPOINT ["python3", "-m", "auzix"]
