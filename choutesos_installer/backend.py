"""ChoutesOS installer backend.

Pure Python, no Qt. Every system change goes through `Runner`, so a dry run
(`dry_run=True`) logs the commands without touching anything.

The installed system is a copy of the live system's pristine root image
(/run/archiso/airootfs), so installation works fully offline.
"""
from __future__ import annotations

import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

LIVE_ROOT = Path("/run/archiso/airootfs")
BOOT_MNT = Path("/run/archiso/bootmnt")
TARGET = Path("/mnt")
OVERLAY_DIR = Path("/usr/share/choutesos-installer/target-overlay")

USERNAME_RE = re.compile(r"^[a-z_][a-z0-9_-]{0,31}$")
HOSTNAME_RE = re.compile(r"^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$")
RESERVED_USERS = {"root", "daemon", "bin", "sys", "nobody", "live", "sddm", "git", "http", "mail"}

LIVE_ONLY_FILES = [
    "/etc/sysusers.d/choutesos-live.conf",
    "/etc/tmpfiles.d/choutesos-live.conf",
    "/etc/sudoers.d/10-live",
    "/etc/sddm.conf.d/20-live-autologin.conf",
    "/etc/mkinitcpio.conf.d/archiso.conf",
    "/etc/systemd/system/getty@tty1.service.d/autologin.conf",
    "/etc/systemd/system/pacman-init.service",
    "/etc/systemd/system/choose-mirror.service",
    "/etc/systemd/system/etc-pacman.d-gnupg.mount",
    "/etc/systemd/system/livecd-talk.service",
    "/etc/motd",
    "/root/.zlogin",
    "/root/.automated_script.sh",
]

SERVICES = [
    "NetworkManager.service",
    "bluetooth.service",
    "sddm.service",
    "power-profiles-daemon.service",
    "fstrim.timer",
    "systemd-timesyncd.service",
]

EXTRA_GROUPS = ["wheel", "video", "audio", "input", "storage", "optical", "power", "network", "gamemode"]


def part_path(disk: str, number: int) -> str:
    """/dev/sda -> /dev/sda1, /dev/nvme0n1 -> /dev/nvme0n1p1."""
    return f"{disk}p{number}" if disk[-1].isdigit() else f"{disk}{number}"


def uncomment_locales(text: str, locales: list[str]) -> str:
    """Enable the given locales (e.g. 'en_US.UTF-8') in the contents of /etc/locale.gen."""
    out = []
    for line in text.splitlines():
        stripped = line.lstrip("#").strip()
        if line.startswith("#") and any(stripped.startswith(f"{loc} ") or stripped == loc for loc in locales):
            line = stripped
        out.append(line)
    return "\n".join(out) + "\n"


@dataclass
class Config:
    disk: str = ""
    filesystem: str = "ext4"          # ext4 | btrfs
    hostname: str = "choutesos"
    username: str = ""
    fullname: str = ""
    password: str = ""
    autologin: bool = False
    timezone: str = "UTC"
    locale: str = "en_US.UTF-8"
    keymap: str = "us"

    @classmethod
    def from_dict(cls, data: dict) -> "Config":
        known = {k: v for k, v in data.items() if k in cls.__dataclass_fields__}
        return cls(**known)

    def validate(self, check_paths: bool = True) -> list[str]:
        errors: list[str] = []
        if not self.disk.startswith("/dev/"):
            errors.append("Choose a disk to install to.")
        if self.filesystem not in ("ext4", "btrfs"):
            errors.append("Unsupported file system.")
        if not USERNAME_RE.match(self.username) or self.username in RESERVED_USERS:
            errors.append("The username must start with a lowercase letter and use only a-z, 0-9, _ or -.")
        if not self.password:
            errors.append("Choose a password.")
        if not HOSTNAME_RE.match(self.hostname):
            errors.append("The computer name may only contain letters, digits and hyphens.")
        if check_paths and not Path("/usr/share/zoneinfo", self.timezone).exists():
            errors.append("Unknown time zone.")
        if not re.match(r"^[A-Za-z_]+\.[A-Za-z0-9-]+$", self.locale):
            errors.append("Invalid language setting.")
        if not re.match(r"^[A-Za-z0-9_.-]+$", self.keymap):
            errors.append("Invalid keyboard layout.")
        if ":" in self.fullname or "\n" in self.fullname:
            errors.append("The full name contains invalid characters.")
        return errors


