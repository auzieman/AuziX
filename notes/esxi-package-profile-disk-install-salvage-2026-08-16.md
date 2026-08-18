# ESXi package-profile disk install salvage boundary — 2026-08-16

Context: ESXi VM `auzix-esxi-workstation-media-01` / VMID 13 installed from the
new repo-profile disk installer while booted from the AUZiX live ISO.

What worked:

- package-profile backend installed a real workstation-ish root from the repo:
  - 758 package receipts
  - 13 missing package-contract entries logged
  - `/`, `/Home`, `/Work` partitions created on `/dev/sda`
- GRUB installed without reporting an error.
- After VM firmware was switched from EFI to BIOS, the disk boot path found media.
- After grub args changed from `root=LABEL=AUZIXROOT auzix.root=LABEL=AUZIXROOT`
  to `auzix.root=/dev/sda1`, the initramfs mounted `/dev/sda1`.
- After copying live ISO boot payload, `/boot/vmlinuz` and
  `/boot/initramfs.cpio.gz` exist on the installed root.
- After copying `StartSequence` and `auzix-paths.sh` into the installed root and
  replacing `/init` with the installed-init template from `add-auzix-live-tools.sh`,
  serial log showed `StartSequence` ran and DHCP configured `eth0` as
  `10.20.0.113/24`.

What still did not work:

- SSH was still refused after StartSequence completed.
- The installed disk path did not become a usable installed workstation.
- Service/app/runtime state remained incomplete because the repo-profile disk
  installer did not reuse the ISO builder's full root-prep/configure flow.

Important lesson:

Do not maintain a separate clever disk-install path.  The disk installer should
reuse the same AUZiX root assembly/runtime contract as the ISO builder:

1. mount target root/Home/Work
2. install package/profile payloads
3. tar/rsync the proven live toolkit/root-prep fragments into target
4. run the same pre/post/custom scripts against the mounted target
5. install `StartSequence`, `InstalledInit`, paths, CA links, users/groups,
   service state, host keys, menus, E state, and package receipts from shared
   code
6. generate/copy installed-root initramfs and boot assets
7. detect firmware:
   - EFI: create/use ESP and install EFI GRUB
   - BIOS: install MBR GRUB
8. validate HTTPS/CA, SSH, package receipts, and boot files before reboot

CA rule:

Never repeat the live-only CA fix pattern. CA bundle/links must come from the
shared install contract and be validated by HTTPS probe on the installed target.

Current missing package-contract entries from the run:

- UtilLinux
- E2fsprogs
- Dosfstools
- Parted
- ContainersCommon
- Conmon
- Crun
- Netavark
- AardvarkDNS
- Podman
- AbiWord
- Gnumeric
- Galculator
