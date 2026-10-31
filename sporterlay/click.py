"""Zwift Click (v2, also v1) over Bluetooth LE, as virtual shift buttons.

Protocol (reverse-engineered by the community, see README credits):
- Custom service 00000001-19ca-4651-86e5-fa29dcdd09d1. Notifications arrive on …0002,
  we write on …0003, the device answers handshakes on …0004.
- Advertisement manufacturer data (company 0x094A, Zwift) first byte = device type:
  0x09 Click v1, 0x0A Click v2 right, 0x0B Click v2 left.
- v2: write b"RideOn\\x02\\x03", 00 08 00, 00 08 10, then b"RideOn" every 3 s as keep-alive.
  Button frames start with 0x23, then protobuf field 1 = bitmask where a *cleared*
  bit means pressed: 0x1000 shift up (right pod), 0x100 shift down (left pod); the
  right pod also has z/y/a/b (0x80/0x40/0x10/0x20).
  Verified on hardware: the LEFT pod's connection carries both pods' buttons, the
  RIGHT pod's connection only its own. So we connect to every pod that's awake and
  ignore the right connection while the left one is up (else right presses double).
  A v2 that was never paired with the Zwift app answers with 0xFF (locked) and stays silent.
- v1: write b"RideOn"; frames start with 0x37, field 1 = plus, field 2 = minus (0 = pressed).
"""

from __future__ import annotations

import asyncio
import logging
import sys
import threading
import time
from typing import Callable, Optional

log = logging.getLogger(__name__)

SERVICE = "00000001-19ca-4651-86e5-fa29dcdd09d1"
CHAR_NOTIFY = "00000002-19ca-4651-86e5-fa29dcdd09d1"
CHAR_WRITE = "00000003-19ca-4651-86e5-fa29dcdd09d1"
CHAR_INDICATE = "00000004-19ca-4651-86e5-fa29dcdd09d1"
ZWIFT_COMPANY_ID = 0x094A
TYPE_V1, TYPE_V2_RIGHT, TYPE_V2_LEFT = 0x09, 0x0A, 0x0B
RIDE_ON = b"RideOn"
V2_ACTIVATION = [RIDE_ON + bytes([0x02, 0x03]), bytes([0x00, 0x08, 0x00]), bytes([0x00, 0x08, 0x10])]
V2_BITS = {
    0x1: "dpad_left", 0x2: "dpad_up", 0x4: "dpad_right", 0x8: "dpad_down",
    0x10: "a", 0x20: "b", 0x40: "y", 0x80: "z",
    0x100: "shift_down", 0x1000: "shift_up",
}
SHIFT = {"shift_up": +1, "shift_down": -1}


def _varint(data: bytes, i: int) -> tuple[int, int]:
    result = shift = 0
    while True:
        b = data[i]
        i += 1
        result |= (b & 0x7F) << shift
        if not b & 0x80:
            return result, i
        shift += 7


def decode_fields(payload: bytes) -> dict[int, int]:
    """Varint-only protobuf fields after the 1-byte message type."""
    out, i = {}, 1
    try:
        while i < len(payload):
            tag, i = _varint(payload, i)
            if tag & 0x7 != 0:
                break  # not a varint field: not a frame shape we know
            val, i = _varint(payload, i)
            out[tag >> 3] = val
    except IndexError:
        pass
    return out


def pressed_buttons(frame: bytes) -> Optional[set[str]]:
    """Names of the buttons currently pressed (see V2_BITS), or None if not a button frame."""
    if not frame:
        return None
    f = decode_fields(frame)
    if frame[0] == 0x23 and 1 in f:
        mask = f[1]
        return {name for bit, name in V2_BITS.items() if not mask & bit}
    if frame[0] == 0x37 and (1 in f or 2 in f):  # Click v1: field 1 = plus, field 2 = minus
        return {n for n, k in (("shift_up", 1), ("shift_down", 2)) if f.get(k, 1) == 0}
    return None


