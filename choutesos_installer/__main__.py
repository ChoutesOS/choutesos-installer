"""ChoutesOS installer entry point.

    python -m choutesos_installer            installer (fullscreen, live medium)
    python -m choutesos_installer --setup    first-boot setup (fullscreen, installed system)
    python -m choutesos_installer --demo     either one as a harmless dry run; add --setup for the setup
    python -m choutesos_installer --cli FILE install from a JSON config (add --dry-run to test)
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

from .backend import Config, InstallError, Installer

HELPER = "/usr/lib/choutesos/oobe-helper"


def run_cli(path: str, dry_run: bool) -> int:
    cfg = Config.from_dict(json.loads(Path(path).read_text()))
    installer = Installer(
        cfg, dry_run=dry_run,
        progress=lambda p, s: print(f"[{p:5.1f}%] {s}", flush=True),
        log=lambda s: print("   " + s, flush=True))
    try:
        installer.run()
    except InstallError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


def run_gui(demo: bool, setup: bool) -> int:
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    from PySide6.QtCore import QObject, QThread, QUrl, Signal, Slot
    from PySide6.QtGui import QGuiApplication, QIcon
    from PySide6.QtQml import QQmlApplicationEngine

    from . import oobe, requirements, system_info

    class InstallWorker(QThread):
        progress = Signal(float, str)
        line = Signal(str)
        done = Signal(bool, str)

        def __init__(self, cfg: Config, dry_run: bool):
            super().__init__()
            self.cfg, self.dry_run = cfg, dry_run

        def run(self) -> None:
            try:
                Installer(self.cfg, dry_run=self.dry_run,
                          progress=self.progress.emit, log=self.line.emit).run()
                self.done.emit(True, "")
            except Exception as exc:  # shown to the user in the UI
                self.done.emit(False, str(exc))

    class UpdateWorker(QThread):
        progress = Signal(float, str)
        done = Signal(bool, bool, str)   # ok, reboot needed, message

        def __init__(self, dry_run: bool):
            super().__init__()
            self.dry_run = dry_run

        def run(self) -> None:
            if self.dry_run:
                for i, label in enumerate(["Looking for updates", "Downloading updates", "Verifying updates",
                                           "Installing updates", "Installing updates"]):
                    for step in range(10):
                        self.progress.emit(i * 20 + step * 2, label)
                        time.sleep(0.12)
                self.done.emit(True, False, "")
                return
            try:
                proc = subprocess.Popen(["sudo", "-n", HELPER, "update"], stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL, text=True)
                reboot, ok = False, True
                assert proc.stdout is not None
                for line in proc.stdout:
                    try:
                        msg = json.loads(line)
                    except ValueError:
                        continue
                    if "percent" in msg:
                        self.progress.emit(float(msg["percent"]), str(msg.get("label", "")))
                    if msg.get("done"):
                        reboot = bool(msg.get("reboot"))
                if proc.wait() != 0:
                    ok = False
                self.done.emit(ok, reboot, "" if ok else "The update could not be completed.")
            except OSError as exc:
                self.done.emit(False, False, str(exc))

    class Controller(QObject):
        progressChanged = Signal(float, str)
        logLine = Signal(str)
        installFinished = Signal(bool, str)
        updateProgress = Signal(float, str)
        updateFinished = Signal(bool, bool, str)

        def __init__(self) -> None:
            super().__init__()
            self.worker = None

        # -- mode ---------------------------------------------------------
        @Slot(result=bool)
        def isDemo(self) -> bool:
            return demo

        @Slot(result=str)
        def stage(self) -> str:
            return "language" if demo else oobe.read_stage()

        # -- shared lists -------------------------------------------------
        @Slot(result="QVariantList")
        def languages(self):
            return system_info.list_languages()

        @Slot(result="QVariantList")
        def timezones(self):
            return system_info.list_timezones()

        @Slot(result="QVariantList")
        def keymaps(self):
            return system_info.list_keymaps()

        @Slot(result="QVariantList")
        def avatars(self):
            return oobe.list_avatars()

        # -- installer ----------------------------------------------------
        @Slot(result="QVariantList")
        def disks(self):
            found = system_info.list_disks(requirements.MIN_DISK_GB)
            if demo and not found:
                found = [{"path": "/dev/demo0", "model": "Demo disk", "sizeGb": 512,
                          "removable": False, "transport": "nvme"}]
            return found

        @Slot(result="QVariantList")
        def checks(self):
            disks = system_info.list_disks(8)
            found = requirements.run_checks(disks)
            if demo:
                for c in found:
                    if c["status"] == "fail":
                        c["status"], c["detail"] = "warn", c["detail"] + " (ignored in demo mode)"
            return found

        @Slot("QVariantMap", result="QVariantList")
        def validate(self, data):
            return Config.from_dict(dict(data)).validate(check_paths=not demo)

        @Slot("QVariantMap")
        def install(self, data) -> None:
            cfg = Config.from_dict(dict(data))
            self.worker = InstallWorker(cfg, dry_run=demo)
            self.worker.progress.connect(self.progressChanged)
            self.worker.line.connect(self.logLine)
            self.worker.done.connect(self.installFinished)
            self.worker.start()

        @Slot()
        def reboot(self) -> None:
            if demo:
                QGuiApplication.quit()
                return
            subprocess.Popen(["sudo", "-n", "systemctl", "reboot"])

        # -- first-boot setup ---------------------------------------------
        @Slot(result="QVariantList")
        def wifi(self):
            if demo:
                return [{"ssid": "Home Wi-Fi", "signal": 82, "secure": True, "connected": False},
                        {"ssid": "Cafe", "signal": 55, "secure": False, "connected": False}]
            return oobe.list_wifi()

        @Slot(result="QVariantMap")
        def internet(self):
            return {"ethernet": False, "online": True} if demo else oobe.internet_state()

        @Slot(str, str, result="QVariantMap")
        def connectWifi(self, ssid, password):
            ok, message = (True, "") if demo else oobe.connect_wifi(ssid, password)
            return {"ok": ok, "message": message}

        def _helper(self, args: list[str], payload: dict | None = None) -> tuple[bool, str]:
            if demo:
                return True, ""
            proc = subprocess.run(["sudo", "-n", HELPER] + args, input=json.dumps(payload or {}),
                                  capture_output=True, text=True)
            if proc.returncode == 0:
                return True, ""
            try:
                return False, json.loads(proc.stdout.strip().splitlines()[-1]).get("error", "Failed.")
            except (ValueError, IndexError):
                return False, (proc.stderr or "Failed.").strip().splitlines()[-1]

        @Slot("QVariantMap", result="QVariantMap")
        def applyRegion(self, data):
            ok, message = self._helper(["region"], dict(data))
            return {"ok": ok, "message": message}

        @Slot("QVariantMap", result="QVariantMap")
        def createAccount(self, data):
            ok, message = self._helper(["create-user"], dict(data))
            return {"ok": ok, "message": message}

        @Slot(str, result=str)
        def importPhoto(self, url):
            """Copies a photo chosen by the user into the setup user's home, where the helper may read it."""
            src = Path(QUrl(url).toLocalFile() or url)
            try:
                if not src.is_file() or src.stat().st_size > 5 * 1024 * 1024:
                    return ""
                dst = Path.home() / ".avatar-custom"
                dst.write_bytes(src.read_bytes())
                return str(dst)
            except OSError:
                return ""

        @Slot()
        def startUpdates(self) -> None:
            self.worker = UpdateWorker(demo)
            self.worker.progress.connect(self.updateProgress)
            self.worker.done.connect(self.updateFinished)
            self.worker.start()

        @Slot(str)
        def setStage(self, name) -> None:
            self._helper(["stage", name])

        @Slot(result=bool)
        def verify(self) -> bool:
            return self._helper(["verify"])[0]

        @Slot()
        def rebootNow(self) -> None:
            if demo:
                QGuiApplication.quit()
                return
            self._helper(["reboot"])

        @Slot(bool)
        def finishSetup(self, autologin) -> None:
            if demo:
                QGuiApplication.quit()
                return
            self._helper(["finish"], {"autologin": bool(autologin)})

        @Slot()
        def powerOff(self) -> None:
            if demo:
                QGuiApplication.quit()
                return
            subprocess.Popen(["sudo", "-n", "systemctl", "poweroff"])

        @Slot()
        def quit(self) -> None:
            QGuiApplication.quit()

    app = QGuiApplication(sys.argv)
    app.setApplicationName("ChoutesOS Setup" if setup else "ChoutesOS Installer")
    base = Path(__file__).parent
    app.setWindowIcon(QIcon(str(base / "assets" / "logo.png")))
    engine = QQmlApplicationEngine()
    controller = Controller()
    engine.rootContext().setContextProperty("controller", controller)
    engine.load(QUrl.fromLocalFile(str(base / "qml" / ("Setup.qml" if setup else "Main.qml"))))
    if not engine.rootObjects():
        print("The interface failed to load.", file=sys.stderr)
        return 1
    return app.exec()


def main() -> int:
    parser = argparse.ArgumentParser(prog="choutesos-installer")
    parser.add_argument("--demo", action="store_true", help="dry run; changes nothing")
    parser.add_argument("--setup", action="store_true", help="first-boot setup instead of the installer")
    parser.add_argument("--cli", metavar="CONFIG", help="install from a JSON config file")
    parser.add_argument("--dry-run", action="store_true", help="with --cli: only print the commands")
    args = parser.parse_args()
    if args.cli:
        return run_cli(args.cli, args.dry_run)
    return run_gui(args.demo, args.setup)


if __name__ == "__main__":
    sys.exit(main())
