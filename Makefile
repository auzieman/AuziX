.PHONY: compose-build compose-run kustomize-base kustomize-nfs auzix-installer-builder auzix-strict-all auzix-image auzix-vdi auzix-vbox-create auzix-run auzix-gui auzix-vagrant-up auzix-vagrant-up-vbox auzix-vagrant-ssh auzix-vagrant-destroy auzix-strict-root auzix-strict-probe auzix-strict-dynprobe auzix-strict-busybox auzix-strict-live-tools auzix-strict-access auzix-strict-iputils auzix-strict-package-tools auzix-strict-installer auzix-strict-installer-test auzix-strict-grub auzix-strict-sudo auzix-strict-dbus auzix-strict-udev auzix-strict-acpid auzix-strict-pulseaudio auzix-strict-alsa auzix-strict-strace auzix-strict-curl auzix-strict-midori auzix-strict-host-e auzix-strict-host-xorg auzix-strict-host-terminology auzix-strict-host-xterm auzix-strict-netsurf auzix-strict-lightdm auzix-strict-display-templates auzix-strict-e-assets auzix-strict-desktop-assets-package auzix-strict-desktop-repo-packages auzix-strict-user-defaults auzix-strict-kernel-modules auzix-strict-package-repo auzix-strict-container auzix-strict-pruned-test auzix-strict-audit auzix-strict-iso clean

compose-build:
	docker compose build builder

compose-run:
	docker compose run --rm builder

auzix-installer-builder:
	docker compose --profile installer build installer-builder

auzix-package-bot-test:
	./scripts/test-auzix-package-bot.sh

auzix-package-bot-installer-ui:
	./scripts/run-auzix-package-bot.sh packages/installer-ui.queue.json installer-ui-core

kustomize-base:
	kubectl apply -k k8s/base

kustomize-nfs:
	kubectl apply -k k8s/overlays/nfs

auzix-strict-all:
	./scripts/build-auzix-strict-all.sh

auzix-image:
	./scripts/build-auzix-x86-image.sh

auzix-vdi:
	./scripts/build-auzix-vdi.sh

auzix-vbox-create:
	./scripts/create-auzix-virtualbox-vm.sh

auzix-run:
	./scripts/run-auzix-kvm.sh

auzix-gui:
	AUZIX_HEADLESS=0 ./scripts/run-auzix-kvm.sh

auzix-vagrant-up:
	vagrant up --provider=libvirt

auzix-vagrant-up-vbox:
	vagrant up --provider=virtualbox

auzix-vagrant-ssh:
	vagrant ssh

auzix-vagrant-destroy:
	vagrant destroy -f

auzix-strict-root:
	./scripts/scaffold-auzix-strict-root.sh

auzix-strict-probe:
	./scripts/build-auzix-probe-package.sh

auzix-strict-dynprobe:
	./scripts/build-auzix-dynprobe-package.sh

auzix-strict-busybox:
	./scripts/build-auzix-busybox-package.sh

auzix-strict-live-tools:
	./scripts/add-auzix-live-tools.sh

auzix-strict-access:
	./scripts/build-auzix-access-package.sh

auzix-strict-iputils:
	./scripts/build-auzix-iputils-package.sh

auzix-strict-package-tools:
	./scripts/build-auzix-package-tools-package.sh

auzix-strict-installer:
	./scripts/build-auzix-installer-package.sh

auzix-strict-installer-test:
	./scripts/test-auzix-installer.sh

auzix-strict-grub:
	./scripts/build-auzix-grub-package.sh

auzix-strict-sudo:
	./scripts/build-auzix-sudo-package.sh

auzix-strict-dbus:
	./scripts/build-auzix-dbus-package.sh

auzix-strict-udev:
	./scripts/build-auzix-udev-package.sh

auzix-strict-acpid:
	./scripts/build-auzix-acpid-package.sh

auzix-strict-pulseaudio:
	./scripts/build-auzix-pulseaudio-package.sh

auzix-strict-alsa:
	./scripts/build-auzix-alsa-probe-package.sh

auzix-strict-strace:
	./scripts/build-auzix-strace-package.sh

auzix-strict-curl:
	./scripts/build-auzix-curl-package.sh

auzix-strict-midori:
	./scripts/build-auzix-midori-package.sh

auzix-strict-host-e:
	./scripts/build-auzix-host-enlightenment-package.sh

auzix-strict-host-xorg:
	./scripts/build-auzix-host-xorg-package.sh

auzix-strict-host-terminology:
	./scripts/build-auzix-host-terminology-package.sh

auzix-strict-host-xterm:
	./scripts/build-auzix-host-xterm-package.sh

auzix-strict-netsurf:
	./scripts/build-auzix-netsurf-package.sh

auzix-strict-lightdm:
	./scripts/build-auzix-lightdm-package.sh

auzix-strict-display-templates:
	./scripts/stage-auzix-display-templates.sh

auzix-strict-e-assets:
	./scripts/stage-auzix-enlightenment-assets.sh

auzix-strict-desktop-assets-package:
	./scripts/build-auzix-desktop-assets-package.sh

auzix-strict-desktop-repo-packages:
	./scripts/build-auzix-desktop-repo-packages.sh

auzix-strict-user-defaults:
	./scripts/stage-auzix-user-defaults.sh

auzix-strict-kernel-modules:
	./scripts/package-auzix-kernel-modules.sh

auzix-strict-package-repo:
	./scripts/build-auzix-package-repo.sh

auzix-strict-container:
	./scripts/build-auzix-strict-container.sh

auzix-strict-pruned-test:
	./scripts/test-auzix-pruned-root.sh

auzix-strict-audit:
	./scripts/audit-auzix-strict-root.sh

auzix-strict-iso:
	./scripts/build-auzix-boot-iso.sh

clean:
	rm -rf out artifacts
