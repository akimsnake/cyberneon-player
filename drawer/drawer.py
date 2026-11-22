#!/usr/bin/env python3
"""CyberNeon Drawer: a neon side panel that slides out from the left screen edge.
The KWin script in kwin/ moves the pointer-at-the-edge event to this window; this program draws everything."""
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

from PySide6.QtCore import Property, QObject, QProcess, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtNetwork import QLocalServer, QLocalSocket
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle

import sysstats

HERE = Path(__file__).resolve().parent
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))
PLAYER_SOCKET = str(RUNTIME / "cyberneon-player.sock")
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "cyberneon-drawer"
DATA = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share"))) / "cyberneon-drawer"
INSTANCE = "cyberneon-drawer"
DEFAULT_LAUNCHERS = [
    {"name": "FILES", "cmd": "dolphin"},
    {"name": "TERMINAL", "cmd": "konsole"},
    {"name": "WEB", "cmd": "firefox"},
    {"name": "SETTINGS", "cmd": "systemsettings"},
    {"name": "PLAYER", "cmd": "cyberneon-player"},
]


def load_launchers():
    path = CONFIG / "launchers.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        items = [{"name": str(d["name"]), "cmd": str(d["cmd"])} for d in data if d.get("name") and d.get("cmd")]
        if items:
            return items
    except (OSError, ValueError, TypeError, KeyError, AttributeError):
        pass
    try:                                                  # first run: write the default list so you can edit it
        CONFIG.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(DEFAULT_LAUNCHERS, indent=2), encoding="utf-8")
    except OSError:
        pass
    return list(DEFAULT_LAUNCHERS)


class Backend(QObject):
    statsChanged = Signal()
    volumeChanged = Signal()

    def __init__(self):
        super().__init__()
        self._sampler = sysstats.Sampler()
        self._stats = self._sampler.sample()
        self._volume, self._muted = 0.5, False
        self._tick = 0
        self._launchers = load_launchers()
        self._notes_file = DATA / "notes.txt"
        self.read_volume()

    # ----- numbers -----
    @Property("QVariantMap", notify=statsChanged)
    def stats(self):
        return self._stats

    @Property(float, notify=volumeChanged)
    def volume(self):
        return self._volume

    @Property(bool, notify=volumeChanged)
    def muted(self):
        return self._muted

    @Property("QVariantList", constant=True)
    def launchers(self):
        return self._launchers

    @Slot()
    def refresh(self):
        self._stats = self._sampler.sample()
        self.statsChanged.emit()
        self._tick += 1
        if self._tick % 3 == 0:
            self.read_volume()

    # ----- sound -----
    def read_volume(self):
        try:
            out = subprocess.run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"],
                                 capture_output=True, text=True, timeout=1).stdout
            r = sysstats.parse_wpctl(out)
        except (OSError, subprocess.SubprocessError):
            try:
                out = subprocess.run(["pactl", "get-sink-volume", "@DEFAULT_SINK@"],
                                     capture_output=True, text=True, timeout=1).stdout
                v = sysstats.parse_pactl(out)
                r = (v, False) if v is not None else None
            except (OSError, subprocess.SubprocessError):
                r = None
        if r and (abs(r[0] - self._volume) > 0.005 or r[1] != self._muted):
            self._volume, self._muted = r
            self.volumeChanged.emit()

    @Slot(float)
    def setVolume(self, v):
        v = max(0.0, min(1.0, float(v)))
        self._volume = v
        if shutil_which("wpctl"):
            QProcess.startDetached("wpctl", ["set-volume", "@DEFAULT_AUDIO_SINK@", "%.2f" % v])
        else:
            QProcess.startDetached("pactl", ["set-sink-volume", "@DEFAULT_SINK@", "%d%%" % round(v * 100)])
        self.volumeChanged.emit()

    @Slot()
    def toggleMute(self):
        if shutil_which("wpctl"):
            QProcess.startDetached("wpctl", ["set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
        else:
            QProcess.startDetached("pactl", ["set-sink-mute", "@DEFAULT_SINK@", "toggle"])
        self._muted = not self._muted
        self.volumeChanged.emit()

    # ----- player (same commands as cyberneon-ctl) -----
    @Slot(str)
    def send(self, cmd):
        s = QLocalSocket()
        s.connectToServer(PLAYER_SOCKET)
        if s.waitForConnected(300):
            s.write((cmd + "\n").encode("utf-8"))
            s.waitForBytesWritten(300)
            s.waitForReadyRead(300)
            s.disconnectFromServer()

    # ----- launchers and notes -----
    @Slot(str)
    def launch(self, cmd):
        try:
            parts = shlex.split(cmd)
        except ValueError:
            return
        if parts:
            QProcess.startDetached(parts[0], parts[1:])

    @Slot(result=str)
    def loadNotes(self):
        try:
            return self._notes_file.read_text(encoding="utf-8")
        except OSError:
            return ""

    @Slot(str)
    def saveNotes(self, text):
        try:
            DATA.mkdir(parents=True, exist_ok=True)
            self._notes_file.write_text(text, encoding="utf-8")
        except OSError:
            pass


def shutil_which(name):
    import shutil
    return shutil.which(name)


def main():
    # every window of this program becomes a Wayland layer-shell surface (like Plasma's panels)
    os.environ.setdefault("QT_WAYLAND_SHELL_INTEGRATION", "layer-shell")
    app = QGuiApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    app.setApplicationName(INSTANCE)                      # the window class KWin script looks for
    app.setApplicationDisplayName("CyberNeon Drawer")
    app.setDesktopFileName(INSTANCE)

    probe = QLocalSocket()                                # only one drawer at a time
    probe.connectToServer(INSTANCE)
    if probe.waitForConnected(200):
        return 0
    QLocalServer.removeServer(INSTANCE)
    server = QLocalServer()
    server.listen(INSTANCE)
    server.newConnection.connect(lambda: server.nextPendingConnection().close())

    QQuickStyle.setStyle("Basic")
    engine = QQmlApplicationEngine()
    for path in ("/usr/lib/qt6/qml", "/usr/lib64/qt6/qml", "/usr/lib/x86_64-linux-gnu/qt6/qml"):
        if os.path.isdir(path + "/org/kde/layershell"):
            engine.addImportPath(path)
    backend = Backend()
    engine.rootContext().setContextProperty("backend", backend)
    engine.load(QUrl.fromLocalFile(str(HERE / "Drawer.qml")))
    if not engine.rootObjects():
        print("CyberNeon Drawer needs layer-shell-qt (sudo pacman -S layer-shell-qt) and a Wayland session.",
              file=sys.stderr)
        return 1
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
