"""First-boot setup helpers that run as the temporary setup user (no root needed)."""
from __future__ import annotations

import subprocess
from pathlib import Path

AVATAR_DIR = Path(__file__).parent / "assets" / "avatars"
STAGE_FILE = Path("/var/lib/choutesos/oobe/stage")
STAGES = ("language", "after-update", "welcome")


def read_stage() -> str:
    try:
        stage = STAGE_FILE.read_text().strip()
    except OSError:
        return "language"
    return stage if stage in STAGES else "language"


def _split_terse(line: str) -> list[str]:
    """Splits one line of `nmcli -t` output; a literal colon is written as \\:."""
    parts, cur, i = [], "", 0
    while i < len(line):
        ch = line[i]
        if ch == "\\" and i + 1 < len(line):
            cur += line[i + 1]
            i += 2
            continue
        if ch == ":":
            parts.append(cur)
            cur = ""
        else:
            cur += ch
        i += 1
    parts.append(cur)
    return parts


def parse_wifi(text: str) -> list[dict]:
    """Output of: nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list"""
    seen: dict[str, dict] = {}
    for line in text.splitlines():
        parts = _split_terse(line)
        if len(parts) < 4 or not parts[1]:
            continue
        in_use, ssid, signal, security = parts[0] == "*", parts[1], int(parts[2] or 0), parts[3]
        entry = {"ssid": ssid, "signal": signal, "secure": security not in ("", "--"), "connected": in_use}
        if ssid not in seen or signal > seen[ssid]["signal"]:
            seen[ssid] = entry
    return sorted(seen.values(), key=lambda e: (not e["connected"], -e["signal"]))


def parse_ethernet(text: str) -> bool:
    """Output of: nmcli -t -f TYPE,STATE dev"""
    return any(line.strip() == "ethernet:connected" for line in text.splitlines())


def _nmcli(args: list[str], input: str | None = None, sudo: bool = False, timeout: int = 40) -> subprocess.CompletedProcess:
    cmd = (["sudo", "-n"] if sudo else []) + ["nmcli"] + args
    try:
        return subprocess.run(cmd, input=input, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return subprocess.CompletedProcess(cmd, 1, "", str(exc))


def list_wifi() -> list[dict]:
    out = _nmcli(["-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "--rescan", "auto"])
    return parse_wifi(out.stdout) if out.returncode == 0 else []


def internet_state() -> dict:
    eth = _nmcli(["-t", "-f", "TYPE,STATE", "dev"])
    conn = _nmcli(["-t", "networking", "connectivity", "check"])
    return {"ethernet": parse_ethernet(eth.stdout), "online": conn.stdout.strip() == "full"}


def connect_wifi(ssid: str, password: str) -> tuple[bool, str]:
    if not ssid or "\n" in ssid:
        return False, "Invalid network name."
    out = _nmcli(["--ask", "dev", "wifi", "connect", ssid], input=(password + "\n") if password else "\n", sudo=True, timeout=60)
    if out.returncode == 0:
        return True, ""
    return False, (out.stderr or out.stdout).strip().splitlines()[-1] if (out.stderr or out.stdout).strip() else "Could not connect."


def list_avatars() -> list[dict]:
    if not AVATAR_DIR.exists():
        return []
    return [{"path": str(p), "name": p.stem} for p in sorted(AVATAR_DIR.glob("*.png"))]
