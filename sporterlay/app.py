"""Application wiring: tray menu, global hotkeys, update timer."""

from __future__ import annotations

import argparse
import datetime as dt
import logging
import os
import sys
import threading
import time
from pathlib import Path

from PyQt6.QtCore import QAbstractNativeEventFilter, QLockFile, QObject, QRectF, QTimer, pyqtSignal
from PyQt6.QtGui import QAction, QActionGroup, QColor, QIcon, QPainter, QPixmap, QFont
from PyQt6.QtWidgets import (QApplication, QFileDialog, QInputDialog, QLineEdit, QMenu, QMessageBox,
                             QSystemTrayIcon)

from . import recorder
from .buttonmap import ButtonMap
from .click import LEFT_POD, RIGHT_POD, ClickController
from .cues import Beeper
from .dircon import ZwiftShare
from .fan import FanProfile, HeadwindController
from .ftptest import RampTest, is_ramp_test, ramp_workout
from .intervals import IntervalsClient
from .media import AutoPause, MediaSessions, NowPlaying
from .overlay import Overlay, _family, fmt_time
from .ride import Ride
from .settings import Settings, config_dir
from .summary import summarize
from .webscreen import WebScreen, ride_state, workout_key, workout_payload
from .sources import AntSource, DemoSource
from .workout import parse_zwo
from .workoutdb import load_workout_db

log = logging.getLogger("sporterlay")
TICK_MS = 250
FLASH_S = 2.0  # how long an action confirmation stays in the status line
RIDE_IDLE_END_S = 600  # a ride ends after this long without pedaling...
RIDE_DONE_END_S = 30  # ...or this long once the workout is finished
WBAL_WARN, WBAL_REARM = 0.25, 0.35  # W′ balance warning and when it can warn again
CARD_PEDAL_HIDE_S = 5  # the ride card goes away when pedaling resumes, once shown this long
EFTP_WAIT_S, EFTP_POLL_S = 180, 5  # how long to wait for intervals.icu to analyse a ramp test
EFTP_FTP_TRIES = 6  # then how many times to re-read the FTP while intervals.icu may still raise it

