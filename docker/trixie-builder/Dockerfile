# syntax=docker/dockerfile:1.6
FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      apt \
      abiword \
      acpid \
      alsa-utils \
      bubblewrap \
      busybox-static \
      ca-certificates \
      dbus \
      dbus-x11 \
      dpkg-dev \
      enlightenment \
      file \
      flatpak \
      g++ \
      gcc \
      git \
      gnupg \
      gpg-agent \
      gpgsm \
      gpgv \
      gnumeric \
      jq \
      less \
      make \
      openssh-client \
      openssh-server \
      ostree \
      pkg-config \
      pulseaudio \
      python3 \
      rsync \
      strace \
      sudo \
      tar \
      terminology \
      udev \
      unzip \
      wget \
      xinit \
      xserver-xorg-core \
      xserver-xorg-input-libinput \
      xserver-xorg-legacy \
      xserver-xorg-video-fbdev \
      xserver-xorg-video-vesa \
      xdg-dbus-proxy \
      xterm \
      xz-utils && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

CMD ["./scripts/run-auzix-trixie-intake.sh"]
