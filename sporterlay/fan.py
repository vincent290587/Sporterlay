"""Wahoo KICKR Headwind fan driven by heart rate and W′ balance.

The Headwind's own speed mode needs a Wahoo KICKR, so the fan is put in manual mode and
Sporterlay sets its speed. Protocol (verified on a Headwind with firmware 1.0.3):
- It advertises by name only ("HEADWIND 70A2"), no service UUID, so it's found by name.
- Service a026ee0c-…, characteristic a026e038-… (read, write without response, notify).
- `04 04` = manual mode (acknowledged `fe 04 01 04`); entering manual mode restores the last
  manual speed, so the speed is sent right after.
- `02 <0..100>` = speed in % (acknowledged `fe 02 01 <speed>`).
- Status `fd 01 <speed %> <mode>` about once a second (mode 04 = manual, 01 = power-on default).

`FanProfile` is the pure logic (fan.json in the config folder):
    fan % = max(hr curve(heart rate), W′ curve(fraction of W′ used))
Heart rate follows the overall heat load; W′ reacts at once to efforts above CP, before the
heart rate catches up. `HeadwindController` keeps the BLE connection on its own thread.
"""

from __future__ import annotations

import asyncio
import json
import logging
import sys
import threading
from pathlib import Path
from typing import Callable, Optional

log = logging.getLogger(__name__)

CHAR = "a026e038-0a7d-4ab3-97fa-f1500f9feb8b"
NAME_PREFIX = "HEADWIND"
MANUAL_MODE = bytes([0x04, 0x04])

DEFAULT_PROFILE = {
    "hr": [[100, 20], [130, 40], [150, 70], [170, 100]],  # bpm -> fan %, linear in between
    "wbal": [[0.0, 0], [0.2, 50], [0.5, 80], [0.7, 100]],  # fraction of W′ used -> fan %
    "min": 20,  # % while riding (also with no heart rate and W′ full)
    "max": 100,
    "hr_smoothing_s": 10,
    "step": 5,  # round to steps so the speed doesn't wander
    "min_hold_s": 10,  # don't step down more often than this (stepping up is immediate)
    "off_after_stop_s": 60,
}


def interp(curve: list, x: float) -> float:
    """Piecewise-linear lookup, flat beyond the ends."""
    pts = sorted((float(a), float(b)) for a, b in curve)
    if not pts:
        return 0.0
    if x <= pts[0][0]:
        return pts[0][1]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0) if x1 > x0 else y1
    return pts[-1][1]


class FanProfile:
    def __init__(self, profile: Optional[dict] = None):
        self.p = {**DEFAULT_PROFILE, **(profile or {})}
        self._hr: Optional[float] = None  # smoothed heart rate
        self.speed = 0  # current fan %
        self._changed = -1e9  # when the speed last changed
        self._stopped_since: Optional[float] = None
        self._rode = False  # pedaled since the fan was last turned off
        self.offset = 0  # manual +/- from Click buttons, until the next stop

    @classmethod
    def load(cls, path: Path) -> "FanProfile":
        """Read fan.json, writing the defaults first if there is none (so it can be edited)."""
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(raw, dict):
                raise ValueError("not a JSON object")
            unknown = set(raw) - set(DEFAULT_PROFILE)
            if unknown:
                log.warning("fan.json: ignoring unknown keys %s", ", ".join(sorted(unknown)))
            return cls({k: v for k, v in raw.items() if k in DEFAULT_PROFILE})
        except FileNotFoundError:
            try:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(DEFAULT_PROFILE, indent=2), encoding="utf-8")
            except OSError as e:
                log.warning("Could not write %s: %s", path, e)
        except Exception as e:
            log.warning("Ignoring unreadable %s: %s", path, e)
        return cls()

    def adopt(self, other: "FanProfile") -> None:
        """Take another profile's settings (a reloaded fan.json) but keep the running state."""
        self.p = other.p

    def target(self, hr: Optional[float], wbal_fraction: Optional[float]) -> int:
        """Fan % the curves ask for, before holding and stopping."""
        p = self.p
        want = 0.0
        if hr is not None:
            want = max(want, interp(p["hr"], hr))
        if wbal_fraction is not None:
            want = max(want, interp(p["wbal"], 1.0 - wbal_fraction))
        want = min(max(want + self.offset, p["min"]), p["max"])
        step = max(1, int(p["step"]))
        return int(max(0, min(100, round(want / step) * step)))

    def update(self, now: float, dt: float, pedaling: bool, hr: Optional[float],
               wbal_fraction: Optional[float]) -> int:
        """Called every tick; returns the fan % to set."""
        p = self.p
        if hr is None:
            self._hr = None
        elif self._hr is None or p["hr_smoothing_s"] <= 0:
            self._hr = float(hr)
        else:
            self._hr += (hr - self._hr) * min(1.0, dt / p["hr_smoothing_s"])
        if pedaling:
            self._rode = True
            self._stopped_since = None
        elif self._rode:
            if self._stopped_since is None:
                self._stopped_since = now
            if now - self._stopped_since >= p["off_after_stop_s"]:
                self._rode, self.offset = False, 0
                return self._set(now, 0)
            return self.speed  # short stop: keep blowing
        else:
            return self._set(now, 0)
        want = self.target(self._hr, wbal_fraction)
        if want > self.speed or now - self._changed >= p["min_hold_s"]:
            return self._set(now, want)
        return self.speed

    def nudge(self, delta: int) -> None:
        """Manual +/- (Click button) on top of the curves, while riding; it lasts until the fan
        turns off after a stop and is applied at the next update, also downwards."""
        if self._rode:
            self.offset = max(-100, min(100, self.offset + delta))
            self._changed = -1e9

    def _set(self, now: float, speed: int) -> int:
        if speed != self.speed:
            self.speed, self._changed = speed, now
        return self.speed