# Actions a Zwift Click button can be bound to: key -> (menu label, button map label, App method, args...)
ACTIONS = {
    "none": ("Nothing", ""),
    "harder": ("Harder gear", "Harder", "shift", +1),
    "easier": ("Easier gear", "Easier", "shift", -1),
    "harder4": ("4 gears harder", "+4 gears", "shift", +4),
    "easier4": ("4 gears easier", "−4 gears", "shift", -4),
    "neutral": ("Neutral gear", "Neutral gear", "_neutral_gear"),
    "pause": ("Pause / resume workout", "Pause", "toggle_pause"),
    "skip": ("Next interval", "Next interval", "skip"),
    "back": ("Previous / restart interval", "Back", "back"),
    "erg": ("ERG on / off", "ERG on/off", "toggle_erg"),
    "iso": ("Isokinetic on / off", "Isokinetic", "toggle_iso"),
    "int_up": ("Intensity +5 %", "Intensity +5%", "bump_intensity", +5),
    "int_down": ("Intensity −5 %", "Intensity −5%", "bump_intensity", -5),
    "overlay": ("Show / hide overlay", "Overlay", "toggle_visible"),
    "map": ("Show / hide this button map", "Button map", "toggle_button_map"),
    "card": ("Show / hide ride summary", "Ride summary", "toggle_card"),
    "ramp_done": ("End ramp test (I'm done)", "Ramp done", "end_ramp_test"),
    "fan_up": ("Fan +10 %", "Fan +10%", "nudge_fan", +10),
    "fan_down": ("Fan −10 %", "Fan −10%", "nudge_fan", -10),
}
DEFAULT_CLICK_MAP = {
    "shift_up": "harder", "shift_down": "easier",
    "a": "pause", "b": "skip", "y": "int_up", "z": "int_down",
    "dpad_up": "harder4", "dpad_down": "easier4", "dpad_left": "back", "dpad_right": "erg",
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


def activities_dir() -> Path:
    return config_dir() / "activities"


def qr_pixmap(text: str, box: int = 8, border: int = 4):
    """QR code for the second screen's address, or None without the qrcode package."""
    try:
        import qrcode
    except ImportError:
        return None
    qr = qrcode.QRCode(border=border, error_correction=qrcode.constants.ERROR_CORRECT_M)
    qr.add_data(text)
    qr.make(fit=True)
    m = qr.get_matrix()
    n = len(m)
    pm = QPixmap(n * box, n * box)
    pm.fill(QColor("white"))
    p = QPainter(pm)
    for y, row in enumerate(m):
        for x, on in enumerate(row):
            if on:
                p.fillRect(x * box, y * box, box, box, QColor("black"))
    p.end()
    return pm


def fan_profile_path() -> Path:
    return config_dir() / "fan.json"


def make_icon(size: int = 64) -> QIcon:
    pm = QPixmap(size, size)
    pm.fill(QColor(0, 0, 0, 0))
    p = QPainter(pm)
    p.setRenderHint(QPainter.RenderHint.Antialiasing)
    p.setBrush(QColor(255, 110, 50))
    p.setPen(QColor(0, 0, 0, 0))
    m = size / 32
    p.drawEllipse(QRectF(m, m, size - 2 * m, size - 2 * m))
    f = QFont(_family())
    f.setPixelSize(round(size * 0.625))
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

    button = pyqtSignal(str)
    click_pods = pyqtSignal(object)  # dict address -> device type, to persist
    icu_done = pyqtSignal(object, object, object, bool)  # workouts, athlete, error, startup
    upload_done = pyqtSignal(object, object)  # [(fit name, activity id, meta)] uploaded, error (str) or None
    eftp_done = pyqtSignal(object, object, object)  # eFTP (int) or None, AthleteInfo or None, error
    zwift = pyqtSignal(bool)  # Zwift connected / gone
    fan_address = pyqtSignal(str)  # Headwind found: remember it


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
        self.demo = args.demo
        self.ride = Ride(self.settings, self.source)
        self.card_state = None  # end-of-ride card: dict(summary, status, fit, until, shown)
        self.ramp = None  # RampTest while a ramp test workout is loaded
        self._ramp_fit = None  # .fit name of the ramp test waiting for its eFTP
        self.overlay = Overlay(self.ride, self.status_text, self.now_playing_text, self.card)
        self.beeper = Beeper(config_dir() / "sounds")
        self.media = MediaSessions()
        self.autopause = AutoPause()
        self.music = NowPlaying()
        self.recorder = recorder.RideRecorder(activities_dir(), demo=args.demo)
        self._uploading = False
        self._wbal_warned = False

        self.signals = Signals()
        self.signals.button.connect(self.click_button)
        self._flash = ("", 0.0)
        self.signals.click_pods.connect(lambda pods: self._set("click_pods", pods))
        self.signals.icu_done.connect(self._icu_done)
        self.signals.upload_done.connect(self._upload_done)
        self.signals.eftp_done.connect(self._eftp_done)
        self.signals.zwift.connect(lambda on: self.flash("Zwift connected" if on else "Zwift disconnected"))
        self.zwift = ZwiftShare(self.signals.zwift.emit) if self.settings.zwift_share else None
        self.signals.fan_address.connect(lambda a: self._set("fan_address", a))
        self.fan_profile = FanProfile.load(fan_profile_path())
        self._fan_mtime = self._profile_mtime()
        self._fan_check = 0.0
        self.fan = None
        if self.settings.fan:
            self._start_fan()
        self._hud_on = True  # Ctrl+Alt+H / tray "Show overlay" (within the HUD mode)
        self._cue_seq = 0
        self._cue = None
        self.web = WebScreen(self.settings.web_port) if self.settings.web_screen else None
        self.icu_workouts = []
        self.icu_status = ""
        self.click = None
        if self.settings.click_enabled and not args.no_click:
            self.click = ClickController(self.signals.button.emit, known=self.settings.click_pods,
                                         on_known=self.signals.click_pods.emit)
        self.button_map = ButtonMap(self.settings, lambda b: ACTIONS[self.click_action(b)][1],
                                    self._click_map_status, self.overlay.screen)

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
                ord("I"): self.toggle_iso,
                ord("M"): self.toggle_button_map,
                0x27: lambda: self.shift(+1),  # right arrow: harder gear
                0x25: lambda: self.shift(-1),  # left arrow: easier gear
            })
            self.qapp.installNativeEventFilter(self.hotkeys)

        self._last = time.monotonic()
        self.timer = QTimer()
        self.timer.timeout.connect(self.tick)
        self.timer.start(TICK_MS)
        self._apply_hud()
        if self.settings.icu_api_key:
            self.refresh_intervals(startup=True)
        QTimer.singleShot(0, self._recover_rides)

    # ---- loop --------------------------------------------------------------------
    def tick(self):
        now = time.monotonic()
        dt, self._last = min(now - self._last, 1.0), now
        self.ride.tick(dt)
        if self.ride.cues:
            self._cue_seq += 1
            self._cue = self.ride.cues[-1]  # one sound per tick; the step change wins over a tick
            if self.settings.beeps:
                self.beeper.play(self._cue)
        self._ramp_tick()
        self._record()
        self._card_tick(now)
        if self.zwift:
            t = self.ride.telemetry  # raw, not the smoothed power on the HUD
            self.zwift.update(t.power, t.cadence, t.heart_rate)
        self._media(now)
        self._fan(now, dt)
        self._wbal_warning()
        self._apply_hud()
        self.overlay.refresh()
        self.button_map.refresh()
        self._web()

    # ---- second screen and HUD visibility -------------------------------------------------
    def _web(self) -> None:
        if self.web is None or not self.web.connected:
            return
        r = self.ride
        state = ride_state(r, self.status_text(), self.now_playing_text(), self.card(),
                           (self._cue_seq, self._cue if self.settings.beeps else None))
        self.web.publish(state, workout_key(r), lambda: workout_payload(r))

    def hud_wanted(self) -> bool:
        mode = self.settings.hud_mode
        if mode == "hidden":
            return False
        if mode == "auto" and self.web is not None and self.web.connected:
            return False
        return self._hud_on

    def _apply_hud(self) -> None:
        want = self.hud_wanted()
        if want != self.overlay.isVisible():
            self.overlay.setVisible(want)
        if self.button_map.suppressed == want:
            self.button_map.suppressed = not want
            self.button_map.refresh()

    def set_hud_mode(self, mode: str) -> None:
        self._set("hud_mode", mode)
        self._hud_on = True
        self._apply_hud()
        if mode == "auto" and self.web is None:
            self.flash("Turn on the second screen too (tray → Second screen)")

    def toggle_web_screen(self):
        self._toggle("web_screen")
        if self.settings.web_screen and self.web is None:
            self.web = WebScreen(self.settings.web_port)
            if self.web.error:
                self.flash(self.web.error)
            else:
                self.show_web_address()
        elif not self.settings.web_screen and self.web is not None:
            self.web.close()
            self.web = None
            self.flash("Second screen off")
        self._apply_hud()

    def show_web_address(self):
        if self.web is None:
            return
        from PyQt6.QtCore import Qt
        from PyQt6.QtWidgets import QDialog, QLabel, QVBoxLayout

        url = self.web.url
        dlg = QDialog()
        dlg.setWindowTitle("Sporterlay: second screen")
        lay = QVBoxLayout(dlg)
        qr = qr_pixmap(url)
        if qr is not None:
            img = QLabel()
            img.setPixmap(qr)
            img.setAlignment(Qt.AlignmentFlag.AlignCenter)
            lay.addWidget(img)
        link = QLabel(f'<p style="font-size:20px"><b>{url}</b></p>')
        link.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        link.setAlignment(Qt.AlignmentFlag.AlignCenter)
        lay.addWidget(link)
        lay.addWidget(QLabel("Scan the code or type the address in the browser of a phone or tablet\n"
                             "on the same Wi-Fi. If Windows asks about network access, allow private networks."))
        dlg.exec()

    def _media(self, now: float) -> None:
        s = self.settings
        sessions = self.media.sessions
        pause, resume = self.autopause.update(now, self.ride.pedaling, sessions, s.autopause_video,
                                              s.autopause_delay_s, s.autopause_apps)
        self.media.pause(pause)
        self.media.play(resume)
        self.music.update(now, sessions)

    # ---- fan ---------------------------------------------------------------------------
    def _start_fan(self) -> None:
        self.fan = HeadwindController(self.settings.fan_address, on_address=self.signals.fan_address.emit)

    def _fan(self, now: float, dt: float) -> None:
        if self.fan is None:
            return
        if now - self._fan_check > 2.0:  # pick up edits to fan.json without a restart
            self._fan_check = now
            m = self._profile_mtime()
            if m != self._fan_mtime:
                self._fan_mtime = m
                self.fan_profile.adopt(FanProfile.load(fan_profile_path()))
                self.flash("Fan profile reloaded")
        t = self.ride.telemetry
        self.fan.set_speed(self.fan_profile.update(now, dt, self.ride.pedaling, t.heart_rate,
                                                   self.ride.wbal.fraction()))

    @staticmethod
    def _profile_mtime() -> float:
        try:
            return fan_profile_path().stat().st_mtime
        except OSError:
            return 0.0

    def toggle_fan(self):
        self._toggle("fan")
        if self.settings.fan and self.fan is None:
            self.fan_profile = FanProfile.load(fan_profile_path())
            self._fan_mtime = self._profile_mtime()
            self._start_fan()
            self.flash("Fan on: looking for the KICKR Headwind")
        elif not self.settings.fan and self.fan is not None:
            self.fan.close()
            self.fan = None
            self.flash("Fan control off")

    def nudge_fan(self, delta: int):
        if self.fan is None:
            self.flash("Fan control is off")
            return
        self.fan_profile.nudge(delta)
        off = self.fan_profile.offset
        self.flash(f"Fan {'+' if off >= 0 else '−'}{abs(off)} %" if self.ride.pedaling else "Fan: start pedaling first")

    def now_playing_text(self):
        return self.music.text(time.monotonic(), self.settings.now_playing)

    def _wbal_warning(self) -> None:
        frac = self.ride.wbal.fraction()
        if frac is None or not self.settings.show_wbal:
            return
        if frac < WBAL_WARN and not self._wbal_warned:
            self._wbal_warned = True
            self.flash(f"W′ below {round(WBAL_WARN * 100)} %")
        elif frac > WBAL_REARM:
            self._wbal_warned = False

    # ---- ride recording and upload ---------------------------------------------------
    def _record(self) -> None:
        if not self.settings.record_rides:
            return
        r, t, now = self.ride, self.ride.telemetry, time.time()
        p = r.player
        lap = (id(p), p.index()) if p and not p.finished else None  # one lap per workout step
        speed = r.speed_kmh
        self.recorder.sample(now, r.pedaling, t.power, t.heart_rate, t.cadence,
                             None if speed is None else speed / 3.6, r.distance_km * 1000, lap,
                             r.target_watts())
        if self.recorder.active:
            idle = self.recorder.idle_s(now)
            if idle >= RIDE_IDLE_END_S or (p and p.finished and idle >= RIDE_DONE_END_S):
                self.finish_ride()

    def finish_ride(self, quitting: bool = False) -> None:
        result = self.recorder.finish()
        if result is None:
            return
        fit, meta = result
        self.flash(f"Ride saved ({fmt_time(meta['moving_s'])})")
        queued = self._queue_upload(fit, meta)
        if not quitting:
            self._show_card(fit, meta, queued)
        self.upload_pending(quitting)

    def _queue_upload(self, fit, meta) -> bool:
        if meta.get("demo"):  # never upload simulated rides
            return False
        if self.settings.icu_auto_upload and self.settings.icu_api_key:
            recorder.queue_upload(fit, {**meta, "external_id": f"sporterlay-{int(meta['start'])}"})
            return True
        return False

    # ---- end-of-ride card ------------------------------------------------------------
    def _show_card(self, fit, meta, queued: bool) -> None:
        s = self.settings
        try:
            sm = summarize(self.recorder.last_rows, s.ftp, s.w_prime_j, meta.get("name") or "", meta.get("start"))
        except Exception:
            log.exception("Ride summary failed")
            return
        if meta.get("demo"):
            status = "Demo ride: saved, not uploaded"
        elif queued:
            status = "Uploading to intervals.icu…"
        elif not s.icu_api_key:
            status = "Saved (no intervals.icu key)"
        else:
            status = "Saved (upload is off)"
        if meta.get("ramp"):
            sm.note = "Ramp test: demo, no eFTP" if meta.get("demo") else (
                "Ramp test: eFTP after upload" if queued else "Ramp test: upload it for an eFTP")
        self.card_state = {"summary": sm, "status": status, "fit": fit.name, "png": fit.with_suffix(".png"),
                           "until": 0.0, "shown": 0.0}
        self._save_card_png()
        if s.ride_card:
            self.toggle_card(show=True)

    def _save_card_png(self) -> None:
        c = self.card_state
        try:
            self.overlay.render_card_png(c["summary"], c["status"], c["png"])
        except Exception as e:
            log.warning("Could not save the ride card: %s", e)

    def _card_status(self, fit_name: str, status: str = "", note: str = "") -> None:
        c = self.card_state
        if not c or c["fit"] != fit_name:
            return
        if status:
            c["status"] = status
        if note:
            c["summary"].note = note
        self._save_card_png()
        self.overlay.refresh()

    def card(self):
        c = self.card_state
        if c and time.monotonic() < c["until"]:
            return c["summary"], c["status"]
        return None

    def toggle_card(self, show=None):
        c = self.card_state
        if c is None:
            self.flash("No ride saved yet")
            return
        if show is None:
            show = self.card() is None
        now = time.monotonic()
        c["until"], c["shown"] = (now + self.settings.ride_card_s, now) if show else (0.0, 0.0)
        self.overlay.refresh()

    def _card_tick(self, now: float) -> None:
        c = self.card_state
        if c and c["until"] and now >= c["until"]:
            c["until"] = 0.0
            self.overlay.refresh()
        elif c and c["until"] and self.ride.pedaling and now - c["shown"] >= CARD_PEDAL_HIDE_S:
            c["until"] = 0.0  # back on the bike
            self.overlay.refresh()

    # ---- FTP ramp test -----------------------------------------------------------------
    def start_ramp_test(self):
        wo = ramp_workout(self.settings.ftp)
        self.use_workout(wo)
        self.flash("Ramp test loaded: it starts when you pedal")

    def _ramp_tick(self) -> None:
        p = self.ride.player
        if self.ramp is None or p is None or p.workout is not self.ramp.workout:
            return
        t = self.ride.telemetry
        if self.ramp.update(time.monotonic(), p.elapsed, t.cadence, self.ride.target_watts()):
            self._ramp_over()

    def end_ramp_test(self):
        p = self.ride.player
        if self.ramp is None or p is None or p.workout is not self.ramp.workout or not self.ramp.in_ramp(p.elapsed):
            self.flash("No ramp in progress")
            return
        self.ramp.end()
        self._ramp_over()

    def _ramp_over(self) -> None:
        p = self.ride.player
        p.elapsed = self.ramp.cooldown_start
        if self.settings.beeps:
            self.beeper.play("finish")
        top = self.ramp.peak_step_w
        self.flash(f"Ramp over{f' at {top} W' if top else ''}: cool down")

    def _fetch_eftp(self, activity_id: str) -> None:
        """Wait for intervals.icu to analyse the ramp test, then re-read the FTP: intervals.icu raises
        it by itself when a ride's eFTP beats it (Sporterlay never writes it)."""
        key, athlete_id, sync = self.settings.icu_api_key, self.settings.icu_athlete_id, self.settings.icu_sync_ftp
        old_ftp = self.settings.ftp

        def work():
            client = IntervalsClient(key, athlete_id)
            deadline, error, eftp = time.monotonic() + EFTP_WAIT_S, None, None
            while time.monotonic() < deadline and eftp is None:
                try:
                    eftp = client.activity_eftp(activity_id)
                    error = None
                except Exception as e:
                    error = str(e)
                if eftp is None:
                    time.sleep(EFTP_POLL_S)
            if eftp is None:
                self.signals.eftp_done.emit(None, None, error or "intervals.icu has no eFTP for this ride")
                return
            athlete = None
            if sync:  # give intervals.icu's own FTP update a moment when it should happen
                for _ in range(EFTP_FTP_TRIES):
                    try:
                        athlete = client.athlete()
                    except Exception as e:
                        log.warning("Re-reading FTP after the ramp test: %s", e)
                    if athlete is None or not athlete.ftp or eftp <= old_ftp or athlete.ftp != old_ftp:
                        break
                    time.sleep(EFTP_POLL_S)
            self.signals.eftp_done.emit(eftp, athlete, None)

        threading.Thread(target=work, name="eftp", daemon=True).start()

    def _eftp_done(self, eftp, athlete, error):
        fit = self._ramp_fit
        if not eftp:
            log.warning("Ramp test eFTP: %s", error)
            self._card_status(fit, note="Ramp test: no eFTP from intervals.icu")
            self.flash("No eFTP from intervals.icu for the ramp test")
            return
        s, old = self.settings, self.settings.ftp
        log.info("Ramp test eFTP from intervals.icu: %d W (FTP was %d W)", eftp, old)
        if athlete and athlete.ftp:
            s.ftp = athlete.ftp
            if athlete.w_prime:
                s.w_prime_j = athlete.w_prime
            s.save()
        if s.ftp != old:
            msg = f"Ramp test: eFTP {eftp} W · FTP {old} → {s.ftp} W"
        elif athlete:
            msg = f"Ramp test: eFTP {eftp} W · FTP stays {s.ftp} W"
        else:
            msg = f"Ramp test: eFTP {eftp} W"
        self._card_status(fit, note=msg)
        self.tray.showMessage("Sporterlay", msg.replace("Ramp test: ", "Ramp test: intervals.icu "), self.icon, 8000)

    def _recover_rides(self) -> None:
        for fit, meta in recorder.recover(activities_dir()):
            self.tray.showMessage("Sporterlay", f"Recovered an unfinished ride: {fit.name}", self.icon, 4000)
            self._queue_upload(fit, meta)
        self.upload_pending()

    def upload_pending(self, quitting: bool = False) -> None:
        s = self.settings
        if self._uploading or not s.icu_api_key or not s.icu_auto_upload:
            return
        todo = recorder.pending_uploads(activities_dir())
        if not todo:
            return
        self._uploading = True
        key, athlete = s.icu_api_key, s.icu_athlete_id

        def work():
            client = IntervalsClient(key, athlete, timeout=60)
            done, error = [], None
            for fit, meta in todo:
                try:
                    aid = client.upload_activity(fit, meta.get("name") or "", meta.get("event_id"),
                                                 meta.get("external_id") or "")
                    recorder.mark_uploaded(fit)
                    done.append((fit.name, aid, meta))
                    log.info("Uploaded %s to intervals.icu (activity %s)", fit.name, aid)
                except Exception as e:
                    error = str(e)
                    log.warning("Upload of %s failed: %s", fit.name, e)
                    break  # probably offline: retry everything later
            self.signals.upload_done.emit(done, error)

        # when quitting, a non-daemon thread lets the upload finish after the window is gone
        threading.Thread(target=work, name="upload", daemon=not quitting).start()

    def _upload_done(self, done: list, error):
        self._uploading = False
        for fit_name, aid, meta in done:
            self._card_status(fit_name, "Uploaded to intervals.icu ✓")
            if meta.get("ramp") and aid:
                self._ramp_fit = fit_name
                self._card_status(fit_name, note="Ramp test: waiting for intervals.icu eFTP…")
                self._fetch_eftp(aid)
        if error:
            self.flash("Upload to intervals.icu failed, will retry")
            self.icu_status = "upload failed, will retry"
            if self.card_state and self.card_state["status"].startswith("Uploading"):
                self._card_status(self.card_state["fit"], "Upload failed, will retry")
            QTimer.singleShot(15000, lambda: setattr(self, "icu_status", ""))
        elif done:
            n = len(done)
            self.flash("Ride uploaded to intervals.icu" if n == 1 else f"{n} rides uploaded to intervals.icu")

    def save_ride_now(self):
        if not self.recorder.active:
            self.flash("Nothing recorded yet")
            return
        if self.recorder.samples < recorder.MIN_RIDE_S:
            self.flash(f"Too short to save yet (under {recorder.MIN_RIDE_S // 60} min)")
            return
        self.finish_ride()

    def reset_ride(self):
        self.finish_ride()
        self.ride.reset()

    def toggle_recording(self):
        self._toggle("record_rides")
        if not self.settings.record_rides:
            self.finish_ride()

    def set_w_prime(self):
        v, ok = QInputDialog.getDouble(None, "Sporterlay", "W′ (kJ), the work you can do above FTP:",
                                       self.settings.w_prime_j / 1000, 5, 60, 1)
        if ok:
            self.settings.w_prime_j = round(v * 1000)
            self.settings.save()

    def flash(self, text: str) -> None:
        """Briefly show an action confirmation in the status line."""
        self._flash = (text, time.monotonic() + FLASH_S)
        self.overlay.refresh()

    # ---- Zwift Click buttons -----------------------------------------------------------
    def click_action(self, button: str) -> str:
        key = self.settings.click_map.get(button) or DEFAULT_CLICK_MAP.get(button, "none")
        return key if key in ACTIONS else DEFAULT_CLICK_MAP.get(button, "none")

    def click_button(self, name: str):
        self.button_map.pressed(name)
        _, _, *call = ACTIONS[self.click_action(name)]
        if not call:
            log.info("Click button %s (not mapped)", name)
            return
        getattr(self, call[0])(*call[1:])

    def set_click_action(self, button: str, key: str):
        if key == DEFAULT_CLICK_MAP.get(button, "none"):
            self.settings.click_map.pop(button, None)
        else:
            self.settings.click_map[button] = key
        self.settings.save()
        self.button_map.flash(button)

    def reset_click_map(self):
        self.settings.click_map = {}
        self.settings.save()
        self.button_map.flash()

    def toggle_button_map(self):
        self.settings.show_button_map = not self.settings.show_button_map
        self.settings.save()
        self.button_map.flash(seconds=0)  # applies the toggle now, and cancels a pending flash

    def _click_map_status(self):
        if self.click is None:
            return "disabled"
        return None if self.click.connected else self.click.status.removeprefix("Click: ")

    def status_text(self):
        text, until = self._flash
        if text and time.monotonic() < until:
            return text
        t = self.ride.telemetry
        if not t.trainer_connected:
            return self.source.status
        bits = []
        if self.ride.iso:
            bits.append(f"Isokinetic {self.settings.iso_cadence} rpm ({self.ride.iso_speed_ms() * 3.6:.1f} km/h)")
        elif self.ride.player and not self.ride.player.finished:
            if self.ride.erg_waiting:
                bits.append(f"ERG starts at {self.ride.erg_thresholds()[0]} rpm")
            else:
                bits.append("ERG on" if self.settings.erg else "ERG off")
        if not t.hr_connected:
            bits.append("no heart rate")
        if self.click and not self.click.connected:
            bits.append(self.click.status)
        if self.zwift and not self.zwift.connected:
            bits.append(self.zwift.status)
        if self.fan and not self.fan.connected:
            bits.append(self.fan.status)
        p = self.ride.player
        if self.ramp and p and p.workout is self.ramp.workout and self.ramp.in_ramp(p.elapsed) and not self.ramp.ended:
            bits.append("Ramp test: keep going, under 60 rpm ends it")
        if self.web and self.web.error:
            bits.append(self.web.error)
        if self.icu_status:
            bits.append(self.icu_status)
        return " · ".join(bits) if bits else None

    # ---- shifting --------------------------------------------------------------------
    def shift(self, delta: int):
        if self.ride.iso:  # no gears in isokinetic mode: shifting changes the target cadence
            rpm = self.ride.set_iso_cadence(self.settings.iso_cadence + (5 if delta > 0 else -5))
            self.settings.save()
            self.flash(f"Isokinetic {rpm} rpm")
            return
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
            if athlete.w_prime:
                self.settings.w_prime_j = athlete.w_prime
            self.settings.save()
        today = [w for w in self.icu_workouts if w.date == dt.date.today()]
        busy = self.ride.player is not None and self.ride.player.started
        if startup and today and self.settings.icu_autoload_today and not busy:
            self.load_planned(today[0])
            self.tray.showMessage("Sporterlay", f"Today's workout loaded: {today[0].name}", self.icon, 4000)

    def load_planned(self, pw):
        self.use_workout(pw.workout, f"icu:{pw.event_id}")

    def use_workout(self, workout, key: str | None = None):
        """Load a workout (key: what to restore at next start; None = don't change it)."""
        p = self.ride.player
        if p is not None and p.finished and self.recorder.active:
            self.finish_ride()  # the previous workout is done: the next one is a new ride
        self.ride.load_workout(workout)
        self.ramp = RampTest(workout) if is_ramp_test(workout) else None
        event = int(key[4:]) if key and key.startswith("icu:") else None
        extra = {"ramp": True} if self.ramp else {}
        self.recorder.set_meta(("DEMO " if self.demo else "") + workout.name, event, **extra)
        if key is not None:
            self.settings.last_workout = key
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
            self.use_workout(match.workout)

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
            self.use_workout(dlg.chosen.workout, f"lib:{dlg.chosen.name}")

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
        self.use_workout(wo, str(path))

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

    def toggle_iso(self):
        self.ride.set_iso(not self.ride.iso)
        if self.ride.iso:
            rpm = self.ride.set_iso_cadence(self.settings.iso_cadence)
            self.flash(f"Isokinetic {rpm} rpm")
        else:
            self.flash("Isokinetic off: " + ("ERG" if self.ride.erg_wanted else "normal riding"))

    def set_iso_cadence(self, rpm: int):
        rpm = self.ride.set_iso_cadence(rpm)
        self.settings.save()
        if self.ride.iso:
            self.flash(f"Isokinetic {rpm} rpm")

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
        if self.settings.hud_mode == "hidden":
            self.flash("The HUD is set to hidden (tray → HUD)")  # shows on the second screen
            return
        self._hud_on = not self.overlay.isVisible()
        self._apply_hud()

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
        self.finish_ride(quitting=True)
        self.media.close()
        self.source.set_free_ride(0.0)
        self.settings.save()
        if self.hotkeys:
            self.hotkeys.unregister()
        self.source.close()
        if self.click:
            self.click.close()
        if self.zwift:
            self.zwift.close()
        if self.fan:
            self.fan.close()
        if self.web:
            self.web.close()
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
            act("Use FTP, weight and W′ from intervals.icu", lambda: self._toggle("icu_sync_ftp"),
                checked=s.icu_sync_ftp, menu=icu)
            act("Upload rides to intervals.icu", self._toggle_upload, checked=s.icu_auto_upload, menu=icu)
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
        act("FTP ramp test (+20 W/min until you can't)", self.start_ramp_test)
        m.addSeparator()
        act("Pause workout\tCtrl+Alt+P", self.toggle_pause,
            checked=bool(has and self.ride.player.paused), enabled=has)
        act("Next interval\tCtrl+Alt+N", self.skip, enabled=has)
        act("Previous / restart interval\tCtrl+Alt+B", self.back, enabled=has)
        act("ERG mode\tCtrl+Alt+E", self.toggle_erg, checked=s.erg)
        maker = getattr(self.source, "manufacturer_id", None)
        note = "" if maker in (None, 89) else "  (needs a Tacx Neo)"
        act(f"Isokinetic mode{note}\tCtrl+Alt+I", self.toggle_iso, checked=self.ride.iso)
        lo, hi = self.ride.iso_cadence_range()
        km = lambda rpm: self.ride._rpm_to_ms(rpm) * 3.6
        isom = m.addMenu(f"Isokinetic cadence: {s.iso_cadence} rpm")
        for rpm in sorted({lo, *range((lo + 4) // 5 * 5, hi + 1, 5), hi}):
            act(f"{rpm} rpm  ({km(rpm):.1f} km/h)", lambda rpm=rpm: self.set_iso_cadence(rpm),
                checked=rpm == s.iso_cadence, menu=isom)
        gm = m.addMenu(f"Gear {s.gear}/{len(self.ride.ratios)}   (Click or Ctrl+Alt+←/→)")
        act("Harder", lambda: self.shift(+1), menu=gm)
        act("Easier", lambda: self.shift(-1), menu=gm)
        act("Back to neutral gear", self._neutral_gear, menu=gm)
        gm.addSeparator()
        cs = self.click.status if self.click else "Zwift Click disabled"
        act(cs, lambda: None, enabled=False, menu=gm)
        bm = m.addMenu("Zwift Click buttons")
        act("Show button map\tCtrl+Alt+M", self.toggle_button_map, checked=s.show_button_map, menu=bm)
        for side, pod in (("Left", LEFT_POD), ("Right", RIGHT_POD)):
            bm.addSeparator()
            for name, _, desc in pod:
                cur = self.click_action(name)
                sub = bm.addMenu(f"{side} {desc}:  {ACTIONS[cur][0]}")
                grp = QActionGroup(sub)
                for key, (label, *_) in ACTIONS.items():
                    grp.addAction(act(label, lambda name=name, key=key: self.set_click_action(name, key),
                                      checked=key == cur, menu=sub))
        bm.addSeparator()
        act("Reset to defaults", self.reset_click_map, enabled=bool(s.click_map), menu=bm)
        im = m.addMenu(f"Intensity: {s.intensity}%   (Ctrl+Alt+↑/↓)")
        for v in (70, 80, 90, 95, 100, 105, 110, 120):
            act(f"{v}%", lambda v=v: self._set("intensity", v), checked=s.intensity == v, menu=im)
        m.addSeparator()
        act(f"FTP: {s.ftp} W…", self.set_ftp)
        act(f"Weight: {s.weight_kg:g} kg…", self.set_weight)
        act(f"W′: {s.w_prime_j / 1000:g} kJ…", self.set_w_prime)
        xm = m.addMenu("Extras")
        act("Beeps before interval changes", lambda: self._toggle("beeps"), checked=s.beeps, menu=xm)
        act("W′ balance gauge", self._toggle_wbal, checked=s.show_wbal, menu=xm)
        win = sys.platform == "win32"
        act("Pause the browser video when I stop pedaling" + ("" if win else "  (Windows only)"),
            lambda: self._toggle("autopause_video"), checked=s.autopause_video, enabled=win, menu=xm)
        npm = xm.addMenu("Spotify now playing" + ("" if win else "  (Windows only)"))
        npm.setEnabled(win)
        grp = QActionGroup(npm)
        for key, label in (("off", "Off"), ("change", "When the track changes"), ("always", "Always")):
            grp.addAction(act(label, lambda key=key: self._set("now_playing", key),
                              checked=s.now_playing == key, menu=npm))
        act("Share power, cadence and HR with Zwift", self.toggle_zwift_share, checked=s.zwift_share, menu=xm)
        fm = xm.addMenu("Fan (KICKR Headwind)")
        fan_state = ""
        if self.fan:
            fan_state = f"  ({self.fan.reported} %)" if self.fan.connected and self.fan.reported is not None \
                else f"  ({self.fan.status.removeprefix('Fan: ')})"
        act("Control the fan from HR and W′" + fan_state, self.toggle_fan, checked=s.fan, menu=fm)
        act("Edit fan profile (fan.json)…", self._edit_fan_profile, menu=fm)
        rm = m.addMenu("Rides")
        act("Record rides (.fit)", self.toggle_recording, checked=s.record_rides, menu=rm)
        rec = self.recorder
        act(f"Save ride now  ({fmt_time(rec.samples)} recorded)" if rec.active else "Save ride now",
            self.save_ride_now, enabled=rec.active, menu=rm)
        act("Open rides folder", lambda: self._open_folder(activities_dir()), menu=rm)
        act("Show last ride summary", self.toggle_card, enabled=self.card_state is not None, menu=rm)
        act("Ride summary when a ride ends", lambda: self._toggle("ride_card"), checked=s.ride_card, menu=rm)
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
        hm = m.addMenu("HUD")
        grp = QActionGroup(hm)
        for key, label in (("shown", "Shown"), ("hidden", "Hidden"),
                           ("auto", "Hidden while a second screen is open")):
            grp.addAction(act(label, lambda key=key: self.set_hud_mode(key), checked=s.hud_mode == key, menu=hm))
        hm.addSeparator()
        act("Show overlay\tCtrl+Alt+H", self.toggle_visible, checked=self.overlay.isVisible(),
            enabled=s.hud_mode != "hidden", menu=hm)
        wm2 = m.addMenu("Second screen (phone / tablet)")
        act("Show the ride on a phone or tablet", self.toggle_web_screen, checked=s.web_screen, menu=wm2)
        act("Address and QR code…", self.show_web_address, enabled=self.web is not None, menu=wm2)
        if self.web is not None:
            n = self.web.connected
            info = self.web.error or (f"{n} screen{'s' if n != 1 else ''} open" if n else self.web.url)
            act(info, lambda: None, enabled=False, menu=wm2)
        act("Reset ride (saves it, then resets time, distance, workout)", self.reset_ride)
        m.addSeparator()
        act("Quit", self.quit)

    def _toggle(self, key):
        self._set(key, not getattr(self.settings, key))

    def _toggle_wbal(self):
        self._toggle("show_wbal")
        self.overlay.refresh()  # width changes

    def toggle_zwift_share(self):
        self._toggle("zwift_share")
        if self.settings.zwift_share and self.zwift is None:
            self.zwift = ZwiftShare(self.signals.zwift.emit)
            self.flash("Sharing with Zwift: pair “Sporterlay” in Zwift")
        elif not self.settings.zwift_share and self.zwift is not None:
            self.zwift.close()
            self.zwift = None
            self.flash("Stopped sharing with Zwift")

    def _toggle_upload(self):
        self._toggle("icu_auto_upload")
        if self.settings.icu_auto_upload:
            self.upload_pending()

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

    def _edit_fan_profile(self):
        from PyQt6.QtCore import QUrl
        from PyQt6.QtGui import QDesktopServices

        path = fan_profile_path()
        if not path.exists():
            FanProfile.load(path)  # writes the defaults
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(path)))

    @staticmethod
    def _open_folder(path: Path):
        from PyQt6.QtCore import QUrl
        from PyQt6.QtGui import QDesktopServices

        path.mkdir(parents=True, exist_ok=True)
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(path)))

    def run(self) -> int:
        # Ctrl+C / kill: quit properly, so the ride is saved and the fan and Click let go.
        # Python only sees the signal when the interpreter runs, which the tick timer ensures.
        import signal

        def stop(*_):
            QTimer.singleShot(0, self.quit)

        signal.signal(signal.SIGINT, stop)
        if hasattr(signal, "SIGTERM"):
            signal.signal(signal.SIGTERM, stop)
        return self.qapp.exec()


