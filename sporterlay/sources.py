"""Data sources: the real ANT+ trainer/HR reader and a demo simulator.

Both expose the same small interface, polled by the UI:
    snapshot() -> Telemetry
    set_target_power(watts) / set_free_ride()   (trainer control)
    status -> str
"""

from __future__ import annotations

import logging
import math
import os
import random
import sys
import threading
import time
from dataclasses import dataclass
from typing import Optional

log = logging.getLogger(__name__)

STALE_S = 3.0  # values older than this are shown as "no data"


@dataclass
class Telemetry:
    power: Optional[int] = None  # W, instantaneous
    cadence: Optional[int] = None  # rpm
    speed_kmh: Optional[float] = None
    heart_rate: Optional[int] = None
    trainer_connected: bool = False
    hr_connected: bool = False


def _prepare_libusb() -> None:
    """On Windows pyusb needs libusb-1.0.dll; the libusb-package wheel ships one."""
    if sys.platform != "win32":
        return
    try:
        import libusb_package

        dll = libusb_package.get_library_path()
        if dll:
            d = os.path.dirname(str(dll))
            os.environ["PATH"] = d + os.pathsep + os.environ.get("PATH", "")
            if hasattr(os, "add_dll_directory"):
                os.add_dll_directory(d)
    except Exception as e:  # pragma: no cover - best effort
        log.warning("Could not locate bundled libusb: %s", e)
    _patch_usb_find()


def _patch_usb_find() -> None:
    """Let openant open sticks bound to libusb-win32 (libusb0.sys), not just WinUSB.

    libusb-1.0 lists a libusb0.sys device but can't open it (access denied), and the
    driver can't be swapped because other apps on the PC rely on it. openant calls
    usb.core.find() without a backend, so try each backend and return the first
    device that actually opens; libusb0.dll is installed with the libusb-win32 driver.
    """
    import usb.core
    import usb.util

    if getattr(usb.core.find, "_sporterlay", False):
        return
    orig_find = usb.core.find

    def backends():
        try:
            import libusb_package

            yield libusb_package.get_libusb1_backend()
        except Exception:
            pass
        try:
            import usb.backend.libusb0

            yield usb.backend.libusb0.get_backend()
        except Exception:
            pass

    def find(*args, **kwargs):
        if kwargs.get("backend") is not None or kwargs.get("find_all"):
            return orig_find(*args, **kwargs)
        for be in backends():
            if be is None:
                continue
            dev = orig_find(*args, backend=be, **kwargs)
            if dev is None:
                continue
            try:
                dev._ctx.managed_open()
            except usb.core.USBError as e:
                log.debug("USB %s can't open device via %s: %s", dev, type(be).__module__, e)
                usb.util.dispose_resources(dev)
                continue
            try:
                # libusb0 lets a second process open a stick that another app is using; only the
                # claim fails, and openant's read loop then spins on that error. Fail here instead.
                usb.util.claim_interface(dev, 0)
            except usb.core.USBError as e:
                raise usb.core.USBError(f"ANT+ dongle busy: {e}", errno=16) from e
            finally:
                usb.util.dispose_resources(dev)  # openant reopens it; don't hold a second handle
            log.debug("USB device opens via %s", type(be).__module__)
            if type(be).__module__.endswith("libusb0"):
                # usb_reset() makes the stick re-enumerate and invalidates the handle openant
                # keeps using ("device does not exist"). openant sends an ANT reset anyway.
                dev.reset = lambda: None
            return dev
        return orig_find(*args, **kwargs)

    find._sporterlay = True
    usb.core.find = find
    # libusb0 read timeouts arrive as a plain USBError (pyusb compares against Windows'
    # errno.ETIMEDOUT, not libusb-win32's 116), so openant warns about each idle second.
    logging.getLogger("openant.base.ant").addFilter(
        lambda r: "timeout error" not in r.getMessage()
    )


