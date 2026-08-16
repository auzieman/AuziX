#!/usr/bin/env bash
set -euo pipefail

# Hard-power helper for VMID135. This intentionally avoids ACPI/qm shutdown.
# It is safe to inspect with no side effects by running:
#   scripts/vmid135-hard-boot.sh status
#
# Mutating examples:
#   scripts/vmid135-hard-boot.sh disk
#   scripts/vmid135-hard-boot.sh iso local:iso/auzix-netinstall-express-r4-vm135.iso
#
# Defaults assume the operator laptop can reach Proxmox on the LAN.

PVE_HOST="${PVE_HOST:-root@192.168.1.9}"
VMID="${VMID:-135}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)

usage() {
  cat <<'EOF'
Usage:
  scripts/vmid135-hard-boot.sh status
  scripts/vmid135-hard-boot.sh disk
  scripts/vmid135-hard-boot.sh iso STORAGE_ISO

Examples:
  scripts/vmid135-hard-boot.sh status
  scripts/vmid135-hard-boot.sh disk
  scripts/vmid135-hard-boot.sh iso local:iso/auzix-netinstall-express-r4-vm135.iso

Notes:
  - Uses hard stop/start because VMID135 ACPI is not trustworthy yet.
  - "disk" removes ide2 and boots scsi0;net0.
  - "iso" attaches the given ISO at ide2 and boots ide2;scsi0;net0.
EOF
}

remote() {
  ssh "${SSH_OPTS[@]}" "${PVE_HOST}" "$@"
}

status() {
  remote "qm status ${VMID}; qm config ${VMID} | sed -n '1,70p'"
}

hard_stop() {
  remote "
    set -e
    qm stop ${VMID} --skiplock 1 || true
    for i in \$(seq 1 30); do
      qm status ${VMID} | grep -q stopped && exit 0
      sleep 1
    done
    qm status ${VMID}
    exit 1
  "
}

case "${1:-}" in
  status)
    status
    ;;
  disk)
    hard_stop
    remote "
      set -e
      qm set ${VMID} --delete ide2 >/dev/null 2>&1 || true
      qm set ${VMID} --boot 'order=scsi0;net0'
      qm start ${VMID}
      sleep 5
      qm status ${VMID}
      qm config ${VMID} | sed -n '1,70p'
    "
    ;;
  iso)
    iso_ref="${2:-}"
    if [[ -z "${iso_ref}" ]]; then
      usage >&2
      exit 2
    fi
    hard_stop
    remote "
      set -e
      qm set ${VMID} --ide2 '${iso_ref},media=cdrom'
      qm set ${VMID} --boot 'order=ide2;scsi0;net0'
      qm start ${VMID}
      sleep 5
      qm status ${VMID}
      qm config ${VMID} | sed -n '1,70p'
    "
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

