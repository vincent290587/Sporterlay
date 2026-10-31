"""Application wiring: tray menu, global hotkeys, update timer."""

from __future__ import annotations

import argparse
import datetime as dt
import logging
import sys
import threading
import time
from pathlib import Path

from PyQt6.QtCore import QAbstractNativeEventFilter, QObject, QTimer, pyqtSignal
from PyQt6.QtGui import QAction, QActionGroup, QColor, QIcon, QPainter, QPixmap, QFont
from PyQt6.QtWidgets import (QApplication, QFileDialog, QInputDialog, QLineEdit, QMenu, QMessageBox,
                             QSystemTrayIcon)

from .click import ClickController
from .intervals import IntervalsClient
from .overlay import Overlay, fmt_time
from .ride import Ride
from .settings import Settings, config_dir
from .sources import AntSource, DemoSource
from .workout import parse_zwo
from .workoutdb import load_workout_db

log = logging.getLogger("sporterlay")
TICK_MS = 250
FLASH_S = 2.0  # how long an action confirmation stays in the status line

# Zwift Click v2 buttons other than the shift paddles -> App method (and argument)
CLICK_ACTIONS = {
    "a": ("toggle_pause",),
    "b": ("skip",),
    "y": ("bump_intensity", +5),
    "z": ("bump_intensity", -5),
    "dpad_up": ("shift", +4),
    "dpad_down": ("shift", -4),
    "dpad_left": ("back",),
    "dpad_right": ("toggle_erg",),
}


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