def prefer_xwayland(env=os.environ) -> bool:
    """Linux Wayland session: run through XWayland unless the platform was chosen explicitly.
    Native Wayland ignores window placement, always-on-top and click-through, so the HUD would
    open as a normal window in the middle of the screen. Returns True if it switched."""
    if not sys.platform.startswith("linux") or env.get("QT_QPA_PLATFORM"):
        return False
    wayland = env.get("WAYLAND_DISPLAY") or env.get("XDG_SESSION_TYPE") == "wayland"
    if not wayland or not env.get("DISPLAY"):  # no XWayland to fall back on
        return False
    env["QT_QPA_PLATFORM"] = "xcb"
    return True


def main(argv=None) -> int:
    xwayland = prefer_xwayland()  # before any QApplication exists
    ap = argparse.ArgumentParser(prog="sporterlay", description="Smart trainer HUD overlay")
    ap.add_argument("--demo", action="store_true", help="simulate a trainer and HR strap (no ANT+ needed)")
    ap.add_argument("--workout", help="path to a .zwo workout to load")
    ap.add_argument("--ftp", type=int, help="override FTP for this session")
    ap.add_argument("--no-click", action="store_true", help="don't look for a Zwift Click")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args(argv)

    # One instance only: a second one would fight over the ANT+ stick, the Click and the hotkeys,
    # and truncate the running one's log. Check before any of that is touched.
    config_dir().mkdir(parents=True, exist_ok=True)
    lock = QLockFile(str(config_dir() / "sporterlay.lock"))
    if not lock.tryLock(0):
        _app = QApplication(sys.argv)
        QMessageBox.information(None, "Sporterlay",
                                "Sporterlay is already running.\n\n"
                                "Look for the orange S icon in the system tray (next to the clock).")
        return 1

    # pythonw / windowed .exe have no console: sys.stderr is None there
    handlers = [logging.StreamHandler()] if sys.stderr is not None else []
    try:
        config_dir().mkdir(parents=True, exist_ok=True)
        handlers.append(logging.FileHandler(config_dir() / "sporterlay.log", mode="w", encoding="utf-8"))
    except Exception:
        pass
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(name)s %(levelname)s %(message)s", handlers=handlers)
    if xwayland:
        log.info("Wayland session: using XWayland (QT_QPA_PLATFORM=xcb) so the HUD can stay on top")
    try:
        return App(args).run()
    finally:
        lock.unlock()
