"""Share raw power, cadence and heart rate with Zwift over Wahoo Direct Connect ("DIRCON").

Sporterlay shows up in Zwift's pairing screen as one Direct Connect device offering the BLE
Cycling Power (0x1818) and Heart Rate (0x180D) services: a power meter with crank data plus an
HR strap, never a controllable trainer, so ERG, gears and isokinetic mode stay in Sporterlay.
Verified with Zwift on the same Windows PC (issue #6).

Discovery is mDNS `_wahoo-fitness-tnp._tcp` with TXT `ble-service-uuids` (full 128-bit UUIDs,
comma-separated), `mac-address` and `serial-number`. Zwift takes the service list from that TXT
and never sends "discover services"; it discovers the characteristics, enables notifications on
0x2A63 and 0x2A37, then only listens.

Wire format (from qdomyos-zwift src/devices/dircon): 6-byte header [version 1, message id,
sequence, response code, length (big-endian u16)], payload with each UUID as 16 bytes. Responses
echo the request's sequence number; notifications use 0.
"""

from __future__ import annotations

import asyncio
import logging
import socket
import struct
import threading
import time
import uuid as uuidlib
from typing import Callable, Optional

log = logging.getLogger(__name__)

PORT = 36866  # what Wahoo trainers use; the next free one is taken if it's busy
NAME = "Sporterlay"
SERVICE_TYPE = "_wahoo-fitness-tnp._tcp.local."
SEND_S = 0.25

DISCOVER_SERVICES, DISCOVER_CHARS, READ, WRITE, ENABLE_NOTIFY, NOTIFY, UNKNOWN_7 = 1, 2, 3, 4, 5, 6, 7
OK, UNKNOWN_MSG, SERVICE_NOT_FOUND, CHAR_NOT_FOUND, OP_NOT_SUPPORTED = 0, 1, 3, 4, 5
PROP_READ, PROP_NOTIFY = 0x01, 0x04

POWER_SVC, POWER_MEAS, POWER_FEAT, SENSOR_LOC = 0x1818, 0x2A63, 0x2A65, 0x2A5D
HR_SVC, HR_MEAS = 0x180D, 0x2A37

# service -> {characteristic: (properties, value for reads)}
SERVICES = {
    POWER_SVC: {
        POWER_MEAS: (PROP_NOTIFY, b""),
        POWER_FEAT: (PROP_READ, struct.pack("<I", 0x08)),  # crank revolution data supported
        SENSOR_LOC: (PROP_READ, b"\x0d"),  # rear hub
    },
    HR_SVC: {HR_MEAS: (PROP_NOTIFY, b"")},
}
CHARS = {ch: v for chars in SERVICES.values() for ch, v in chars.items()}


def uuid128(u: int) -> bytes:
    """16-bit BLE UUID on the Bluetooth base UUID."""
    return bytes([0, 0, u >> 8, u & 0xFF, 0, 0, 0x10, 0, 0x80, 0, 0, 0x80, 0x5F, 0x9B, 0x34, 0xFB])


def uuid16(b: bytes) -> int:
    return (b[2] << 8) | b[3]


def frame(msg: int, seq: int, code: int, payload: bytes = b"") -> bytes:
    return struct.pack(">BBBBH", 1, msg, seq, code, len(payload)) + payload


class Crank:
    """Cumulative crank revolutions and the time of the last whole one (1/1024 s), built from
    cadence, which is all an FE-C trainer reports."""

    def __init__(self) -> None:
        self.revs = 0.0
        self.event = 0.0
        self.t: Optional[float] = None

    def update(self, now: float, rpm: float) -> tuple[int, int]:
        if self.t is not None and rpm > 0:
            before = self.revs
            self.revs += rpm / 60 * (now - self.t)
            if int(self.revs) > int(before):  # when the last revolution completed
                self.event = now - (self.revs - int(self.revs)) / (rpm / 60)
        self.t = now
        return int(self.revs) & 0xFFFF, int(self.event * 1024) & 0xFFFF


