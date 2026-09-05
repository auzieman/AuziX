#!/usr/bin/env bash
set -euo pipefail
[[ "$(hostname -s)" == r730-ai-01 || "$(hostname -s)" == lab-ai-worker ]]
image=${1:?usage: boot-auzix-alpha-pve.sh IMAGE TEST_VMID}
vmid=${2:?test VM ID required}
[[ "$vmid" =~ ^[0-9]+$ ]] && (( vmid >= 143 ))
test -s "$image"
bytes=$(stat -c %s "$image")
(( bytes > 0 && bytes % 1073741824 == 0 ))
gib=$((bytes / 1073741824))
digest=$(sha256sum "$image" | awk '{print $1}')
pve=${AUZIX_ALPHA_PVE_HOST:-root@192.168.1.9}
ssh_command=(ssh -o BatchMode=yes -o ConnectTimeout=10 "$pve")

# Reuse the explicitly designated test slots. Keep their prior disks attached
# for rollback; never stream over an existing disk. Other IDs remain new-only.
slot=scsi0
if (( vmid <= 145 )); then
  "${ssh_command[@]}" "qm config $vmid" >"$image.vm-before.conf"
  "${ssh_command[@]}" "qm status $vmid | grep -qx 'status: stopped'"
  slot=
  for number in $(seq 1 30); do
    if ! grep -q "^scsi$number:" "$image.vm-before.conf"; then slot="scsi$number"; break; fi
  done
  test -n "$slot"
  "${ssh_command[@]}" "qm set $vmid --$slot local-lvm:$gib"
else
"${ssh_command[@]}" bash -s -- "$vmid" "$gib" "$digest" <<'PVE'
set -euo pipefail
vmid=$1; gib=$2; digest=$3
test ! -e "/etc/pve/qemu-server/$vmid.conf"
test ! -e "/etc/pve/lxc/$vmid.conf"
qm create "$vmid" --name "Auzix-Alpha-Test-$vmid" --cores 4 --memory 8192 \
  --cpu host --ostype l26 --scsihw virtio-scsi-single \
  --scsi0 "local-lvm:$gib" --boot order=scsi0 \
  --net0 virtio,bridge=vmbr0 --serial0 socket --vga std \
  --description "AUZiX candidate raw image SHA256 $digest; boot validation pending"
PVE
fi
volume=$("${ssh_command[@]}" "qm config $vmid" | sed -n "s/^$slot: \\([^,]*\\).*/\\1/p")
[[ "$volume" =~ ^local-lvm:vm-$vmid-disk-[0-9]+$ ]]
device=$("${ssh_command[@]}" "pvesm path $volume")
[[ "$device" == "/dev/pve/${volume#local-lvm:}" ]]
"${ssh_command[@]}" "test -b $device; test \"\$(blockdev --getsize64 $device)\" = $bytes"
"${ssh_command[@]}" "dd of=$device bs=4M iflag=fullblock conv=fsync status=progress" <"$image"
actual=$("${ssh_command[@]}" "sha256sum $device" | awk '{print $1}')
test "$actual" = "$digest"
"${ssh_command[@]}" "set -e; qm set $vmid --boot order=$slot; qm start $vmid; qm status $vmid | grep -qx 'status: running'; qm config $vmid"
printf 'format=auzix-alpha-vm-start-v1\nvmid=%s\nimage_sha256=%s\nstatus=started-not-validated\n' \
  "$vmid" "$digest" >"$image.vm-start.receipt"
