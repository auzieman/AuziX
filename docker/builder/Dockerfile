# syntax=docker/dockerfile:1.6
FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
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
      dosfstools \
      dpkg-dev \
      e2fsprogs \
      enlightenment \
      fdisk \
      file \
      flex \
      gcc \
      genisoimage \
      git \
      grub-common \
      grub-efi-amd64-bin \
      grub-pc \
      grub-pc-bin \
      jq \
      libc-bin \
      libc6-dev \
      lightdm \
      lightdm-gtk-greeter \
      libarchive-tools \
      libefl-all-dev \
      libnss3-tools \
      live-boot \
      live-build \
      live-config \
      linux-image-amd64 \
      make \
      mtools \
      netsurf-common \
      netsurf-gtk \
      openssh-client \
      openssh-server \
      openssl \
      patchelf \
      parted \
      pulseaudio \
      pkg-config \
      qemu-utils \
      rsync \
      strace \
      sudo \
      squashfs-tools \
      terminology \
      udev \
      wget \
      xinit \
      xorriso \
      xserver-xorg-core \
      xserver-xorg-input-libinput \
      xserver-xorg-legacy \
      xserver-xorg-video-fbdev \
      xserver-xorg-video-vesa \
      xterm \
      xz-utils \
      zstd

# AUZiX package intake uses Debian metadata as build-time evidence.  Keep the
# apt lists in the builder image so command-suite/package scripts can resolve
# candidate versions without silently drifting into "metadata unavailable".

WORKDIR /workspace

CMD ["./scripts/build-auzix-strict-all.sh"]