def power_measurement(watts: int, revs: int, event: int) -> bytes:
    return struct.pack("<HhHH", 0x20, max(-32768, min(32767, watts)), revs, event)  # flags: crank data


def hr_measurement(bpm: int) -> bytes:
    return bytes([0x00, max(0, min(255, bpm))])  # flags: u8 heart rate


def handle(msg: int, seq: int, payload: bytes, notify: set[int]) -> bytes:
    """Answer one request; `notify` is the client's set of subscribed characteristics."""
    if msg == DISCOVER_SERVICES:
        return frame(msg, seq, OK, b"".join(uuid128(s) for s in SERVICES))
    if msg == UNKNOWN_7:
        return frame(msg, seq, OK)
    if msg not in (DISCOVER_CHARS, READ, WRITE, ENABLE_NOTIFY) or len(payload) < 16:
        return frame(msg, seq, UNKNOWN_MSG)
    u = uuid16(payload)
    if msg == DISCOVER_CHARS:
        if u not in SERVICES:
            return frame(msg, seq, SERVICE_NOT_FOUND)
        return frame(msg, seq, OK, payload[:16] + b"".join(
            uuid128(ch) + bytes([props]) for ch, (props, _) in SERVICES[u].items()))
    if u not in CHARS:
        return frame(msg, seq, CHAR_NOT_FOUND)
    props, value = CHARS[u]
    if msg == READ and props & PROP_READ:
        return frame(msg, seq, OK, payload[:16] + value)
    if msg == ENABLE_NOTIFY and props & PROP_NOTIFY:
        if len(payload) < 17 or payload[16]:
            notify.add(u)
        else:
            notify.discard(u)
        return frame(msg, seq, OK, payload[:16])
    return frame(msg, seq, OP_NOT_SUPPORTED, payload[:16])


def lan_addresses() -> list[str]:
    """IPv4 addresses to announce: no loopback, link-local or virtual adapters (Hyper-V would
    otherwise be listed first)."""
    import ifaddr

    ips = []
    for a in ifaddr.get_adapters():
        if "virtual" in a.nice_name.lower():
            continue
        ips += [ip.ip for ip in a.ips if isinstance(ip.ip, str) and not ip.ip.startswith(("127.", "169.254."))]
    return ips


