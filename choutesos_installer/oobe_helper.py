"""Root helper for the ChoutesOS first-boot setup.

Runs as root through sudo (see /etc/sudoers.d/90-choutesos-setup), only for the temporary
setup user, and is removed when the setup finishes. Input comes as JSON on stdin and every
value is validated here, because the caller is not trusted.

    oobe-helper region        {"locale", "timezone", "keymap"}
    oobe-helper create-user   {"username", "fullname", "password", "hostname", "autologin", "avatar"}
    oobe-helper update        streams {"percent", "label"} lines, ends with {"done", "reboot"}
    oobe-helper stage <name>  language | after-update | welcome
    oobe-helper verify
    oobe-helper reboot
    oobe-helper finish        {"autologin": bool}
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

from .backend import (EXTRA_GROUPS, HOSTNAME_RE, RESERVED_USERS, USERNAME_RE, InstallError, Runner,
                      uncomment_locales)

STATE_DIR = Path("/var/lib/choutesos/oobe")
FACES_DIR = Path("/var/lib/choutesos/faces")
AVATAR_DIR = Path("/usr/share/choutesos-installer/choutesos_installer/assets/avatars")
SETUP_HOME = Path("/home/choutesos-setup")
STAGES = ("language", "after-update", "welcome")
MAX_AVATAR_BYTES = 5 * 1024 * 1024
SETUP_USER = "choutesos-setup"

CLEANUP_PATHS = [
    "/etc/sudoers.d/90-choutesos-setup",
    "/etc/sddm.conf.d/40-choutesos-oobe.conf",
    "/usr/share/wayland-sessions/choutesos-setup.desktop",
    "/usr/share/wayland-sessions/choutesos-installer.desktop",
    "/usr/share/applications/choutesos-installer.desktop",
    "/usr/bin/choutesos-installer",
    "/usr/bin/choutesos-session",
    "/usr/share/choutesos-installer",
    "/usr/share/choutesos-setup",
    "/var/lib/choutesos/oobe",
    "/usr/lib/choutesos/oobe-helper",
]


class PacmanProgress:
    """Turns the text of `pacman -Su --noprogressbar` into (percent, label) steps."""

    DOWNLOAD = re.compile(r"^\s*\S+-[^\s]+\s+[\d.,]+\s*[KMG]i?B\s")
    INSTALL = re.compile(r"^\(\s*(\d+)/(\d+)\)\s+(checking|loading|upgrading|installing|removing|reinstalling|downgrading)\s*(.*)$")

    def __init__(self) -> None:
        self.total = 0
        self.downloaded = 0
        self.percent = 10.0

    def feed(self, text: str) -> list[tuple[float, str]]:
        steps: list[tuple[float, str]] = []
        for line in text.replace("\r", "\n").splitlines():
            line = line.rstrip()
            m = re.match(r"^Packages \((\d+)\)", line)
            if m:
                self.total = int(m.group(1))
                steps.append((self._set(12), f"Updating {self.total} packages"))
                continue
            if line.startswith(":: Retrieving packages"):
                steps.append((self._set(15), "Downloading updates"))
                continue
            if self.total and self.DOWNLOAD.match(line):
                self.downloaded += 1
                steps.append((self._set(15 + 35 * min(self.downloaded / self.total, 1)), "Downloading updates"))
                continue
            m = self.INSTALL.match(line)
            if m:
                i, n, verb, rest = int(m.group(1)), int(m.group(2)), m.group(3), m.group(4)
                if verb in ("checking", "loading"):
                    steps.append((self._set(50), "Verifying updates"))
                else:
                    name = rest.split()[0] if rest.split() else ""
                    steps.append((self._set(52 + 46 * (i / max(n, 1))), f"Installing {name}".strip()))
        return steps

    def _set(self, value: float) -> float:
        self.percent = max(self.percent, min(value, 99.0))
        return self.percent


def validate_account(data: dict) -> list[str]:
    errors = []
    username = str(data.get("username", ""))
    if not USERNAME_RE.match(username) or username in RESERVED_USERS or username == SETUP_USER:
        errors.append("Invalid username.")
    password = str(data.get("password", ""))
    if not password or "\n" in password:
        errors.append("Invalid password.")
    fullname = str(data.get("fullname", ""))
    if ":" in fullname or "\n" in fullname or len(fullname) > 60:
        errors.append("Invalid name.")
    if not HOSTNAME_RE.match(str(data.get("hostname", "choutesos"))):
        errors.append("Invalid computer name.")
    return errors


def avatar_ok(path: str) -> bool:
    """Only the bundled avatars or a photo the setup user placed in its own home."""
    if not path:
        return False
    try:
        p = Path(path).resolve()
    except OSError:
        return False
    if not (p.is_relative_to(AVATAR_DIR.resolve()) or p.is_relative_to(SETUP_HOME.resolve())):
        return False
    try:
        if not p.is_file() or p.stat().st_size > MAX_AVATAR_BYTES:
            return False
        head = p.read_bytes()[:4]
    except OSError:
        return False
    return head.startswith(b"\x89PNG") or head.startswith(b"\xff\xd8")


class Helper:
    def __init__(self, dry_run: bool = False, log=print):
        self.dry = dry_run
        self.log = log
        self.r = Runner(dry_run, log)

    # -- small helpers ---------------------------------------------------
    def write(self, path: str, content: str, mode: int = 0o644) -> None:
        self.log(f"write {path}")
        if self.dry:
            return
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        Path(path).write_text(content)
        os.chmod(path, mode)

    def read(self, path: str) -> str:
        try:
            return Path(path).read_text()
        except OSError:
            return ""

    def group_exists(self, name: str) -> bool:
        return self.dry or re.search(rf"^{name}:", self.read("/etc/group"), re.M) is not None

    # -- commands --------------------------------------------------------
    def region(self, data: dict) -> None:
        locale, tz, keymap = str(data.get("locale", "")), str(data.get("timezone", "")), str(data.get("keymap", ""))
        if not re.match(r"^[A-Za-z_]+\.[A-Za-z0-9-]+$", locale) or not re.match(r"^[A-Za-z0-9_.-]+$", keymap):
            raise InstallError("Invalid language or keyboard.")
        if ".." in tz or not (self.dry or Path("/usr/share/zoneinfo", tz).is_file()):
            raise InstallError("Unknown time zone.")
        self.write("/etc/locale.gen", uncomment_locales(self.read("/etc/locale.gen"), [locale, "en_US.UTF-8"]))
        self.r.run(["locale-gen"])
        self.write("/etc/locale.conf", f"LANG={locale}\n")
        self.write("/etc/vconsole.conf", f"KEYMAP={keymap}\n")
        self.r.run(["ln", "-sf", f"/usr/share/zoneinfo/{tz}", "/etc/localtime"])
        self.r.run(["hwclock", "--systohc"], check=False)

    def create_user(self, data: dict) -> None:
        errors = validate_account(data)
        if errors:
            raise InstallError(" ".join(errors))
        user, name, host = data["username"], str(data.get("fullname", "")), str(data.get("hostname") or "choutesos")
        groups = [g for g in EXTRA_GROUPS if self.group_exists(g)]
        cmd = ["useradd", "-m", "-s", "/bin/zsh", "-G", ",".join(groups)]
        if name:
            cmd += ["-c", name]
        self.r.run(cmd + [user])
        self.r.run(["chpasswd"], input=f"{user}:{data['password']}\n", secret=True)
        self.write("/etc/sudoers.d/10-wheel", "%wheel ALL=(ALL:ALL) ALL\n", 0o440)
        self.write("/etc/hostname", host + "\n")
        self.write("/etc/hosts", f"127.0.0.1 localhost\n::1 localhost\n127.0.1.1 {host}\n")
        self.r.run(["hostnamectl", "set-hostname", host], check=False)
        avatar = str(data.get("avatar", ""))
        if avatar and (self.dry or avatar_ok(avatar)):
            self.r.run(["install", "-d", "-m", "755", str(FACES_DIR)])
            self.r.run(["install", "-m", "644", avatar, f"{FACES_DIR}/{user}.face.icon"])
            self.r.run(["install", "-m", "644", "-o", user, "-g", user, avatar, f"/home/{user}/.face"], check=False)
        self.write(str(STATE_DIR / "account.json"), json.dumps({"username": user}))

    def update(self, emit) -> None:
        """Runs a full system update and reports progress through emit(percent, label)."""
        emit(2, "Looking for updates")
        self.r.run(["pacman", "-Sy", "--noconfirm", "--noprogressbar"])
        emit(8, "Looking for updates")
        pending = self.r.run(["pacman", "-Qu"], check=False)
        names = [line.split()[0] for line in pending.splitlines() if line.strip()]
        if not names and not self.dry:
            emit(100, "Your system is up to date")
            return
        kernel = ""
        pkgbase = Path(f"/usr/lib/modules/{os.uname().release}/pkgbase")
        if pkgbase.exists():
            kernel = pkgbase.read_text().strip()
        progress = PacmanProgress()
        self.r.stream(["pacman", "-Su", "--noconfirm", "--noprogressbar"],
                      lambda chunk: [emit(p, label) for p, label in progress.feed(chunk)])
        emit(100, "Updates installed")
        self.reboot_needed = bool(kernel) and kernel in names

    reboot_needed = False

    def set_stage(self, name: str) -> None:
        if name not in STAGES:
            raise InstallError("Unknown stage.")
        self.write(str(STATE_DIR / "stage"), name + "\n")

    def verify(self) -> dict:
        self.r.run(["pacman", "-Dkq"], check=False)
        return {"ok": True}

    def reboot(self) -> None:
        self.r.run(["systemctl", "reboot"])

    def finish(self, data: dict) -> None:
        """Removes the setup user and every installer file, then shows the login screen."""
        user = ""
        try:
            user = json.loads(self.read(str(STATE_DIR / "account.json"))).get("username", "")
        except ValueError:
            pass
        if data.get("autologin") and USERNAME_RE.match(user):
            self.write("/etc/sddm.conf.d/30-autologin.conf", f"[Autologin]\nUser={user}\nSession=hyprland\n")
        script = " ; ".join(
            ["systemctl stop sddm", f"userdel -rf {SETUP_USER}"]
            + [f"rm -rf {p}" for p in CLEANUP_PATHS]
            + ["systemctl start sddm"])
        self.r.run(["systemd-run", "--no-block", "--on-active=2s", "/bin/sh", "-c", script])


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    if os.geteuid() != 0 and not os.environ.get("CHOUTESOS_DRY_RUN"):
        print("must run as root", file=sys.stderr)
        return 2
    helper = Helper(dry_run=bool(os.environ.get("CHOUTESOS_DRY_RUN")), log=lambda s: print(s, file=sys.stderr))
    cmd = argv[1]
    try:
        data = json.loads(sys.stdin.read() or "{}") if cmd in ("region", "create-user", "finish") else {}
        if cmd == "region":
            helper.region(data)
        elif cmd == "create-user":
            helper.create_user(data)
        elif cmd == "update":
            def emit(percent: float, label: str) -> None:
                print(json.dumps({"percent": round(percent, 1), "label": label}), flush=True)
            helper.update(emit)
            print(json.dumps({"done": True, "reboot": helper.reboot_needed}), flush=True)
        elif cmd == "stage" and len(argv) > 2:
            helper.set_stage(argv[2])
        elif cmd == "verify":
            print(json.dumps(helper.verify()))
        elif cmd == "reboot":
            helper.reboot()
        elif cmd == "finish":
            helper.finish(data)
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except InstallError as exc:
        print(json.dumps({"error": str(exc)}), flush=True)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
