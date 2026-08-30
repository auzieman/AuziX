from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from ..contracts import ContractError, content_sha256

BUSYBOX = "/Programs/BusyBox/1.36.1/Commands/busybox"

START_SEQUENCE = f"""#!{BUSYBOX} sh
set -u
BB={BUSYBOX}
PATH=/System/Compatibility/sbin:/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH

mounted() {{ $BB grep -q " $1 " /proc/mounts 2>/dev/null; }}
mounted /proc || $BB mount -t proc proc /proc
mounted /sys || $BB mount -t sysfs sysfs /sys
mounted /dev || $BB mount -t devtmpfs devtmpfs /dev
$BB mkdir -p /dev/pts /dev/shm /run /sys/fs/cgroup /System/Logs
mounted /dev/pts || $BB mount -t devpts devpts /dev/pts
mounted /dev/shm || $BB mount -t tmpfs tmpfs /dev/shm
mounted /run || $BB mount -t tmpfs tmpfs /run
mounted /sys/fs/cgroup || $BB mount -t cgroup2 cgroup2 /sys/fs/cgroup 2>/dev/null || true

cat >/run/auzix-udhcpc.script <<'UDHCPC'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
BB=/Programs/BusyBox/1.36.1/Commands/busybox
case "${{1:-}}" in
  deconfig)
    $BB ifconfig "$interface" 0.0.0.0 2>/dev/null || true
    ;;
  bound|renew)
    $BB ifconfig "$interface" "$ip" netmask "$subnet" ${{broadcast:+broadcast "$broadcast"}} up
    for route in ${{router:-}}; do
      $BB route add default gw "$route" dev "$interface" 2>/dev/null || true
    done
    $BB mkdir -p /run /Network/DNS /System/Settings
    : >/run/resolv.conf
    for server in ${{dns:-}}; do echo "nameserver $server" >>/run/resolv.conf; done
    $BB cp /run/resolv.conf /Network/DNS/resolv.conf 2>/dev/null || true
    $BB ln -sfn /run/resolv.conf /System/Settings/resolv.conf 2>/dev/null || true
    echo "dhcp-lease=$interface ip=$ip router=${{router:-}} dns=${{dns:-}}"
    ;;
esac
UDHCPC
$BB chmod 0755 /run/auzix-udhcpc.script
for path in /sys/class/net/*; do
  iface=${{path##*/}}
  [ "$iface" = lo ] && continue
  $BB ip link set "$iface" up 2>/dev/null || true
  $BB udhcpc -i "$iface" -s /run/auzix-udhcpc.script -t 5 -T 3 -q -b \
    >"/System/Logs/udhcpc-$iface.log" 2>&1 || true
done

for service in /Services/*/run; do
  [ -x "$service" ] || continue
  name=${{service#/Services/}}; name=${{name%/run}}
  "$service" >"/System/Logs/$name.log" 2>&1 &
done
echo "[StartSequence] base activation complete"
"""

INSTALLED_INIT = f"""#!{BUSYBOX} sh
set -u
BB={BUSYBOX}
$BB mount -t proc proc /proc 2>/dev/null || true
$BB mount -t sysfs sysfs /sys 2>/dev/null || true
$BB mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
/System/Boot/StartSequence || true
echo "AUZiX base-netinstall rescue shell"
exec $BB setsid $BB cttyhack $BB sh
"""


def rooted(root: Path, absolute: str) -> Path:
    if not absolute.startswith("/"):
        raise ContractError(f"activation path is not absolute: {absolute}")
    return root / absolute.lstrip("/")


def write_text(root: Path, absolute: str, content: str, mode: int) -> None:
    path = rooted(root, absolute)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    path.chmod(mode)


def link(root: Path, absolute: str, target: str) -> None:
    path = rooted(root, absolute)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_dir() and not path.is_symlink():
        merge_directory(root, absolute, target)
    if path.exists() or path.is_symlink():
        path.unlink()
    path.symlink_to(target)


def relocate_directory(root: Path, source_absolute: str, target_absolute: str) -> None:
    source = rooted(root, source_absolute)
    if not source.exists():
        return
    target = rooted(root, target_absolute)
    if target.exists() or target.is_symlink():
        if source.resolve() == target.resolve():
            return
        raise ContractError(f"activation relocation target already exists: {target}")
    target.parent.mkdir(parents=True, exist_ok=True)
    source.rename(target)


def merge_directory(root: Path, source_absolute: str, target_absolute: str) -> None:
    source = rooted(root, source_absolute)
    if not source.is_dir() or source.is_symlink():
        return
    target = rooted(root, target_absolute)
    target.mkdir(parents=True, exist_ok=True)
    for child in source.iterdir():
        destination = target / child.name
        if destination.exists() or destination.is_symlink():
            raise ContractError(f"activation merge target already exists: {destination}")
        child.rename(destination)
    source.rmdir()


