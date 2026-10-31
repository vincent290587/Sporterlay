"""Zwift Click (v2, also v1) over Bluetooth LE, as virtual shift buttons.

Protocol (reverse-engineered by the community, see README credits):
- Custom service 00000001-19ca-4651-86e5-fa29dcdd09d1. Notifications arrive on …0002,
  we write on …0003, the device answers handshakes on …0004.
- Advertisement manufacturer data (company 0x094A, Zwift) first byte = device type:
  0x09 Click v1, 0x0A Click v2 right, 0x0B Click v2 left.
- v2: write b"RideOn\\x02\\x03", 00 08 00, 00 08 10, then b"RideOn" every 3 s as keep-alive.
  Button frames start with 0x23, then protobuf field 1 = bitmask where a *cleared*
  bit means pressed: 0x1000 shift up, 0x100 shift down. Pressing the other pod also
  shows up on this connection, so we only connect one pod.
  A v2 that was never paired with the Zwift app answers with 0xFF (locked) and stays silent.
- v1: write b"RideOn"; frames start with 0x37, field 1 = plus, field 2 = minus (0 = pressed).
"""

from __future__ import annotations

import asyncio
import logging
import threading
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
V2_BIT_UP, V2_BIT_DOWN = 0x1000, 0x100


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
    """Set of currently pressed buttons ("up"/"down"), or None if not a button frame."""
    if not frame:
        return None
    f = decode_fields(frame)
    if frame[0] == 0x23 and 1 in f:
        mask = f[1]
        return {n for n, bit in (("up", V2_BIT_UP), ("down", V2_BIT_DOWN)) if not mask & bit}
    if frame[0] == 0x37 and (1 in f or 2 in f):
        return {n for n, k in (("up", 1), ("down", 2)) if f.get(k, 1) == 0}
    return None


class ClickController:
    """Runs a bleak asyncio loop in a background thread; reconnects forever.

    on_shift(+1 | -1) is called from that thread on each button *press*.
    """

    def __init__(self, on_shift: Callable[[int], None], side: str = "right"):
        self.on_shift = on_shift
        self.prefer = TYPE_V2_LEFT if side == "left" else TYPE_V2_RIGHT
        self.status = "Click: starting…"
        self.connected = False
        self._pressed: set[str] = set()
        self._stop = threading.Event()
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        threading.Thread(target=self._thread, name="click", daemon=True).start()

    def close(self) -> None:
        self._stop.set()

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
        while not self._stop.is_set():
            try:
                found = await self._scan()
                if found:
                    await self._session(*found)
            except Exception as e:
                msg = str(e) or e.__class__.__name__
                log.warning("Click: %s", msg)
                if "bluetooth" in msg.lower() and ("off" in msg.lower() or "not" in msg.lower()):
                    self.status = "Click: Bluetooth is off / no adapter"
                else:
                    self.status = f"Click: {msg[:60]}"
            self.connected = False
            self._pressed.clear()
            await asyncio.sleep(2)

    async def _scan(self):
        from bleak import BleakScanner

        self.status = "Click: searching (press a button to wake it)"
        seen: dict[str, tuple] = {}

        def cb(device, adv):
            md = adv.manufacturer_data.get(ZWIFT_COMPANY_ID)
            name = (device.name or adv.local_name or "")
            if md and md[0] in (TYPE_V1, TYPE_V2_RIGHT, TYPE_V2_LEFT):
                seen[device.address] = (device, md[0])
            elif "zwift click" in name.lower() and device.address not in seen:
                seen[device.address] = (device, None)

        async with BleakScanner(detection_callback=cb):
            # look for a few seconds so we can prefer the configured pod if both are awake
            for _ in range(40):
                await asyncio.sleep(0.25)
                if self._stop.is_set():
                    return None
                if any(t == self.prefer for _, t in seen.values()):
                    break
                if seen and _ >= 12:
                    break
        if not seen:
            return None
        ranked = sorted(seen.values(), key=lambda dt: (dt[1] != self.prefer, dt[1] is None))
        return ranked[0]

    async def _session(self, device, dev_type) -> None:
        from bleak import BleakClient

        kind = "v1" if dev_type == TYPE_V1 else "v2"
        side = {TYPE_V2_RIGHT: " right", TYPE_V2_LEFT: " left"}.get(dev_type, "")
        self.status = f"Click{side}: connecting…"
        disconnected = asyncio.Event()
        locked = asyncio.Event()

        def on_disconnect(_):
            self._loop.call_soon_threadsafe(disconnected.set)

        def on_indicate(_, data: bytearray):
            if data[:1] == b"\xff":
                locked.set()

        async with BleakClient(device, disconnected_callback=on_disconnect) as client:
            await client.start_notify(CHAR_NOTIFY, lambda _, d: self._on_frame(bytes(d)))
            try:
                await client.start_notify(CHAR_INDICATE, on_indicate)
            except Exception:
                pass
            await asyncio.sleep(0.5)  # needed before the writes, or only one press ever arrives
            writes = [RIDE_ON] if kind == "v1" else V2_ACTIVATION
            for w in writes:
                await client.write_gatt_char(CHAR_WRITE, w, response=False)
                await asyncio.sleep(0.3)
            self.connected = True
            self.status = f"Click{side} connected"
            log.info("Zwift Click %s%s connected (%s)", kind, side, device.address)

            while not disconnected.is_set() and not self._stop.is_set():
                if locked.is_set():
                    self.status = "Click is locked: pair it once with the Zwift app"
                try:
                    await asyncio.wait_for(disconnected.wait(), timeout=3.0)
                except asyncio.TimeoutError:
                    if kind == "v2":
                        await client.write_gatt_char(CHAR_WRITE, RIDE_ON, response=False)
        log.info("Zwift Click disconnected")

    def _on_frame(self, frame: bytes) -> None:
        now = pressed_buttons(frame)
        if now is None:
            return
        new = now - self._pressed
        self._pressed = now
        for b in new:  # fire on press edges only
            try:
                self.on_shift(+1 if b == "up" else -1)
            except Exception:
                log.exception("shift handler failed")
