# syntax=docker/dockerfile:1.6
FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      acl \
      acpid \
      alsa-utils \
      bash \
      binutils \
      bison \
      bzip2 \
      ca-certificates \
      cpio \
      curl \
      dbus \
      dbus-x11 \
      dpkg-dev \
      e2fsprogs \
      enlightenment \
      fdisk \
      file \
      flex \
      gcc \
      git \
      grub-common \
      grub-efi-amd64-bin \
      grub-pc-bin \
      jq \
      libc-bin \
      libc6-dev \
      lightdm \
      lightdm-gtk-greeter \
      linux-image-amd64 \
      make \
      mtools \
      netsurf-common \
      netsurf-gtk \
      openssh-client \
      openssh-server \
      openssl \
      pulseaudio \
      qemu-utils \
      rsync \
      strace \
      sudo \
      terminology \
      udev \
      wget \
      xorriso \
      xserver-xorg-core \
      xserver-xorg-input-libinput \
      xserver-xorg-video-fbdev \
      xserver-xorg-video-vesa \
      xterm \
      xz-utils \
      zstd && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

CMD ["./scripts/build-auzix-strict-all.sh"]