class InstallError(RuntimeError):
    pass


class Runner:
    """Runs commands (through sudo when not root). In dry-run mode only logs them."""

    def __init__(self, dry_run: bool, log: Callable[[str], None]):
        self.dry_run = dry_run
        self.log = log
        self.sudo = [] if (os.geteuid() == 0 or dry_run) else ["sudo", "-n"]
        self.history: list[list[str]] = []

    def run(self, cmd: list[str], *, input: str | None = None, check: bool = True,
            chroot: bool = False, secret: bool = False) -> str:
        full = (["arch-chroot", str(TARGET)] if chroot else []) + cmd
        self.history.append(full)
        self.log("$ " + " ".join(full) + (" <secret>" if secret else ""))
        if self.dry_run:
            return ""
        proc = subprocess.run(self.sudo + full, input=input, capture_output=True, text=True)
        if proc.returncode != 0 and check:
            detail = (proc.stderr or proc.stdout or "").strip()[-600:]
            raise InstallError(f"Command failed ({proc.returncode}): {' '.join(full)}\n{detail}")
        return proc.stdout

    def stream(self, cmd: list[str], on_chunk: Callable[[str], None]) -> None:
        self.history.append(cmd)
        self.log("$ " + " ".join(cmd))
        if self.dry_run:
            return
        proc = subprocess.Popen(self.sudo + cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        assert proc.stdout is not None
        fd = proc.stdout.fileno()
        tail = ""
        while True:
            data = os.read(fd, 4096)
            if not data:
                break
            text = data.decode("utf-8", "replace")
            tail = (tail + text)[-800:]
            on_chunk(text)
        if proc.wait() != 0:
            raise InstallError(f"Command failed ({proc.returncode}): {' '.join(cmd)}\n{tail[-400:]}")


class Installer:
    def __init__(self, cfg: Config, dry_run: bool = False,
                 progress: Callable[[float, str], None] | None = None,
                 log: Callable[[str], None] | None = None):
        self.cfg = cfg
        self.progress = progress or (lambda p, s: None)
        self.log = log or (lambda s: None)
        self.r = Runner(dry_run, self.log)
        self.dry_run = dry_run
        self.uefi = Path("/sys/firmware/efi").exists()
        self.esp = ""
        self.root_dev = ""
        self.steps = [
            ("Preparing the disk", 4, self.step_partition),
            ("Formatting", 3, self.step_format),
            ("Copying the system", 62, self.step_copy),
            ("Configuring the system", 18, self.step_configure),
            ("Setting up the boot loader", 10, self.step_bootloader),
            ("Finishing", 3, self.step_finish),
        ]

    # -- helpers ---------------------------------------------------------
    def t(self, path: str) -> str:
        return str(TARGET) + path

    def write(self, path: str, content: str, mode: str = "644") -> None:
        self.r.run(["tee", self.t(path)], input=content)
        self.r.run(["chmod", mode, self.t(path)])

    def read(self, path: str) -> str:
        if self.dry_run:
            return ""
        try:
            return self.r.run(["cat", self.t(path)], check=False)
        except InstallError:
            return ""

    def target_exists(self, path: str) -> bool:
        return Path(self.t(path)).exists() if not self.dry_run else True

    # -- run -------------------------------------------------------------
    def run(self) -> None:
        errors = self.cfg.validate(check_paths=not self.dry_run)
        if errors:
            raise InstallError("\n".join(errors))
        total = sum(w for _, w, _ in self.steps)
        done = 0.0
        self.base = 0.0
        for label, weight, fn in self.steps:
            self.base, self.weight, self.total = done, weight, total
            self.progress(done / total * 100, label)
            fn()
            done += weight
        self.progress(100.0, "Installation complete")

    def sub(self, fraction: float) -> None:
        self.progress((self.base + self.weight * min(max(fraction, 0), 1)) / self.total * 100, "Copying the system")

    # -- steps -----------------------------------------------------------
    def step_partition(self) -> None:
        d, r = self.cfg.disk, self.r
        r.run(["swapoff", "-a"], check=False)
        r.run(["umount", "-R", str(TARGET)], check=False)
        mounts = r.run(["lsblk", "-nrpo", "MOUNTPOINT", d], check=False).split()
        for mp in sorted((m for m in mounts if m.startswith("/")), key=len, reverse=True):
            r.run(["umount", "-R", mp], check=False)
        r.run(["wipefs", "-af", d])
        r.run(["sgdisk", "--zap-all", d])
        if self.uefi:
            r.run(["sgdisk", "-n1:0:+1G", "-t1:ef00", "-c1:EFI", "-n2:0:0", "-t2:8300", "-c2:ChoutesOS", d])
            self.esp, self.root_dev = part_path(d, 1), part_path(d, 2)
        else:
            r.run(["sgdisk", "-n1:0:+1M", "-t1:ef02", "-c1:BIOS", "-n2:0:0", "-t2:8300", "-c2:ChoutesOS", d])
            self.root_dev = part_path(d, 2)
        r.run(["partprobe", d], check=False)
        r.run(["udevadm", "settle"], check=False)

    def step_format(self) -> None:
        r, fs = self.r, self.cfg.filesystem
        if self.uefi:
            r.run(["mkfs.fat", "-F32", "-n", "EFI", self.esp])
        if fs == "btrfs":
            r.run(["mkfs.btrfs", "-f", "-L", "ChoutesOS", self.root_dev])
            r.run(["mount", self.root_dev, str(TARGET)])
            r.run(["btrfs", "subvolume", "create", self.t("/@")])
            r.run(["btrfs", "subvolume", "create", self.t("/@home")])
            r.run(["umount", str(TARGET)])
            opts = "compress=zstd,noatime"
            r.run(["mount", "-o", f"{opts},subvol=@", self.root_dev, str(TARGET)])
            r.run(["mkdir", "-p", self.t("/home")])
            r.run(["mount", "-o", f"{opts},subvol=@home", self.root_dev, self.t("/home")])
        else:
            r.run(["mkfs.ext4", "-F", "-L", "ChoutesOS", self.root_dev])
            r.run(["mount", "-o", "noatime", self.root_dev, str(TARGET)])
        if self.uefi:
            r.run(["mkdir", "-p", self.t("/boot/efi")])
            r.run(["mount", self.esp, self.t("/boot/efi")])

    def step_copy(self) -> None:
        src = LIVE_ROOT if (LIVE_ROOT.exists() or self.dry_run) else Path("/")
        cmd = ["rsync", "-aAXH", "--info=progress2", "--no-inc-recursive"]
        if src == Path("/"):
            cmd += ["--one-file-system", "--exclude=/mnt/*", "--exclude=/home/live/*"]
        cmd += [f"{src}/", f"{TARGET}/"]

        def on_chunk(text: str) -> None:
            found = re.findall(r"(\d{1,3})%", text)
            if found:
                self.sub(int(found[-1]) / 100)

        self.r.stream(cmd, on_chunk)

    def step_configure(self) -> None:
        c, r = self.cfg, self.r
        # fstab
        fstab = r.run(["genfstab", "-U", str(TARGET)])
        if not self.dry_run:
            self.write("/etc/fstab", fstab)
        # kernel and initramfs: the live initramfs is archiso-specific, so rebuild it
        r.run(["rm", "-f", self.t("/etc/mkinitcpio.conf.d/archiso.conf")])
        kernels = []
        if not self.dry_run:
            boot = Path(self.t("/boot"))
            if not list(boot.glob("vmlinuz-*")):
                for k in BOOT_MNT.glob("*/boot/x86_64/vmlinuz-*"):
                    r.run(["cp", str(k), self.t("/boot/" + k.name)])
            kernels = [p.name.removeprefix("vmlinuz-") for p in Path(self.t("/boot")).glob("vmlinuz-*")]
        else:
            kernels = ["linux"]
        for k in kernels:
            self.write(f"/etc/mkinitcpio.d/{k}.preset",
                       'ALL_config="/etc/mkinitcpio.conf"\n'
                       f'ALL_kver="/boot/vmlinuz-{k}"\n'
                       "PRESETS=('default')\n"
                       f'default_image="/boot/initramfs-{k}.img"\n')
        # files that only make sense on the live medium
        for f in LIVE_ONLY_FILES:
            r.run(["rm", "-f", self.t(f)])
        r.run(["rm", "-f", self.t("/etc/machine-id")])
        r.run(["touch", self.t("/etc/machine-id")])
        # settings that belong to the installed system only
        if OVERLAY_DIR.exists() or self.dry_run:
            r.run(["cp", "-a", f"{OVERLAY_DIR}/.", f"{TARGET}/"], check=False)
        # locale, keyboard, time zone, host
        locales = [c.locale, "en_US.UTF-8"]
        self.write("/etc/locale.gen", uncomment_locales(self.read("/etc/locale.gen"), locales))
        r.run(["locale-gen"], chroot=True)
        self.write("/etc/locale.conf", f"LANG={c.locale}\n")
        self.write("/etc/vconsole.conf", f"KEYMAP={c.keymap}\n")
        r.run(["ln", "-sf", f"/usr/share/zoneinfo/{c.timezone}", "/etc/localtime"], chroot=True)
        r.run(["hwclock", "--systohc"], chroot=True, check=False)
        self.write("/etc/hostname", c.hostname + "\n")
        self.write("/etc/hosts", f"127.0.0.1 localhost\n::1 localhost\n127.0.1.1 {c.hostname}\n")
        # accounts
        groups = [g for g in EXTRA_GROUPS if self.dry_run or re.search(rf"^{g}:", self.read("/etc/group"), re.M)]
        cmd = ["useradd", "-m", "-s", "/bin/zsh", "-G", ",".join(groups)]
        if c.fullname:
            cmd += ["-c", c.fullname]
        r.run(cmd + [c.username], chroot=True)
        r.run(["chpasswd"], input=f"{c.username}:{c.password}\n", chroot=True, secret=True)
        r.run(["passwd", "-l", "root"], chroot=True, check=False)
        self.write("/etc/sudoers.d/10-wheel", "%wheel ALL=(ALL:ALL) ALL\n", "440")
        # services
        for unit in SERVICES:
            if self.dry_run or self.target_exists(f"/usr/lib/systemd/system/{unit}"):
                r.run(["systemctl", "enable", unit], chroot=True, check=False)
        r.run(["systemctl", "set-default", "graphical.target"], chroot=True, check=False)
        r.run(["find", "/etc/systemd/system", "-xtype", "l", "-delete"], chroot=True, check=False)
        if c.autologin:
            self.write("/etc/sddm.conf.d/30-autologin.conf",
                       f"[Autologin]\nUser={c.username}\nSession=hyprland\n")
        # package signing keys
        r.run(["pacman-key", "--init"], chroot=True, check=False)
        r.run(["pacman-key", "--populate"], chroot=True, check=False)
        # rebuild the initramfs
        r.run(["mkinitcpio", "-P"], chroot=True)

    def step_bootloader(self) -> None:
        r = self.r
        grub = self.read("/etc/default/grub")
        if grub or self.dry_run:
            grub = re.sub(r'^#?GRUB_DISTRIBUTOR=.*$', 'GRUB_DISTRIBUTOR="ChoutesOS"', grub, flags=re.M)
            grub = re.sub(r'^GRUB_CMDLINE_LINUX_DEFAULT=.*$', 'GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3"', grub, flags=re.M)
            grub = re.sub(r'^#?GRUB_DISABLE_OS_PROBER=.*$', 'GRUB_DISABLE_OS_PROBER=false', grub, flags=re.M)
            if "GRUB_DISABLE_OS_PROBER" not in grub:
                grub += "\nGRUB_DISABLE_OS_PROBER=false\n"
            self.write("/etc/default/grub", grub)
        if self.uefi:
            r.run(["grub-install", "--target=x86_64-efi", "--efi-directory=/boot/efi",
                   "--bootloader-id=ChoutesOS", "--recheck"], chroot=True)
            r.run(["grub-install", "--target=x86_64-efi", "--efi-directory=/boot/efi",
                   "--removable", "--recheck"], chroot=True, check=False)
        else:
            r.run(["grub-install", "--target=i386-pc", "--recheck", self.cfg.disk], chroot=True)
        r.run(["grub-mkconfig", "-o", "/boot/grub/grub.cfg"], chroot=True)

    def step_finish(self) -> None:
        self.r.run(["sync"])
        self.r.run(["umount", "-R", str(TARGET)], check=False)
