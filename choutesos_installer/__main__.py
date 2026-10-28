"""ChoutesOS installer entry point.

    python -m choutesos_installer            graphical installer
    python -m choutesos_installer --demo     graphical installer, dry run (changes nothing)
    python -m choutesos_installer --cli FILE install from a JSON config (add --dry-run to test)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from .backend import Config, InstallError, Installer


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


def run_gui(demo: bool) -> int:
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    from PySide6.QtCore import QObject, QThread, QUrl, Signal, Slot
    from PySide6.QtGui import QGuiApplication, QIcon
    from PySide6.QtQml import QQmlApplicationEngine

    from . import system_info

    class Worker(QThread):
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

    class Controller(QObject):
        progressChanged = Signal(float, str)
        logLine = Signal(str)
        installFinished = Signal(bool, str)

        def __init__(self) -> None:
            super().__init__()
            self.worker: Worker | None = None

        @Slot(result=bool)
        def isDemo(self) -> bool:
            return demo

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
        def disks(self):
            found = system_info.list_disks()
            if demo and not found:
                found = [{"path": "/dev/demo0", "model": "Demo disk", "sizeGb": 512,
                          "removable": False, "transport": "nvme"}]
            return found

        @Slot("QVariantMap", result="QVariantList")
        def validate(self, data):
            return Config.from_dict(dict(data)).validate(check_paths=not demo)

        @Slot("QVariantMap")
        def install(self, data) -> None:
            cfg = Config.from_dict(dict(data))
            self.worker = Worker(cfg, dry_run=demo)
            self.worker.progress.connect(self.progressChanged)
            self.worker.line.connect(self.logLine)
            self.worker.done.connect(self.installFinished)
            self.worker.start()

        @Slot()
        def reboot(self) -> None:
            if demo:
                QGuiApplication.quit()
                return
            os.system("sudo -n systemctl reboot")

        @Slot()
        def quit(self) -> None:
            QGuiApplication.quit()

    app = QGuiApplication(sys.argv)
    app.setApplicationName("ChoutesOS Installer")
    base = Path(__file__).parent
    app.setWindowIcon(QIcon(str(base / "assets" / "logo.png")))
    engine = QQmlApplicationEngine()
    controller = Controller()
    engine.rootContext().setContextProperty("controller", controller)
    engine.load(QUrl.fromLocalFile(str(base / "qml" / "Main.qml")))
    if not engine.rootObjects():
        print("The installer interface failed to load.", file=sys.stderr)
        return 1
    return app.exec()


def main() -> int:
    parser = argparse.ArgumentParser(prog="choutesos-installer")
    parser.add_argument("--demo", action="store_true", help="graphical dry run; changes nothing")
    parser.add_argument("--cli", metavar="CONFIG", help="install from a JSON config file")
    parser.add_argument("--dry-run", action="store_true", help="with --cli: only print the commands")
    args = parser.parse_args()
    if args.cli:
        return run_cli(args.cli, args.dry_run)
    return run_gui(args.demo)


if __name__ == "__main__":
    sys.exit(main())