def _patch_openant() -> None:
    """Fix two openant channel problems that starve or kill the trainer/HR channels.

    - AntPlusDevice opens its channel with extended assignment 0x01 (background
      scanning). Such a channel never tracks the device's timeslot and only catches
      ~1 in 10 messages (measured 0.36/s vs 3.7/s from a 4 Hz HR strap), so assign
      plain channels instead.
    - When a wildcard search finds a device, openant closes the channel, pins its ID and
      reopens it straight away. A close only completes at EVENT_CHANNEL_CLOSED, so a fast
      stick (ANT USB2) rejects the reopen with CHANNEL_IN_WRONG_STATE and the node dies.
      Retry the open briefly.
    """
    from openant.devices.common import AntPlusDevice
    from openant.easy.channel import Channel

    if getattr(Channel.open, "_sporterlay", False):
        return
    orig_open_channel = AntPlusDevice.open_channel

    def open_channel(self, extended=True, channel_type=None, ext_assign=None):
        return orig_open_channel(self, extended, channel_type, ext_assign)

    AntPlusDevice.open_channel = open_channel
    orig_open = Channel.open

    def open_(self):
        deadline = time.monotonic() + 2.0
        while True:
            try:
                return orig_open(self)
            except Exception as e:
                if "CHANNEL_IN_WRONG_STATE" not in str(e) or time.monotonic() > deadline:
                    raise
                time.sleep(0.05)

    open_._sporterlay = True
    Channel.open = open_


