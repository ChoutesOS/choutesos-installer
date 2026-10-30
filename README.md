<p align="center">
  <img src="assets/banner.png" alt="ChoutesOS" width="100%">
</p>

<p align="center">
  <b>The graphical installer and first-boot setup for ChoutesOS.</b>
</p>

<p align="center">
  <a href="https://choutes.com"><img src="https://img.shields.io/badge/choutes.com-5B18E5?style=for-the-badge" alt="Website"></a>
  <a href="https://discord.gg/nYdsKv7Fra"><img src="https://img.shields.io/badge/Discord-5865F2?style=for-the-badge&logo=discord&logoColor=white" alt="Discord"></a>
  <img src="https://img.shields.io/badge/license-GPL--3.0-9660F8?style=for-the-badge" alt="GPL-3.0">
</p>

---

## What it does

ChoutesOS is installed in two parts, like a modern desktop operating system.

**1. The installer** runs fullscreen from the USB drive, alone on the screen (no desktop, no shortcuts).

| Step | What happens |
|---|---|
| Welcome | Introduction |
| Compatibility check | Processor, memory, storage. If the computer is not supported, installation cannot continue. |
| Disk | Choose the disk and the file system (ext4 or Btrfs) |
| Summary | Review before anything is changed |
| Install | Copies the system offline, then installs the boot loader (UEFI and BIOS) |

**2. The first-boot setup** runs fullscreen the first time the installed system starts.

| Step | What happens |
|---|---|
| Hello | Greeting in many languages |
| Language and region | Language, time zone, keyboard |
| Internet | Wi-Fi or cable. Can be skipped. |
| Account | Name, username, password, picture, computer name |
| Updates | Installs the latest ChoutesOS updates with a progress bar, restarts if needed |
| Welcome | Welcome to ChoutesOS |

When the setup ends, the installer and the temporary setup user are removed from the system.

## Try it safely

The demo mode runs the full interface as a dry run. It changes nothing on your computer.

    sudo pacman -S --needed pyside6 qt6-declarative
    python -m choutesos_installer --demo           # installer
    python -m choutesos_installer --demo --setup   # first-boot setup

Run the tests:

    python -m unittest discover -s tests

## Layout

| Path | Purpose |
|---|---|
| `choutesos_installer/backend.py` | Installation logic (no Qt, unit tested) |
| `choutesos_installer/requirements.py` | Compatibility check |
| `choutesos_installer/oobe.py`, `oobe_helper.py` | First-boot setup (user side and root helper) |
| `choutesos_installer/qml/` | The user interface |
| `bin/` | Launchers, the kiosk session and the root helper |

## Support

Website [choutes.com](https://choutes.com) · Wiki [wiki.choutes.com](https://wiki.choutes.com) · Discord [discord.gg/nYdsKv7Fra](https://discord.gg/nYdsKv7Fra) · wafiq@choutes.com

## License

Released under the [GPL-3.0](LICENSE) license.