class ZwiftShare:
    """Runs the Direct Connect server and mDNS announcement on its own thread.

    `update()` is called from the Qt thread with the latest raw telemetry; the thread sends it to
    every subscribed client at 4 Hz. `on_change(connected)` is called from the thread when the
    first client subscribes or the last one leaves.
    """

    def __init__(self, on_change: Optional[Callable[[bool], None]] = None) -> None:
        self.on_change = on_change
        self.status = "Zwift: starting…"
        self._latest: tuple = (None, None, None)  # power, cadence, heart rate (one atomic swap)
        self._clients: dict[asyncio.StreamWriter, set[int]] = {}
        self._connected = False
        self._stop: Optional[asyncio.Event] = None
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._thread = threading.Thread(target=self._run, name="zwift-share", daemon=True)
        self._thread.start()

    @property
    def connected(self) -> bool:
        return self._connected

    def update(self, power: Optional[int], cadence: Optional[int], heart_rate: Optional[int]) -> None:
        self._latest = (power, cadence, heart_rate)

    def close(self, timeout: float = 3.0) -> None:
        """Withdraw the mDNS announcement (so Zwift drops the device now) and stop."""
        if self._loop is not None and self._stop is not None:
            self._loop.call_soon_threadsafe(self._stop.set)
        self._thread.join(timeout)

    # ---- background thread ---------------------------------------------------------------
    def _run(self) -> None:
        try:
            import ifaddr  # noqa: F401
            import zeroconf  # noqa: F401
        except ImportError:
            self.status = "Zwift: zeroconf not installed"
            log.warning("Zwift sharing needs the zeroconf package")
            return
        self._loop = asyncio.new_event_loop()
        try:
            self._loop.run_until_complete(self._main())
        except Exception as e:
            log.exception("Zwift sharing stopped")
            self.status = f"Zwift sharing error: {e}"
        finally:
            self._loop.close()

    async def _main(self) -> None:
        from zeroconf import IPVersion, ServiceInfo
        from zeroconf.asyncio import AsyncZeroconf

        self._stop = asyncio.Event()
        server = None
        for port in range(PORT, PORT + 10):
            try:
                server = await asyncio.start_server(self._serve, "0.0.0.0", port)
                break
            except OSError:
                continue
        if server is None:
            self.status = f"Zwift: ports {PORT}–{PORT + 9} are in use"
            log.warning("Zwift sharing: no free port")
            return
        ips = lan_addresses()
        mac = ":".join(f"{(uuidlib.getnode() >> s) & 0xFF:02X}" for s in range(40, -1, -8))
        host = socket.gethostname().replace(" ", "-")
        info = ServiceInfo(
            SERVICE_TYPE, f"{NAME}.{SERVICE_TYPE}",
            addresses=[socket.inet_aton(ip) for ip in ips], port=port,
            properties={
                "ble-service-uuids": ",".join(str(uuidlib.UUID(bytes=uuid128(s))) for s in SERVICES),
                "mac-address": mac,
                "serial-number": "SPORTERLAY0001",
            },
            server=f"{host}-sporterlay.local.",
        )
        zc = AsyncZeroconf(ip_version=IPVersion.V4Only)
        try:
            # the type name is 17 bytes, over RFC 6763's 15: python-zeroconf needs strict=False
            await zc.async_register_service(info, strict=False, allow_name_change=True)
            log.info("Zwift sharing: announced %r on %s port %d", info.name, ips, port)
            self._set_connected(False)
            sender = asyncio.ensure_future(self._send_forever())
            await self._stop.wait()
            sender.cancel()
        finally:
            for w in list(self._clients):
                w.close()
            server.close()
            await zc.async_unregister_service(info)
            await zc.async_close()

    def _set_connected(self, connected: bool) -> None:
        self.status = "Zwift connected" if connected else "waiting for Zwift"
        if connected != self._connected:
            self._connected = connected
            if self.on_change:
                self.on_change(connected)

    async def _serve(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        peer = writer.get_extra_info("peername")
        notify: set[int] = set()
        self._clients[writer] = notify
        log.info("Zwift sharing: %s connected", peer)
        buf = b""
        try:
            while data := await reader.read(4096):
                buf += data
                while len(buf) >= 6:
                    _, msg, seq, _, n = struct.unpack(">BBBBH", buf[:6])
                    if len(buf) < 6 + n:
                        break
                    payload, buf = buf[6:6 + n], buf[6 + n:]
                    writer.write(handle(msg, seq, payload, notify))
                    log.debug("Zwift sharing: %s message %d %s", peer, msg, payload.hex())
                self._set_connected(any(self._clients.values()))
                await writer.drain()
        except (ConnectionError, OSError) as e:
            log.debug("Zwift sharing: %s: %s", peer, e)
        finally:
            del self._clients[writer]
            writer.close()
            log.info("Zwift sharing: %s disconnected", peer)
            self._set_connected(any(self._clients.values()))

    async def _send_forever(self) -> None:
        crank = Crank()
        while True:
            await asyncio.sleep(SEND_S)
            power, cadence, hr = self._latest
            revs, event = crank.update(time.monotonic(), cadence or 0)
            # stale power (trainer gone or not pedaling) goes out as 0 W, stale HR isn't sent
            values = {POWER_MEAS: power_measurement(power or 0, revs, event)}
            if hr:
                values[HR_MEAS] = hr_measurement(hr)
            for w, notify in list(self._clients.items()):
                for u, data in values.items():
                    if u in notify:
                        w.write(frame(NOTIFY, 0, OK, uuid128(u) + data))