class ClickController:
    """Runs a bleak asyncio loop in a background thread, keeps a connection to every Click
    pod that is awake, and reconnects forever.

    on_shift(+1 | -1) and on_button(name) are called from that thread on each button *press*.
    """

    def __init__(self, on_shift: Callable[[int], None], on_button: Optional[Callable[[str], None]] = None,
                 known: Optional[dict[str, int]] = None, on_known: Optional[Callable[[dict], None]] = None):
        self.on_shift = on_shift
        self.on_button = on_button
        # pods seen before (address -> device type); on Linux, released at startup if a previous
        # run left them connected (see _release_stale).
        self.known: dict[str, int] = dict(known or {})
        self.on_known = on_known
        self.status = "Click: starting…"
        self._sessions: dict[str, Optional[int]] = {}  # address -> device type, while connected
        self._busy: set[str] = set()  # addresses being connected or connected
        self._pressed: dict[str, set[str]] = {}
        self._tasks: set[asyncio.Task] = set()
        self._stop = threading.Event()
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._thread_obj = threading.Thread(target=self._thread, name="click", daemon=True)
        self._thread_obj.start()

    @property
    def connected(self) -> bool:
        return bool(self._sessions)

    def close(self, timeout: float = 4.0) -> None:
        """Stop and disconnect cleanly (otherwise the OS may keep the pods connected, and a
        connected pod stops advertising)."""
        self._stop.set()
        self._thread_obj.join(timeout)

    def _update_status(self) -> None:
        if not self._sessions:
            self.status = "Click: searching (press a button to wake it)"
            return
        names = sorted({_side(t) for t in self._sessions.values()})
        self.status = "Click " + " + ".join(names) + " connected"

    def _left_connected(self) -> bool:
        return TYPE_V2_LEFT in self._sessions.values()

    # ---- background thread ----------------------------------------------------
    def _thread(self) -> None:
        try:
            import bleak  # noqa: F401
        except ImportError:
            self.status = "Click: bleak not installed"
            return
        self._loop = asyncio.new_event_loop()
        try:
            self._loop.run_until_complete(self._main())
        except Exception as e:
            log.exception("Click thread crashed")
            self.status = f"Click error: {e}"

    async def _main(self) -> None:
        from bleak import BleakScanner

        # BlueZ (and some Windows adapters) connect slowly or time out while a scan is running,
        # so scanning happens in short windows and connection setup takes turns with it.
        self._connect_lock = asyncio.Lock()
        found: list = []

        def cb(device, adv):
            if device.address in self._busy:
                return
            md = adv.manufacturer_data.get(ZWIFT_COMPANY_ID)
            name = device.name or adv.local_name or ""
            if md and md[0] in (TYPE_V1, TYPE_V2_RIGHT, TYPE_V2_LEFT):
                self._busy.add(device.address)
                found.append((device, md[0]))
            elif "zwift click" in name.lower():
                self._busy.add(device.address)
                found.append((device, None))

        self._update_status()
        await self._release_stale(list(self.known))

        while not self._stop.is_set():
            try:
                async with self._connect_lock:
                    async with BleakScanner(detection_callback=cb):
                        for _ in range(8):  # up to 2 s, less if something turns up
                            if found or self._stop.is_set():
                                break
                            await asyncio.sleep(0.25)
                while found:
                    self._spawn(self._run_session(*found.pop(0)))
                await asyncio.sleep(0.1)  # let new sessions queue for the lock before the next scan
            except Exception as e:
                msg = str(e) or e.__class__.__name__
                log.warning("Click scanner: %s", msg)
                if "bluetooth" in msg.lower() and ("off" in msg.lower() or "not" in msg.lower()):
                    self.status = "Click: Bluetooth is off / no adapter"
                await asyncio.sleep(3)
        # stopping: let every session leave so the pods get disconnected
        if self._tasks:
            await asyncio.wait(self._tasks, timeout=3.0)

    @staticmethod
    async def _release_stale(addresses: list[str]) -> None:
        """A pod left connected to the OS (e.g. after a crash) doesn't advertise, so it can't be
        found again. Linux/BlueZ keeps such connections after the process dies; Windows drops
        them, so this is only needed on Linux."""
        if not addresses or not sys.platform.startswith("linux"):
            return
        for addr in addresses:
            try:
                proc = await asyncio.create_subprocess_exec(
                    "bluetoothctl", "disconnect", addr,
                    stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
                await asyncio.wait_for(proc.wait(), timeout=5)
            except Exception:
                pass  # no bluetoothctl, or not connected: nothing to release

    def _spawn(self, coro) -> None:
        task = asyncio.create_task(coro)
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)

    async def _run_session(self, device, dev_type, timeout: float = 20.0) -> None:
        addr = device.address
        try:
            await self._session(device, dev_type, timeout)
        except Exception as e:
            log.warning("Click %s: %s", _side(dev_type), str(e) or e.__class__.__name__)
        finally:
            self._sessions.pop(addr, None)
            self._pressed.pop(addr, None)
            self._update_status()
            if not self._stop.is_set():
                await asyncio.sleep(2)  # don't grab the lingering advertisement right away
            self._busy.discard(addr)

    async def _session(self, device, dev_type, timeout: float) -> None:
        from bleak import BleakClient

        kind = "v1" if dev_type == TYPE_V1 else "v2"
        addr = device.address
        disconnected = asyncio.Event()
        locked = asyncio.Event()

        def on_disconnect(_):
            self._loop.call_soon_threadsafe(disconnected.set)

        def on_indicate(_, data: bytearray):
            if data[:1] == b"\xff":
                locked.set()

        client = BleakClient(device, disconnected_callback=on_disconnect, timeout=timeout)
        try:
            async with self._connect_lock:  # no scanning while we connect
                if self._stop.is_set():
                    return
                if not self._sessions:
                    self.status = f"Click {_side(dev_type)}: connecting…"
                await client.connect()
                await client.start_notify(CHAR_NOTIFY, lambda _, d: self._on_frame(addr, dev_type, bytes(d)))
                try:
                    await client.start_notify(CHAR_INDICATE, on_indicate)
                except Exception:
                    pass
                await asyncio.sleep(0.5)  # needed before the writes, or only one press ever arrives
                for w in ([RIDE_ON] if kind == "v1" else V2_ACTIVATION):
                    await client.write_gatt_char(CHAR_WRITE, w, response=False)
                    await asyncio.sleep(0.3)
            self._sessions[addr] = dev_type
            self._update_status()
            log.info("Zwift Click %s %s connected (%s)", kind, _side(dev_type), addr)
            if dev_type is not None and self.known.get(addr) != dev_type:
                self.known[addr] = dev_type
                if self.on_known:
                    self.on_known(dict(self.known))

            last_keepalive = time.monotonic()
            while not disconnected.is_set() and not self._stop.is_set():
                if locked.is_set():
                    self.status = f"Click {_side(dev_type)} is locked: pair it once with the Zwift app"
                try:  # short waits so close() is quick
                    await asyncio.wait_for(disconnected.wait(), timeout=0.5)
                except asyncio.TimeoutError:
                    if kind == "v2" and time.monotonic() - last_keepalive >= 3.0:
                        last_keepalive = time.monotonic()
                        await client.write_gatt_char(CHAR_WRITE, RIDE_ON, response=False)
        finally:
            try:
                await client.disconnect()
            except Exception:
                pass
        log.info("Zwift Click %s disconnected", _side(dev_type))

    def _on_frame(self, addr: str, dev_type, frame: bytes) -> None:
        now = pressed_buttons(frame)
        if now is None:
            return
        if dev_type == TYPE_V2_RIGHT and self._left_connected():
            return  # the left pod's connection already carries these presses
        new = now - self._pressed.get(addr, set())
        self._pressed[addr] = now
        for b in sorted(new):  # fire on press edges only
            try:
                if b in SHIFT:
                    self.on_shift(SHIFT[b])
                elif self.on_button:
                    self.on_button(b)
            except Exception:
                log.exception("Click button handler failed")


def _side(dev_type) -> str:
    return {TYPE_V2_RIGHT: "right", TYPE_V2_LEFT: "left", TYPE_V1: "v1"}.get(dev_type, "pod")