def adopt_apk_namespace(root: Path) -> None:
    relocate_directory(root, "/lib/apk", "/System/State/apk")
    lib = rooted(root, "/lib")
    if lib.is_dir():
        lib.rmdir()
    compatibility_lib = rooted(root, "/System/Compatibility/lib")
    compatibility_lib.mkdir(parents=True, exist_ok=True)
    apk_link = compatibility_lib / "apk"
    if not apk_link.exists() and not apk_link.is_symlink():
        apk_link.symlink_to("/System/State/apk")
    relocate_directory(root, "/etc/apk", "/System/Settings/apk")
    etc = rooted(root, "/etc")
    if etc.is_dir():
        etc.rmdir()
    merge_directory(root, "/var", "/System/State")
    merge_directory(root, "/System/State/var", "/System/State")


def publish_runtime_loader(root: Path) -> None:
    loader = rooted(root, "/System/Libraries/Runtime/glibc/ld-linux-x86-64.so.2")
    if not loader.is_file():
        raise ContractError(f"coherent runtime loader is missing: {loader}")
    compatibility_lib64 = rooted(root, "/System/Compatibility/lib64")
    compatibility_lib64.mkdir(parents=True, exist_ok=True)
    published = compatibility_lib64 / "ld-linux-x86-64.so.2"
    if published.exists() or published.is_symlink():
        published.unlink()
    published.symlink_to("/System/Libraries/Runtime/glibc/ld-linux-x86-64.so.2")
    compatibility_lib = rooted(root, "/System/Compatibility/lib")
    compatibility_lib.mkdir(parents=True, exist_ok=True)
    for soname in ("libc.so.6", "libm.so.6", "libgcc_s.so.1"):
        source = rooted(root, f"/System/Libraries/Runtime/glibc/{soname}")
        if not source.is_file():
            raise ContractError(f"coherent runtime library is missing: {source}")
        exported = compatibility_lib / soname
        if exported.exists() or exported.is_symlink():
            exported.unlink()
        exported.symlink_to(f"/System/Libraries/Runtime/glibc/{soname}")


def activate_base(root: Path, target_plan: dict[str, Any]) -> dict[str, Any]:
    root = root.resolve()
    busybox = rooted(root, BUSYBOX)
    if not busybox.is_file():
        raise ContractError(f"base activation requires package-owned BusyBox: {busybox}")
    required = [
        "/Programs/OpenSSH/host/Commands/sshd",
        "/Services/ssh/run",
        "/System/Settings/ssh/sshd_config",
        "/System/Compatibility/etc/ssl/certs/ca-certificates.crt",
    ]
    missing = [path for path in required if not rooted(root, path).exists()]
    if missing:
        raise ContractError("base activation package surfaces missing: " + ", ".join(missing))
    for absolute in ("/proc", "/sys", "/dev", "/run", "/Home", "/Work", "/System/Logs", "/System/State/ssh"):
        rooted(root, absolute).mkdir(parents=True, exist_ok=True)
    write_text(root, "/System/Boot/StartSequence", START_SEQUENCE, 0o755)
    write_text(root, "/System/Boot/InstalledInit", INSTALLED_INIT, 0o755)
    write_text(root, "/init", INSTALLED_INIT, 0o755)
    adopt_apk_namespace(root)
    publish_runtime_loader(root)
    link(root, "/lib", "/System/Compatibility/lib")
    link(root, "/lib64", "/System/Compatibility/lib64")
    link(root, "/bin", "/System/Compatibility/bin")
    link(root, "/sbin", "/System/Compatibility/sbin")
    link(root, "/usr", "/System/Compatibility/usr")
    link(root, "/etc", "/System/Settings")
    link(root, "/var", "/System/State")
    link(root, "/tmp", "/Work/Temp")
    link(root, "/home", "/Users")
    link(root, "/opt", "/Programs")
    link(root, "/root", "/Users/root")
    for settings_file in ("passwd", "group", "shadow", "shells", "nsswitch.conf", "hosts"):
        if rooted(root, f"/System/Settings/{settings_file}").exists():
            link(root, f"/System/Compatibility/etc/{settings_file}", f"/System/Settings/{settings_file}")
    ca = "/System/Compatibility/etc/ssl/certs/ca-certificates.crt"
    link(root, "/System/Compatibility/etc/ssl/cert.pem", ca)
    link(root, "/System/Settings/ssl", "/System/Compatibility/etc/ssl")
    link(root, "/System/Compatibility/usr/lib/ssl", "/System/Compatibility/etc/ssl")
    receipt = {
        "format": "auzix-activation-receipt-v1",
        "target": target_plan["target"],
        "target_plan_sha256": target_plan["content_sha256"],
        "stages": [item["id"] for item in target_plan["activation"]],
        "created": ["/System/Boot/StartSequence", "/System/Boot/InstalledInit", "/init"],
        "apk_namespace": {"database": "/System/State/apk", "configuration": "/System/Settings/apk"},
        "status": "passed",
    }
    receipt["content_sha256"] = content_sha256(receipt)
    receipt_path = rooted(root, "/System/State/install/activation-receipt.json")
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(receipt_path, 0o644)
    return receipt
