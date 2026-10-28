<p align="center">
  <img src="assets/banner.png" alt="ChoutesOS" width="100%">
</p>

<p align="center">
  <b>The offline graphical installer for ChoutesOS.</b>
</p>

---

## About

A modern installer written in Python and Qt 6 (QML). It works fully offline: it copies the live system to disk, configures it and installs GRUB (UEFI and BIOS).

> **Status:** early development.

## Steps

1. Welcome
2. Language, time zone and keyboard layout
3. Disk and file system (ext4 or Btrfs)
4. Account
5. Summary
6. Installation

## Try it safely

The demo mode runs the full interface as a dry run. It changes nothing on your computer.

    sudo pacman -S --needed pyside6 qt6-declarative
    python -m choutesos_installer --demo

Run the tests:

    python -m unittest discover -s tests

## Layout

| Path | Purpose |
|---|---|
| `choutesos_installer/backend.py` | Installation logic (no Qt, unit tested) |
| `choutesos_installer/system_info.py` | Disks, languages, time zones, keyboards |
| `choutesos_installer/__main__.py` | Entry point and Qt controller |
| `choutesos_installer/qml/` | The user interface |
| `bin/choutesos-installer` | Launcher |

## License

Released under the [GPL-3.0](LICENSE) license.
