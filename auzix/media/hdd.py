from __future__ import annotations

import os
import shutil
import subprocess
import time
from contextlib import AbstractContextManager
from pathlib import Path

from ..contracts import ContractError
from ..process import run


class MountedHdd(AbstractContextManager["MountedHdd"]):
    """Create and mount only the declared HDD envelope; packages install later."""

    def __init__(self, image: Path, mount_root: Path, size: str = "8G") -> None:
        self.image = image.resolve()
        self.mount_root = mount_root.resolve()
        self.size = size
        self.loop_device: str | None = None

    def __enter__(self) -> "MountedHdd":
        if os.geteuid() != 0:
            raise ContractError("HDD envelope creation requires root")
        required = ("truncate", "losetup", "parted", "partprobe", "mkfs.ext4", "mount", "umount")
        missing = [command for command in required if not shutil.which(command)]
        if missing:
            raise ContractError("missing HDD tools: " + ", ".join(missing))
        if self.image.exists():
            raise ContractError(f"refusing to overwrite HDD image: {self.image}")
        self.image.parent.mkdir(parents=True, exist_ok=True)
        self.mount_root.mkdir(parents=True, exist_ok=True)
        try:
            run(["truncate", "-s", self.size, str(self.image)])
            completed = run(["losetup", "--find", "--show", "--partscan", str(self.image)], capture=True)
            self.loop_device = completed.stdout.strip()
            run(["parted", "-s", self.loop_device, "mklabel", "msdos"])
            run(["parted", "-s", self.loop_device, "mkpart", "primary", "ext4", "1MiB", "60%"])
            run(["parted", "-s", self.loop_device, "mkpart", "primary", "ext4", "60%", "80%"])
            run(["parted", "-s", self.loop_device, "mkpart", "primary", "ext4", "80%", "100%"])
            run(["parted", "-s", self.loop_device, "set", "1", "boot", "on"])
            run(["partprobe", self.loop_device])
            for _ in range(50):
                if Path(f"{self.loop_device}p3").is_block_device():
                    break
                time.sleep(0.1)
            else:
                raise ContractError(f"partition devices did not appear for {self.loop_device}")
            for number, label in ((1, "AUZIXROOT"), (2, "AUZIXHOME"), (3, "AUZIXWORK")):
                run(["mkfs.ext4", "-q", "-F", "-L", label, f"{self.loop_device}p{number}"])
            run(["mount", f"{self.loop_device}p1", str(self.mount_root)])
            (self.mount_root / "Home").mkdir()
            (self.mount_root / "Work").mkdir()
            run(["mount", f"{self.loop_device}p2", str(self.mount_root / "Home")])
            run(["mount", f"{self.loop_device}p3", str(self.mount_root / "Work")])
            return self
        except Exception:
            self._cleanup()
            raise

    def __exit__(self, exc_type, exc_value, traceback) -> None:
        self._cleanup()

    def _cleanup(self) -> None:
        for path in (self.mount_root / "Work", self.mount_root / "Home", self.mount_root):
            subprocess.run(["umount", str(path)], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if self.loop_device:
            subprocess.run(["losetup", "-d", self.loop_device], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.loop_device = None