class AntSource:
    """Reads an ANT+ FE-C trainer and an ANT+ heart-rate strap; can set ERG / sim mode."""

    def __init__(self, fe_device_id: int = 0, hr_device_id: int = 0):
        self.fe_device_id = fe_device_id
        self.hr_device_id = hr_device_id
        self.status = "Starting ANT+…"
        self._lock = threading.Lock()
        self._power = (None, 0.0)  # (value, timestamp)
        self._cadence = (None, 0.0)
        self._speed = (None, 0.0)
        self._hr = (None, 0.0)
        self._node = None
        self._fe = None
        self._stop = threading.Event()
        self._last_cmd: Optional[tuple] = None
        self._pending: Optional[tuple] = None
        self._config = (75.0, 9.0, 2.096, 0.0)  # rider kg, bike kg, wheel circumference m, gear ratio
        self._iso_on = False
        self._config_dirty = False
        self._cmd_cv = threading.Condition()
        threading.Thread(target=self._sender, name="ant-tx", daemon=True).start()
        self._thread = threading.Thread(target=self._run, name="ant", daemon=True)
        self._thread.start()

    # ---- ANT thread -------------------------------------------------------
    def _run(self) -> None:
        _prepare_libusb()
        while not self._stop.is_set():
            try:
                self._run_node()
            except Exception as e:
                msg = str(e) or e.__class__.__name__
                if "DriverNotFound" in e.__class__.__name__ or "not found" in msg.lower():
                    self.status = "No ANT+ dongle found"
                elif getattr(e, "errno", None) in (13, 16) or "access denied" in msg.lower() or "busy" in msg.lower():
                    # Windows: another app (Zwift, Garmin Express…) holds the stick.
                    # Linux: missing udev rule.
                    self.status = "ANT+ dongle busy / no access (close Zwift etc., see README)"
                elif "not supported" in msg.lower() or "unimplemented" in msg.lower():
                    # Windows: the stick has no usable driver (neither WinUSB nor libusb-win32).
                    self.status = "ANT+ dongle needs a USB driver (Zadig, see README)"
                elif "NoBackend" in e.__class__.__name__:
                    self.status = "libusb missing (see README)"
                else:
                    self.status = f"ANT+ error: {msg}"
                log.warning("ANT+ node stopped: %r", e)
            finally:
                self._fe = None
                if self._node is not None:
                    try:
                        self._node.stop()
                    except Exception:
                        pass
                    self._node = None
            self._stop.wait(3.0)  # retry, e.g. dongle plugged in later

    def _run_node(self) -> None:
        from openant.devices import ANTPLUS_NETWORK_KEY
        from openant.devices.fitness_equipment import FitnessEquipment
        from openant.devices.heart_rate import HeartRate
        from openant.easy.node import Node

        _patch_openant()
        node = Node()
        self._node = node
        node.set_network_key(0x00, ANTPLUS_NETWORK_KEY)

        fe = FitnessEquipment(node, device_id=self.fe_device_id)
        hr = HeartRate(node, device_id=self.hr_device_id)

        def on_fe(page, page_name, data):
            now = time.monotonic()
            with self._lock:
                if page_name == "standard_power":  # FE-C page 0x19 (trainer data)
                    self._power = (int(data.instantaneous_power), now)
                    if data.cadence != 255:
                        self._cadence = (int(data.cadence), now)
                elif page_name == "general_fe":  # page 0x10
                    if data.speed < 65.535:
                        self._speed = (data.speed * 3.6, now)

        def on_hr(page, page_name, data):
            if page_name == "heart_rate" and data.heart_rate:
                with self._lock:
                    self._hr = (int(data.heart_rate), time.monotonic())

        def fe_found():
            log.info("Trainer found: %s (manufacturer id %s; Tacx = 89)", fe, fe.data["common"].manufacturer_id)
            self._fe = fe
            self._last_cmd = None  # resend current mode
            self._config_dirty = True
            with self._cmd_cv:
                self._cmd_cv.notify()

        fe.on_device_data = on_fe
        fe.on_found = fe_found
        hr.on_device_data = on_hr
        hr.on_found = lambda: log.info("HR strap found: %s", hr)

        self.status = "Searching for trainer…"
        node.start()  # blocks until node.stop()

    # ---- UI thread ---------------------------------------------------------
    def _fresh(self, pair, now):
        v, ts = pair
        return v if v is not None and now - ts < STALE_S else None

    def snapshot(self) -> Telemetry:
        now = time.monotonic()
        with self._lock:
            p = self._fresh(self._power, now)
            c = self._fresh(self._cadence, now)
            s = self._fresh(self._speed, now)
            h = self._fresh(self._hr, now)
        trainer = p is not None or s is not None
        if trainer:
            self.status = "Trainer connected"
        elif self._node is not None and self.status == "Trainer connected":
            self.status = "Searching for trainer…"
        return Telemetry(p, c, s, h, trainer, h is not None)

    def set_target_power(self, watts: int) -> None:
        watts = int(max(0, min(watts, 2000)))
        self._send(("erg", watts))

    def set_free_ride(self, grade: float = 0.0) -> None:
        self._send(("sim", round(grade, 1)))

    def set_isokinetic(self, speed_ms: float) -> None:
        """Tacx Neo isokinetic mode: the trainer holds the flywheel at this speed (4.2–8.4 m/s)."""
        self._send(("iso", int(round(min(8.4, max(4.2, speed_ms)) / 0.05))))

    @property
    def manufacturer_id(self) -> Optional[int]:
        fe = self._fe
        m = fe.data["common"].manufacturer_id if fe is not None else 0xFFFF
        return None if m == 0xFFFF else m

    def configure(self, rider_kg: float, bike_kg: float, wheel_m: float = 2.096, gear_ratio: float = 0.0) -> None:
        """Rider/bike mass, wheel size and real gear for the trainer (sent when the trainer is found)."""
        config = (rider_kg, bike_kg, wheel_m, gear_ratio)
        if config != self._config:
            self._config = config
            self._config_dirty = True
            with self._cmd_cv:
                self._cmd_cv.notify()

    def _send(self, cmd: tuple) -> None:
        if self._fe is None or cmd == self._last_cmd:
            return
        self._last_cmd = cmd
        log.debug("trainer command %s", cmd)
        with self._cmd_cv:
            self._pending = cmd  # only the latest command matters
            self._cmd_cv.notify()

    def _sender(self) -> None:
        # Acknowledged sends can block for a while, so they run on their own thread.
        while not self._stop.is_set():
            with self._cmd_cv:
                # Without a trainer there's nothing to send: wait (fe_found() notifies). Checking
                # only for work here made the thread spin at 100 % CPU until a trainer was found,
                # because configure() marks the config dirty at startup.
                while not self._stop.is_set() and (
                        self._fe is None or (self._pending is None and not self._config_dirty)):
                    self._cmd_cv.wait(1.0)
                cmd, self._pending = self._pending, None
                fe = self._fe
            if fe is None:
                continue  # stopping
            if self._config_dirty:
                self._config_dirty = False
                self._send_config(fe, *self._config)
            if cmd is not None:
                self._send_now(fe, cmd)

    @staticmethod
    def _send_config(fe, rider_kg: float, bike_kg: float, wheel_m: float, gear_ratio: float) -> None:
        from .shifting import WIND_K

        try:
            # page 55 user configuration: rider 0.01 kg, bike 0.05 kg (12 bit), wheel diameter in
            # 0.01 m plus a 0–9 mm offset (from wheel_m, so the trainer's speed and isokinetic
            # speed use the same wheel as Sporterlay), gear ratio front/rear in 0.03 (0 = unknown)
            u = int(round(rider_kg * 100))
            b = int(round(bike_kg / 0.05)) & 0xFFF
            d_mm = int(round(wheel_m / math.pi * 1000))
            g = min(255, int(round(gear_ratio / 0.03)))
            fe.send_acknowledged_data([0x37, u & 0xFF, (u >> 8) & 0xFF, 0xFF, (d_mm % 10) | ((b & 0xF) << 4), b >> 4,
                                       d_mm // 10, g])
            # page 50 wind resistance: coefficient 0.01 kg/m, no wind (127 = 0 km/h), drafting 1.00
            fe.send_acknowledged_data([0x32, 0xFF, 0xFF, 0xFF, 0xFF, int(round(WIND_K * 100)), 127, 100])
        except Exception as e:
            log.warning("Trainer config failed: %s", e)

    def _send_now(self, fe, cmd: tuple) -> None:
        try:
            # Tacx proprietary FE-C page 0xFC ("Neo modes"): [0xFC, 0, isokinetic on, speed in
            # 0.05 m/s, 0, road surface (0 = off), intensity (0xFF = default), 0].
            # Isokinetic overrides ERG / sim, so switch it off before going back to them.
            if cmd[0] == "iso":
                fe.send_acknowledged_data([0xFC, 0x00, 0x01, cmd[1], 0x00, 0x00, 0xFF, 0x00])
                self._iso_on = True
                return
            if self._iso_on:
                fe.send_acknowledged_data([0xFC, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00])
                self._iso_on = False
            if cmd[0] == "erg":
                fe.set_target_power(cmd[1])  # FE-C page 49
            else:
                # FE-C page 51 "track resistance": grade in 0.01 % with -200 % offset,
                # rolling resistance in 5e-5 units (must match shifting.CRR).
                from .shifting import CRR

                g = int(round((cmd[1] + 200.0) * 100))
                crr = int(round(CRR / 5e-5))
                fe.send_acknowledged_data([0x33, 0xFF, 0xFF, 0xFF, 0xFF, g & 0xFF, (g >> 8) & 0xFF, crr])
        except Exception as e:
            log.warning("Trainer command %s failed: %s", cmd, e)

    def close(self) -> None:
        self._stop.set()
        node = self._node
        if node is not None:
            try:
                node.stop()
            except Exception:
                pass


class DemoSource:
    """Fake rider for testing without hardware.

    ERG: power follows the target. Simulation mode: the rider holds ~88 rpm in a
    50x17, so trainer speed comes from cadence and power from the grade, like a real
    trainer.
    """

    WHEEL_M = 2.096
    REAL_RATIO = 50 / 17

    def __init__(self, ftp: int = 250):
        self.status = "Demo mode"
        self._target = ftp * 0.6
        self._mode = "sim"
        self._grade = 0.0
        self._mass = 84.0
        self._t0 = time.monotonic()
        self._power = self._target

    def snapshot(self) -> Telemetry:
        from .shifting import AERO_K, CRR, G_ACC

        t = time.monotonic() - self._t0
        cad = int(88 + 4 * math.sin(t / 7) + random.gauss(0, 1))
        v = cad * self.REAL_RATIO * self.WHEEL_M / 60  # m/s
        if self._mode == "iso":  # trainer holds the speed; the rider pushes hard against it
            v = self._iso_speed
            cad = int(v * 60 / (self.REAL_RATIO * self.WHEEL_M))
            want = 320 + 25 * math.sin(t / 3)
        elif self._mode == "sim":
            want = (self._mass * G_ACC * (self._grade / 100 + CRR) + AERO_K * v * v) * v
        else:
            want = self._target
        self._power += (max(0.0, want) - self._power) * 0.35
        p = max(0, int(self._power + random.gauss(0, 6)))
        hr = int(95 + 0.28 * self._power + 3 * math.sin(t / 11))
        return Telemetry(p, cad, v * 3.6, hr, True, True)

    def set_target_power(self, watts: int) -> None:
        self._mode, self._target = "erg", watts

    def set_free_ride(self, grade: float = 0.0) -> None:
        self._mode, self._grade = "sim", grade

    def set_isokinetic(self, speed_ms: float) -> None:
        self._mode, self._iso_speed = "iso", min(8.4, max(4.2, speed_ms))

    manufacturer_id = 89  # pretend to be a Tacx

    def configure(self, rider_kg: float, bike_kg: float, wheel_m: float = 2.096, gear_ratio: float = 0.0) -> None:
        self._mass = rider_kg + bike_kg

    def close(self) -> None:
        pass