class HeadwindController:
    """Keeps a connection to the Headwind on a background asyncio thread and sends the
    latest wanted speed. `set_speed()` is safe to call every tick (only changes are sent)."""

    def __init__(self, address: str = "", on_address: Optional[Callable[[str], None]] = None):
        self.address = address  # remembered after the first connection; "" = find by name
        self.on_address = on_address
        self.status = "Fan: searching"
        self.connected = False
        self.reported: Optional[int] = None  # speed the fan says it runs at
        self._want = 0
        self._wake = None  # asyncio.Event, created on the loop
        self._stop = threading.Event()
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._thread = threading.Thread(target=self._run, name="fan", daemon=True)
        self._thread.start()

    def set_speed(self, pct: int) -> None:
        pct = max(0, min(100, int(pct)))
        if pct != self._want:
            self._want = pct
            self._poke()

    def close(self, timeout: float = 5.0) -> None:
        """Turn the fan off and disconnect (BlueZ keeps connections of a dead process, and a
        connected Headwind stops advertising)."""
        self._want = 0
        self._stop.set()
        self._poke()
        self._thread.join(timeout)

    def _poke(self) -> None:
        if self._loop is not None and self._wake is not None:
            self._loop.call_soon_threadsafe(self._wake.set)

    # ---- background thread ---------------------------------------------------------
    def _run(self) -> None:
        try:
            import bleak  # noqa: F401
        except ImportError:
            self.status = "Fan: bleak not installed"
            return
        self._loop = asyncio.new_event_loop()
        try:
            self._loop.run_until_complete(self._main())
        except Exception as e:
            log.exception("Fan thread crashed")
            self.status = f"Fan error: {e}"
        finally:
            self._loop.close()

    async def _main(self) -> None:
        self._wake = asyncio.Event()
        await self._release_stale()
        failures = 0
        while not self._stop.is_set():
            device = await self._find()
            if device is None:
                continue
            try:
                await self._session(device)
                failures = 0
            except Exception as e:
                failures += 1
                if failures <= 2:
                    log.warning("Fan: %s", str(e) or e.__class__.__name__)
            finally:
                self.connected, self.reported = False, None
            if not self._stop.is_set():
                self.status = "Fan: reconnecting"
                await self._sleep(2)

    async def _sleep(self, s: float) -> None:
        try:
            await asyncio.wait_for(self._wake.wait(), s)
        except asyncio.TimeoutError:
            pass
        self._wake.clear()

    async def _find(self):
        from bleak import BleakScanner

        try:
            if self.address:
                d = await BleakScanner.find_device_by_address(self.address, timeout=5)
            else:
                d = await BleakScanner.find_device_by_filter(
                    lambda dev, adv: (adv.local_name or dev.name or "").upper().startswith(NAME_PREFIX),
                    timeout=5)
        except Exception as e:
            msg = str(e) or e.__class__.__name__
            log.debug("Fan scan: %s", msg)
            if "bluetooth" in msg.lower() and ("off" in msg.lower() or "not" in msg.lower()):
                self.status = "Fan: Bluetooth is off / no adapter"
            await self._sleep(3)
            return None
        if d is None:
            self.status = "Fan: not found (close the Wahoo app)"
        return d

    async def _session(self, device) -> None:
        from bleak import BleakClient

        self.status = "Fan: connecting"
        lost = asyncio.Event()
        async with BleakClient(device, timeout=20, disconnected_callback=lambda _c: self._loop.call_soon_threadsafe(
                lost.set)) as client:
            if device.address != self.address:
                self.address = device.address
                if self.on_address:
                    self.on_address(device.address)
            await client.start_notify(CHAR, self._on_notify)
            await client.write_gatt_char(CHAR, MANUAL_MODE, response=False)
            await asyncio.sleep(0.3)
            sent = None
            self.connected = True
            self.status = "Fan connected"
            log.info("Fan connected: %s %s", device.name, device.address)
            while not lost.is_set():
                want = self._want
                if want != sent:
                    await client.write_gatt_char(CHAR, bytes([0x02, want]), response=False)
                    log.debug("Fan: speed %d %%", want)
                    sent = want
                if self._stop.is_set():
                    await asyncio.sleep(0.3)  # let the "off" go out before disconnecting
                    return
                await self._sleep(1.0)
            raise ConnectionError("disconnected")

    def _on_notify(self, _handle, data: bytearray) -> None:
        if len(data) >= 4 and data[0] == 0xFD:
            self.reported = data[2]
            if data[3] != 0x04 and self.connected:  # someone (the button, the Wahoo app) changed mode
                log.info("Fan left manual mode (mode %d)", data[3])

    async def _release_stale(self) -> None:
        """See ClickController._release_stale: only Linux/BlueZ keeps a dead process's link."""
        if not self.address or not sys.platform.startswith("linux"):
            return
        try:
            proc = await asyncio.create_subprocess_exec(
                "bluetoothctl", "disconnect", self.address,
                stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
            await asyncio.wait_for(proc.wait(), timeout=5)
        except Exception:
            pass
