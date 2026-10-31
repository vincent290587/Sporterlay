"""Application wiring: tray menu, global hotkeys, update timer."""

from __future__ import annotations

import argparse
import logging
import sys
import time
from pathlib import Path

from PyQt6.QtCore import QAbstractNativeEventFilter, QTimer
from PyQt6.QtGui import QAction, QActionGroup, QColor, QIcon, QPainter, QPixmap, QFont
from PyQt6.QtWidgets import QApplication, QFileDialog, QInputDialog, QMenu, QMessageBox, QSystemTrayIcon

from .overlay import Overlay
from .ride import Ride
from .settings import Settings, config_dir
from .sources import AntSource, DemoSource
from .workout import parse_zwo

log = logging.getLogger("sporterlay")
TICK_MS = 250


def resource_dir() -> Path:
    """Folder with bundled files (works from source and from a PyInstaller .exe)."""
    if hasattr(sys, "_MEIPASS"):
        return Path(sys._MEIPASS)
    return Path(__file__).resolve().parent.parent


def workout_dirs() -> list[Path]:
    user = config_dir() / "workouts"
    user.mkdir(parents=True, exist_ok=True)
    return [resource_dir() / "workouts", user]


def make_icon() -> QIcon:
    pm = QPixmap(64, 64)
    pm.fill(QColor(0, 0, 0, 0))
    p = QPainter(pm)
    p.setRenderHint(QPainter.RenderHint.Antialiasing)
    p.setBrush(QColor(255, 110, 50))
    p.setPen(QColor(0, 0, 0, 0))
    p.drawEllipse(2, 2, 60, 60)
    f = QFont()
    f.setPixelSize(40)
    f.setBold(True)
    p.setFont(f)
    p.setPen(QColor(255, 255, 255))
    p.drawText(pm.rect(), 0x84, "S")  # AlignCenter
    p.end()
    return QIcon(pm)


class WinHotkeys(QAbstractNativeEventFilter):
    """System-wide Ctrl+Alt+<key> shortcuts on Windows, so you can control the
    workout while YouTube has focus (even fullscreen)."""

    MOD_ALT, MOD_CONTROL, MOD_NOREPEAT = 0x1, 0x2, 0x4000
    WM_HOTKEY = 0x0312

    def __init__(self, bindings: dict[int, callable]):
        super().__init__()
        import ctypes
        from ctypes import wintypes

        self._user32 = ctypes.windll.user32
        self._MSG = wintypes.MSG
        self._actions = {}
        for i, (vk, fn) in enumerate(bindings.items(), start=1):
            ok = self._user32.RegisterHotKey(None, i, self.MOD_CONTROL | self.MOD_ALT | self.MOD_NOREPEAT, vk)
            if ok:
                self._actions[i] = fn
            else:
                log.warning("Hotkey Ctrl+Alt+%s is already used by another program", chr(vk) if vk < 128 else vk)

    def nativeEventFilter(self, event_type, message):
        if bytes(event_type) == b"windows_generic_MSG":
            msg = self._MSG.from_address(int(message))
            if msg.message == self.WM_HOTKEY and msg.wParam in self._actions:
                QTimer.singleShot(0, self._actions[msg.wParam])
                return True, 0
        return False, 0

    def unregister(self):
        for i in self._actions:
            self._user32.UnregisterHotKey(None, i)


