"""Checks whether this computer can run ChoutesOS before anything is installed."""
from __future__ import annotations

import platform
from pathlib import Path

# x86-64-v2: the baseline the ChoutesOS kernel is built for (CPUs from about 2009 on).
# /proc/cpuinfo names: pni = SSE3.
V2_FLAGS = ("cx16", "lahf_lm", "popcnt", "pni", "ssse3", "sse4_1", "sse4_2")
MIN_RAM_GIB = 3.0        # a "4 GB" computer reports about 3.7 GiB
RECOMMENDED_RAM_GIB = 7.5
MIN_DISK_GB = 30


def parse_cpu_flags(cpuinfo: str) -> set[str]:
    for line in cpuinfo.splitlines():
        if line.startswith("flags"):
            return set(line.split(":", 1)[1].split())
    return set()


def parse_meminfo_gib(meminfo: str) -> float:
    for line in meminfo.splitlines():
        if line.startswith("MemTotal:"):
            return int(line.split()[1]) / 1024 / 1024
    return 0.0


def check_architecture(machine: str) -> dict:
    ok = machine == "x86_64"
    return {"id": "arch", "title": "64-bit processor",
            "detail": "x86-64" if ok else f"Unsupported architecture: {machine}",
            "status": "ok" if ok else "fail"}


def check_cpu(flags: set[str]) -> dict:
    missing = [f for f in V2_FLAGS if f not in flags]
    if missing:
        return {"id": "cpu", "title": "Processor features",
                "detail": "This processor is too old. It lacks: " + ", ".join(missing),
                "status": "fail"}
    return {"id": "cpu", "title": "Processor features", "detail": "Supported (x86-64-v2 or newer)", "status": "ok"}


def check_ram(gib: float) -> dict:
    text = f"{gib:.1f} GiB"
    if gib < MIN_RAM_GIB:
        return {"id": "ram", "title": "Memory", "detail": f"{text}. ChoutesOS needs at least 4 GB.", "status": "fail"}
    if gib < RECOMMENDED_RAM_GIB:
        return {"id": "ram", "title": "Memory", "detail": f"{text}. 8 GB or more is recommended for gaming.", "status": "warn"}
    return {"id": "ram", "title": "Memory", "detail": text, "status": "ok"}


def check_disks(disks: list[dict]) -> dict:
    big = [d for d in disks if d.get("sizeGb", 0) >= MIN_DISK_GB]
    if not big:
        return {"id": "disk", "title": "Storage",
                "detail": f"No disk with at least {MIN_DISK_GB} GB was found.", "status": "fail"}
    best = max(d["sizeGb"] for d in big)
    return {"id": "disk", "title": "Storage", "detail": f"{len(big)} suitable disk(s), up to {best} GB", "status": "ok"}


def check_firmware(uefi: bool) -> dict:
    return {"id": "boot", "title": "Boot mode", "detail": "UEFI" if uefi else "Legacy BIOS", "status": "ok"}


def run_checks(disks: list[dict], cpuinfo_path: str = "/proc/cpuinfo", meminfo_path: str = "/proc/meminfo",
               machine: str | None = None, uefi: bool | None = None) -> list[dict]:
    def read(path: str) -> str:
        try:
            return Path(path).read_text(errors="ignore")
        except OSError:
            return ""

    return [
        check_architecture(machine or platform.machine()),
        check_cpu(parse_cpu_flags(read(cpuinfo_path))),
        check_ram(parse_meminfo_gib(read(meminfo_path))),
        check_disks(disks),
        check_firmware(Path("/sys/firmware/efi").exists() if uefi is None else uefi),
    ]


def can_install(checks: list[dict]) -> bool:
    return all(c["status"] != "fail" for c in checks)
