"""Reads disks, languages, time zones and keyboard layouts from the running system."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

LANGUAGES = [
    ("English", "en_US.UTF-8"),
    ("Bahasa Melayu", "ms_MY.UTF-8"),
    ("Bahasa Indonesia", "id_ID.UTF-8"),
    ("Deutsch", "de_DE.UTF-8"),
    ("Español", "es_ES.UTF-8"),
    ("Français", "fr_FR.UTF-8"),
    ("Italiano", "it_IT.UTF-8"),
    ("Português (Brasil)", "pt_BR.UTF-8"),
    ("Polski", "pl_PL.UTF-8"),
    ("Türkçe", "tr_TR.UTF-8"),
    ("Русский", "ru_RU.UTF-8"),
    ("日本語", "ja_JP.UTF-8"),
    ("한국어", "ko_KR.UTF-8"),
    ("简体中文", "zh_CN.UTF-8"),
    ("हिन्दी", "hi_IN.UTF-8"),
]

COMMON_KEYMAPS = ["us", "uk", "de", "fr", "es", "it", "pt-latin1", "br-abnt2", "ru", "tr", "pl2", "jp106", "dvorak"]


def parse_disks(lsblk_json: str) -> list[dict]:
    """Turns `lsblk -J -b` output into a list of installable disks (the live medium is excluded)."""
    data = json.loads(lsblk_json)
    disks = []
    for dev in data.get("blockdevices", []):
        if dev.get("type") != "disk":
            continue
        size = int(dev.get("size") or 0)
        if size < 8 * 1024**3:
            continue

        def mountpoints(node: dict) -> list[str]:
            found = [m for m in (node.get("mountpoints") or []) if m]
            for child in node.get("children") or []:
                found += mountpoints(child)
            return found

        if any(m.startswith("/run/archiso") for m in mountpoints(dev)):
            continue
        disks.append({
            "path": dev["path"],
            "model": (dev.get("model") or "Unknown disk").strip(),
            "sizeGb": round(size / 1000**3),
            "removable": bool(dev.get("rm")),
            "transport": dev.get("tran") or "",
        })
    return disks


def list_disks() -> list[dict]:
    try:
        out = subprocess.run(
            ["lsblk", "-J", "-b", "-p", "-o", "NAME,PATH,SIZE,MODEL,TYPE,RM,TRAN,MOUNTPOINTS"],
            capture_output=True, text=True, check=True).stdout
        return parse_disks(out)
    except (OSError, subprocess.CalledProcessError, ValueError):
        return []


def list_languages() -> list[dict]:
    return [{"label": name, "value": loc} for name, loc in LANGUAGES]


def _read_countries() -> dict[str, str]:
    names: dict[str, str] = {}
    table = Path("/usr/share/zoneinfo/iso3166.tab")
    if table.exists():
        for line in table.read_text(errors="ignore").splitlines():
            if line and not line.startswith("#") and "\t" in line:
                code, name = line.split("\t", 1)
                names[code] = name.strip()
    return names


def parse_zone_tab(text: str, countries: dict[str, str]) -> list[dict]:
    """zone.tab lists one entry per country and city (zone1970.tab merges e.g. Kuala Lumpur into Singapore)."""
    zones = [{"label": "UTC", "value": "UTC"}]
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        code, tz = parts[0], parts[2]
        city = tz.split("/")[-1].replace("_", " ")
        country = countries.get(code, code)
        zones.append({"label": f"{city}, {country}", "value": tz})
    return sorted(zones, key=lambda z: z["label"])


def list_timezones() -> list[dict]:
    table = Path("/usr/share/zoneinfo/zone.tab")
    if table.exists():
        return parse_zone_tab(table.read_text(errors="ignore"), _read_countries())
    return [{"label": z.replace("_", " "), "value": z} for z in
            ("UTC", "Asia/Kuala_Lumpur", "Asia/Singapore", "Europe/London", "America/New_York", "Asia/Tokyo")]


def list_keymaps() -> list[dict]:
    try:
        out = subprocess.run(["localectl", "list-keymaps", "--no-pager"],
                             capture_output=True, text=True, check=True).stdout.split()
        maps = sorted(set(out))
    except (OSError, subprocess.CalledProcessError):
        maps = []
    if not maps:
        maps = COMMON_KEYMAPS
    first = [m for m in COMMON_KEYMAPS if m in maps]
    rest = [m for m in maps if m not in first]
    return [{"label": m, "value": m} for m in first + rest]