class Signals(QObject):
    """Hands results from worker threads (Bluetooth, HTTP) to the Qt thread."""

    shift = pyqtSignal(int)
    button = pyqtSignal(str)
    click_pods = pyqtSignal(object)  # dict address -> device type, to persist
    icu_done = pyqtSignal(object, object, object, bool)  # workouts, athlete, error, startup


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

        self.signals = Signals()
        self.signals.shift.connect(self.shift)
        self.signals.button.connect(self.click_button)
        self._flash = ("", 0.0)
        self.signals.click_pods.connect(lambda pods: self._set("click_pods", pods))
        self.signals.icu_done.connect(self._icu_done)
        self.icu_workouts = []
        self.icu_status = ""
        self.click = None
        if self.settings.click_enabled and not args.no_click:
            self.click = ClickController(self.signals.shift.emit, self.signals.button.emit,
                                         known=self.settings.click_pods,
                                         on_known=self.signals.click_pods.emit)

        self._library = None  # (path, mtime, workouts) cache
        wo = args.workout or self.settings.last_workout
        if wo and wo.startswith("lib:"):
            self._restore_library_workout(wo[4:])
        elif wo and Path(wo).exists():
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
                0x27: lambda: self.shift(+1),  # right arrow: harder gear
                0x25: lambda: self.shift(-1),  # left arrow: easier gear
            })
            self.qapp.installNativeEventFilter(self.hotkeys)

        self._last = time.monotonic()
        self.timer = QTimer()
        self.timer.timeout.connect(self.tick)
        self.timer.start(TICK_MS)
        self.overlay.show()
        if self.settings.icu_api_key:
            self.refresh_intervals(startup=True)

    # ---- loop --------------------------------------------------------------------
    def tick(self):
        now = time.monotonic()
        dt, self._last = min(now - self._last, 1.0), now
        self.ride.tick(dt)
        self.overlay.refresh()

    def flash(self, text: str) -> None:
        """Briefly show an action confirmation in the status line."""
        self._flash = (text, time.monotonic() + FLASH_S)
        self.overlay.refresh()

    def click_button(self, name: str):
        action = CLICK_ACTIONS.get(name)
        if action is None:
            log.info("Click button %s (not mapped)", name)
            return
        getattr(self, action[0])(*action[1:])

    def status_text(self):
        text, until = self._flash
        if text and time.monotonic() < until:
            return text
        t = self.ride.telemetry
        if not t.trainer_connected:
            return self.source.status
        bits = []
        if self.ride.player and not self.ride.player.finished:
            if self.ride.erg_waiting:
                bits.append(f"ERG starts at {self.settings.erg_engage_rpm} rpm")
            else:
                bits.append("ERG on" if self.settings.erg else "ERG off")
        if not t.hr_connected:
            bits.append("no heart rate")
        if self.click and not self.click.connected:
            bits.append(self.click.status)
        if self.icu_status:
            bits.append(self.icu_status)
        return " · ".join(bits) if bits else None

    # ---- shifting --------------------------------------------------------------------
    def shift(self, delta: int):
        self.ride.shift(delta)
        if abs(delta) > 1:  # single shifts show in the GEAR cell; flag the jumps
            self.flash(f"Gear {self.settings.gear}" + (" (ERG active)" if self.ride.erg_active else ""))
        self.overlay.refresh()

    # ---- intervals.icu ---------------------------------------------------------------
    def refresh_intervals(self, startup=False):
        key, athlete = self.settings.icu_api_key, self.settings.icu_athlete_id
        self.icu_status = "intervals.icu: loading…"

        def work():
            client = IntervalsClient(key, athlete)
            workouts = athlete_info = error = None
            try:
                workouts = client.planned_workouts()
                athlete_info = client.athlete() if self.settings.icu_sync_ftp else None
            except Exception as e:  # IntervalsError or anything unexpected
                error = str(e)
                log.warning("intervals.icu: %s", e)
            self.signals.icu_done.emit(workouts, athlete_info, error, startup)

        threading.Thread(target=work, name="intervals", daemon=True).start()

    def _icu_done(self, workouts, athlete, error, startup):
        if error:
            self.icu_status = error
            QTimer.singleShot(15000, lambda: setattr(self, "icu_status", ""))
            return
        self.icu_status = ""
        self.icu_workouts = workouts or []
        if athlete:
            if athlete.ftp:
                self.settings.ftp = athlete.ftp
            if athlete.weight_kg:
                self.settings.weight_kg = round(athlete.weight_kg, 1)
            self.settings.save()
        today = [w for w in self.icu_workouts if w.date == dt.date.today()]
        busy = self.ride.player is not None and self.ride.player.started
        if startup and today and self.settings.icu_autoload_today and not busy:
            self.load_planned(today[0])
            self.tray.showMessage("Sporterlay", f"Today's workout loaded: {today[0].name}", self.icon, 4000)

    def load_planned(self, pw):
        self.ride.load_workout(pw.workout)
        self.settings.last_workout = f"icu:{pw.event_id}"
        self.settings.save()
        self.overlay.refresh()

    # ---- ai_advise workout library ---------------------------------------------------
    def library_path(self) -> Path | None:
        if self.settings.workout_db and Path(self.settings.workout_db).exists():
            return Path(self.settings.workout_db)
        for d in (config_dir(), resource_dir()):
            for name in ("workouts.json", "workoutDB.bin"):
                if (d / name).exists():
                    return d / name
        return None

    def library(self):
        path = self.library_path()
        if path is None:
            return None, []
        mtime = path.stat().st_mtime
        if not self._library or self._library[:2] != (path, mtime):
            self._library = (path, mtime, load_workout_db(path))
            log.info("Workout library %s: %d workouts", path, len(self._library[2]))
        return path, self._library[2]

    def _restore_library_workout(self, name: str):
        try:
            _, workouts = self.library()
        except Exception as e:
            log.warning("Could not read workout library: %s", e)
            return
        match = next((w for w in workouts if w.name == name), None)
        if match:
            self.ride.load_workout(match.workout)

    def open_library(self):
        from .library import LibraryDialog

        try:
            path, workouts = self.library()
        except Exception as e:
            QMessageBox.warning(None, "Sporterlay", f"Could not read the workout library:\n{e}")
            path, workouts = None, []
        if path is None or not workouts:
            if not self.choose_library():
                return
            path, workouts = self.library()
        dlg = LibraryDialog(workouts, lambda f: round(f * self.settings.ftp), path.name)
        if dlg.exec() and dlg.chosen:
            self.ride.load_workout(dlg.chosen.workout)
            self.settings.last_workout = f"lib:{dlg.chosen.name}"
            self.settings.save()
            self.overlay.refresh()

    def choose_library(self) -> bool:
        start = str(Path(self.settings.workout_db).parent) if self.settings.workout_db else str(config_dir())
        path, _ = QFileDialog.getOpenFileName(None, "Choose your workout library", start,
                                              "Workout library (workouts.json workoutDB.bin *.json *.bin)")
        if not path:
            return False
        try:
            n = len(load_workout_db(path))
        except Exception as e:
            QMessageBox.warning(None, "Sporterlay", f"That file isn't a workout library:\n{e}")
            return False
        if n == 0:
            QMessageBox.warning(None, "Sporterlay", "No workouts found in that file.")
            return False
        self.settings.workout_db = path
        self.settings.save()
        return True

    def set_api_key(self):
        key, ok = QInputDialog.getText(
            None, "Sporterlay",
            "intervals.icu API key\n(intervals.icu → Settings → Developer settings):",
            QLineEdit.EchoMode.Password, self.settings.icu_api_key)
        if ok:
            self.settings.icu_api_key = key.strip()
            self.settings.save()
            if self.settings.icu_api_key:
                self.refresh_intervals(startup=True)

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

    def _workout_running(self) -> bool:
        p = self.ride.player
        if p is None:
            self.flash("No workout loaded")
            return False
        if p.finished:
            self.flash("Workout finished")
            return False
        return True

    def toggle_pause(self):
        if self._workout_running():
            p = self.ride.player
            p.paused = not p.paused
            self.flash("Workout paused" if p.paused else "Workout resumed")

    def skip(self):
        if self._workout_running():
            self.ride.player.skip()
            self.flash("Workout finished" if self.ride.player.finished else "Next interval")

    def back(self):
        if self._workout_running():
            before = self.ride.player.index()
            self.ride.player.back()
            self.flash("Previous interval" if self.ride.player.index() < before else "Interval restarted")

    def toggle_erg(self):
        self.settings.erg = not self.settings.erg
        self.settings.save()
        self.flash("ERG on" if self.settings.erg else "ERG off: gears active")

    def bump_intensity(self, d):
        self.settings.intensity = max(50, min(150, self.settings.intensity + d))
        self.settings.save()
        self.flash(f"Intensity {self.settings.intensity} %")

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
        if self.click:
            self.click.close()
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

        icu = m.addMenu("intervals.icu")
        if not s.icu_api_key:
            act("Set API key…", self.set_api_key, menu=icu)
        else:
            today = dt.date.today()
            if not self.icu_workouts:
                act("(no planned rides in the next 7 days)", lambda: None, enabled=False, menu=icu)
            for pw in self.icu_workouts:
                if pw.date < today:
                    day = "Yesterday"
                elif pw.date == today:
                    day = "Today"
                else:
                    day = pw.date.strftime("%a %d %b")
                act(f"{day}:  {pw.name}  ({fmt_time(pw.duration_s)})", lambda pw=pw: self.load_planned(pw),
                    menu=icu)
            icu.addSeparator()
            act("Refresh", self.refresh_intervals, menu=icu)
            act("Use FTP and weight from intervals.icu", lambda: self._toggle("icu_sync_ftp"),
                checked=s.icu_sync_ftp, menu=icu)
            act("Load today's workout at startup", lambda: self._toggle("icu_autoload_today"),
                checked=s.icu_autoload_today, menu=icu)
            act("Change API key…", self.set_api_key, menu=icu)
        act("Workout library…", self.open_library)
        wm = m.addMenu("Local workout files")
        found = False
        for d in workout_dirs():
            for f in sorted(d.glob("*.zwo")):
                act(f.stem.replace("_", " "), lambda f=f: self.load_workout(f), menu=wm)
                found = True
        if not found:
            act("(none found)", lambda: None, enabled=False, menu=wm)
        wm.addSeparator()
        act("Open workouts folder", lambda: self._open_folder(workout_dirs()[1]), menu=wm)
        act("Load workout file…", self.pick_workout, menu=wm)
        act("Choose workout library file…", self.choose_library, menu=wm)
        has = self.ride.player is not None
        act("Unload workout", self.unload_workout, enabled=has)
        m.addSeparator()
        act("Pause workout\tCtrl+Alt+P", self.toggle_pause,
            checked=bool(has and self.ride.player.paused), enabled=has)
        act("Next interval\tCtrl+Alt+N", self.skip, enabled=has)
        act("Previous / restart interval\tCtrl+Alt+B", self.back, enabled=has)
        act("ERG mode\tCtrl+Alt+E", self.toggle_erg, checked=s.erg)
        gm = m.addMenu(f"Gear {s.gear}/{len(self.ride.ratios)}   (Click or Ctrl+Alt+←/→)")
        act("Harder", lambda: self.shift(+1), menu=gm)
        act("Easier", lambda: self.shift(-1), menu=gm)
        act("Back to neutral gear", self._neutral_gear, menu=gm)
        gm.addSeparator()
        cs = self.click.status if self.click else "Zwift Click disabled"
        act(cs, lambda: None, enabled=False, menu=gm)
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

    def _toggle(self, key):
        self._set(key, not getattr(self.settings, key))

    def _neutral_gear(self):
        from .shifting import neutral_gear

        self.shift(neutral_gear(self.ride.ratios, self.ride.real_ratio) - self.settings.gear)

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
    ap.add_argument("--no-click", action="store_true", help="don't look for a Zwift Click")
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