class App:
    def __init__(self, args):
        self.qapp = QApplication(sys.argv)
        self.qapp.setQuitOnLastWindowClosed(False)
        self.qapp.setApplicationName("Sporterlay")
        self.settings = Settings.load()
        if args.ftp:
            self.settings.ftp = args.ftp
        self.source = DemoSource(self.settings.ftp) if args.demo else AntSource(
            self.settings.fe_device_id, self.settings.hr_device_id)
        self.ride = Ride(self.settings, self.source)
        self.overlay = Overlay(self.ride, self.status_text)

        wo = args.workout or self.settings.last_workout
        if wo and Path(wo).exists():
            self.load_workout(wo, quiet=not args.workout)

        self.icon = make_icon()
        self.qapp.setWindowIcon(self.icon)
        self.tray = QSystemTrayIcon(self.icon)
        self.tray.setToolTip("Sporterlay")
        self.menu = QMenu()
        self.menu.aboutToShow.connect(self.build_menu)
        self.build_menu()
        self.tray.setContextMenu(self.menu)
        self.tray.activated.connect(self._tray_click)
        self.tray.show()

        self.hotkeys = None
        if sys.platform == "win32":
            VK_UP, VK_DOWN = 0x26, 0x28
            self.hotkeys = WinHotkeys({
                ord("P"): self.toggle_pause,
                ord("N"): self.skip,
                ord("B"): self.back,
                ord("E"): self.toggle_erg,
                ord("L"): self.toggle_lock,
                ord("H"): self.toggle_visible,
                VK_UP: lambda: self.bump_intensity(+5),
                VK_DOWN: lambda: self.bump_intensity(-5),
            })
            self.qapp.installNativeEventFilter(self.hotkeys)

        self._last = time.monotonic()
        self.timer = QTimer()
        self.timer.timeout.connect(self.tick)
        self.timer.start(TICK_MS)
        self.overlay.show()

    # ---- loop --------------------------------------------------------------------
    def tick(self):
        now = time.monotonic()
        dt, self._last = min(now - self._last, 1.0), now
        self.ride.tick(dt)
        self.overlay.refresh()

    def status_text(self):
        t = self.ride.telemetry
        if not t.trainer_connected:
            return self.source.status
        bits = []
        if self.ride.player and not self.ride.player.finished:
            bits.append("ERG on" if self.settings.erg else "ERG off")
        if not t.hr_connected:
            bits.append("no heart rate")
        return " · ".join(bits) if bits else None

    # ---- actions -------------------------------------------------------------------
    def load_workout(self, path, quiet=False):
        try:
            wo = parse_zwo(path)
        except Exception as e:
            if not quiet:
                QMessageBox.warning(None, "Sporterlay", f"Could not load workout:\n{path}\n\n{e}")
            return
        self.ride.load_workout(wo)
        self.settings.last_workout = str(path)
        self.settings.save()
        self.overlay.refresh()

    def pick_workout(self):
        start = str(workout_dirs()[1])
        path, _ = QFileDialog.getOpenFileName(None, "Load workout", start, "Zwift workouts (*.zwo);;All files (*)")
        if path:
            self.load_workout(path)

    def unload_workout(self):
        self.ride.unload_workout()
        self.settings.last_workout = ""
        self.settings.save()
        self.overlay.refresh()

    def toggle_pause(self):
        if self.ride.player:
            self.ride.player.paused = not self.ride.player.paused

    def skip(self):
        if self.ride.player:
            self.ride.player.skip()

    def back(self):
        if self.ride.player:
            self.ride.player.back()

    def toggle_erg(self):
        self.settings.erg = not self.settings.erg
        self.settings.save()

    def bump_intensity(self, d):
        self.settings.intensity = max(50, min(150, self.settings.intensity + d))
        self.settings.save()

    def toggle_lock(self):
        self.overlay.set_locked(not self.settings.locked)

    def toggle_visible(self):
        self.overlay.setVisible(not self.overlay.isVisible())

    def ask_int(self, title, label, value, lo, hi):
        v, ok = QInputDialog.getInt(None, "Sporterlay", label, value, lo, hi)
        return v if ok else None

    def set_ftp(self):
        v = self.ask_int("FTP", "FTP (watts):", self.settings.ftp, 50, 600)
        if v:
            self.settings.ftp = v
            self.settings.save()

    def set_weight(self):
        v, ok = QInputDialog.getDouble(None, "Sporterlay", "Weight (kg):", self.settings.weight_kg, 30, 200, 1)
        if ok:
            self.settings.weight_kg = v
            self.settings.save()

    def quit(self):
        self.source.set_free_ride(0.0)
        self.settings.save()
        if self.hotkeys:
            self.hotkeys.unregister()
        self.source.close()
        self.tray.hide()
        self.qapp.quit()

    def _tray_click(self, reason):
        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            self.toggle_visible()

    # ---- tray menu (rebuilt each time it opens so labels stay current) --------------
    def build_menu(self):
        m = self.menu
        m.clear()
        s = self.settings

        def act(text, fn, checked=None, enabled=True, menu=m):
            a = QAction(text, menu)
            if checked is not None:
                a.setCheckable(True)
                a.setChecked(checked)
            a.setEnabled(enabled)
            a.triggered.connect(lambda _=False: fn())
            menu.addAction(a)
            return a

        wm = m.addMenu("Workouts")
        found = False
        for d in workout_dirs():
            for f in sorted(d.glob("*.zwo")):
                act(f.stem.replace("_", " "), lambda f=f: self.load_workout(f), menu=wm)
                found = True
        if not found:
            act("(none found)", lambda: None, enabled=False, menu=wm)
        wm.addSeparator()
        act("Open workouts folder", lambda: self._open_folder(workout_dirs()[1]), menu=wm)
        act("Load workout file…", self.pick_workout)
        has = self.ride.player is not None
        act("Unload workout", self.unload_workout, enabled=has)
        m.addSeparator()
        act("Pause workout\tCtrl+Alt+P", self.toggle_pause,
            checked=bool(has and self.ride.player.paused), enabled=has)
        act("Next interval\tCtrl+Alt+N", self.skip, enabled=has)
        act("Previous / restart interval\tCtrl+Alt+B", self.back, enabled=has)
        act("ERG mode\tCtrl+Alt+E", self.toggle_erg, checked=s.erg)
        im = m.addMenu(f"Intensity: {s.intensity}%   (Ctrl+Alt+↑/↓)")
        for v in (70, 80, 90, 95, 100, 105, 110, 120):
            act(f"{v}%", lambda v=v: self._set("intensity", v), checked=s.intensity == v, menu=im)
        m.addSeparator()
        act(f"FTP: {s.ftp} W…", self.set_ftp)
        act(f"Weight: {s.weight_kg:g} kg…", self.set_weight)
        pm = m.addMenu("Power smoothing")
        grp = QActionGroup(pm)
        for v in (1, 3, 5, 10):
            a = act("Instant" if v == 1 else f"{v} s average", lambda v=v: self._set("power_avg_s", v),
                    checked=s.power_avg_s == v, menu=pm)
            grp.addAction(a)
        om = m.addMenu("Opacity")
        for v in (100, 92, 80, 65):
            act(f"{v}%", lambda v=v: self._set_opacity(v / 100), checked=abs(s.opacity - v / 100) < 0.01, menu=om)
        m.addSeparator()
        act("Lock position (click-through)\tCtrl+Alt+L", self.toggle_lock, checked=s.locked)
        act("Reset position and size", self._reset_pos)
        act("Show overlay\tCtrl+Alt+H", self.toggle_visible, checked=self.overlay.isVisible())
        act("Reset ride (time, distance, workout)", self.ride.reset)
        m.addSeparator()
        act("Quit", self.quit)

    def _set(self, key, value):
        setattr(self.settings, key, value)
        self.settings.save()

    def _set_opacity(self, v):
        self.settings.opacity = v
        self.settings.save()
        self.overlay.setWindowOpacity(v)

    def _reset_pos(self):
        self.settings.scale = 1.0
        self.overlay.refresh()
        self.overlay.reset_position()

    @staticmethod
    def _open_folder(path: Path):
        from PyQt6.QtCore import QUrl
        from PyQt6.QtGui import QDesktopServices

        QDesktopServices.openUrl(QUrl.fromLocalFile(str(path)))

    def run(self) -> int:
        return self.qapp.exec()


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="sporterlay", description="Smart trainer HUD overlay")
    ap.add_argument("--demo", action="store_true", help="simulate a trainer and HR strap (no ANT+ needed)")
    ap.add_argument("--workout", help="path to a .zwo workout to load")
    ap.add_argument("--ftp", type=int, help="override FTP for this session")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args(argv)

    # pythonw / windowed .exe have no console: sys.stderr is None there
    handlers = [logging.StreamHandler()] if sys.stderr is not None else []
    try:
        config_dir().mkdir(parents=True, exist_ok=True)
        handlers.append(logging.FileHandler(config_dir() / "sporterlay.log", mode="w", encoding="utf-8"))
    except Exception:
        pass
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(name)s %(levelname)s %(message)s", handlers=handlers)
    return App(args).run()
