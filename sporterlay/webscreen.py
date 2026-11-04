"""Second screen: the ride on a phone or tablet, served on the home network.

`WebScreen` runs a stdlib HTTP server on its own thread:
- `GET /` is the page (`webpage.PAGE`, self-contained HTML/JS, no files to bundle),
- `GET /events` streams Server-Sent Events: a `workout` event (profile, predicted W′, power
  trace so far) whenever the workout changes, and a `state` event with the latest snapshot
  after each tick (only the newest is sent, so a slow phone skips ticks instead of lagging).
The Qt thread hands snapshots over with `publish()`; the server never touches the ride.
`ride_state()` / `workout_payload()` build those snapshots (no Qt).
"""

from __future__ import annotations

import dataclasses
import json
import logging
import socket
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Callable, Optional

from .webpage import PAGE

log = logging.getLogger(__name__)

PORT = 8686
PING_S = 15  # keeps idle connections (and Wi-Fi power saving) from dropping


def local_address() -> str:
    """This PC's address on the home network (no packet is sent)."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("192.0.2.1", 9))  # TEST-NET address: only picks the outgoing interface
            return s.getsockname()[0]
    except OSError:
        return socket.gethostname()


class WebScreen:
    def __init__(self, port: int = PORT):
        self.port = port
        self.error = ""
        self._cond = threading.Condition()
        self._version = 0
        self._state = "{}"
        self._workout_key: object = None
        self._workout = "null"
        self._clients = 0
        self._stop = False
        self._httpd: Optional[ThreadingHTTPServer] = None
        try:
            self._httpd = _Server(("", port), _handler(self))
        except OSError as e:
            self.error = f"Second screen: port {port} is busy" if e.errno in (98, 10048) else f"Second screen: {e}"
            log.warning("Second screen server: %s", e)
            return
        threading.Thread(target=self._httpd.serve_forever, name="webscreen", daemon=True).start()
        log.info("Second screen on %s", self.url)

    @property
    def url(self) -> str:
        return f"http://{local_address()}:{self.port}/"

    @property
    def connected(self) -> int:
        """Number of pages open right now."""
        return self._clients

    def publish(self, state: dict, workout_key: object = None,
                workout: Optional[Callable[[], Optional[dict]]] = None) -> None:
        """Hand over the latest snapshot. workout() is only called when workout_key changed."""
        state_json = json.dumps(state, separators=(",", ":"), default=_jsonable)
        with self._cond:
            if workout_key != self._workout_key:
                self._workout_key = workout_key
                self._workout = json.dumps(workout() if workout else None, separators=(",", ":"), default=_jsonable)
            self._state = state_json
            self._version += 1
            self._cond.notify_all()

    def close(self) -> None:
        with self._cond:
            self._stop = True
            self._cond.notify_all()
        if self._httpd:
            self._httpd.shutdown()
            self._httpd.server_close()

    # ---- request side (server threads) --------------------------------------------------
    def _stream(self, write: Callable[[bytes], None]) -> None:
        sent_version, sent_workout = 0, None  # version 0 = nothing published yet: wait for a snapshot
        with self._cond:
            self._clients += 1
        log.info("Second screen connected (%d open)", self._clients)
        try:
            write(b"retry: 2000\n\n")
            while True:
                with self._cond:
                    self._cond.wait_for(lambda: self._stop or self._version != sent_version, PING_S)
                    if self._stop:
                        return
                    changed = self._version != sent_version
                    sent_version = self._version
                    state = self._state
                    wkey, wjson = self._workout_key, self._workout
                if not changed:
                    write(b": ping\n\n")
                    continue
                if wkey != sent_workout:
                    write(b"event: workout\ndata: " + wjson.encode() + b"\n\n")
                    sent_workout = wkey
                write(b"event: state\ndata: " + state.encode() + b"\n\n")
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError, TimeoutError, OSError):
            pass  # the page closed or the phone went away
        finally:
            with self._cond:
                self._clients -= 1
            log.info("Second screen disconnected (%d open)", self._clients)


class _Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def _handler(screen: WebScreen):
    page = PAGE.encode("utf-8")

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def do_GET(self):  # noqa: N802 (http.server naming)
            path = self.path.split("?", 1)[0]
            if path == "/":
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(page)))
                self.send_header("Cache-Control", "no-cache")
                self.end_headers()
                self.wfile.write(page)
            elif path == "/events":
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "close")
                self.end_headers()
                self.close_connection = True

                def write(b: bytes) -> None:
                    self.wfile.write(b)
                    self.wfile.flush()

                screen._stream(write)
            else:
                self.send_error(404)

        def log_message(self, fmt, *args):
            log.debug("web: " + fmt, *args)

    return Handler


def _jsonable(o):
    if dataclasses.is_dataclass(o):
        return dataclasses.asdict(o)
    return str(o)


# ---- snapshots ---------------------------------------------------------------------------
def workout_payload(ride) -> Optional[dict]:
    """The loaded workout's profile, predicted W′ and power trace (sent when it changes)."""
    p = ride.player
    if p is None:
        return None
    wo = p.workout
    plan = ride.wbal_plan() if ride.settings.show_wbal else []
    return {
        "name": wo.name,
        "duration": wo.duration,
        "segments": [[s.duration, s.start, s.end] for s in wo.segments],
        "ftp": ride.workout_ftp,  # trace watts / ftp = FTP fraction, as on the HUD
        "plan": [[round(t, 1), round(f, 3)] for t, f in plan[::max(1, len(plan) // 400)]]
        if plan and min(f for _, f in plan) < 0.9 else [],
        "trace": [[round(t, 1), w] for t, w in ride.trace],
    }


def workout_key(ride) -> object:
    p = ride.player
    if p is None:
        return None
    s = ride.settings
    # a reset empties the trace: resend then (and once more when it starts again)
    return (id(p.workout), ride.workout_ftp, s.intensity, s.ftp, s.w_prime_j, s.show_wbal, bool(ride.trace))


def ride_state(ride, status: Optional[str], music: Optional[str], card=None, cue: tuple = (0, None)) -> dict:
    """Everything the HUD shows, as plain values."""
    s, t = ride.settings, ride.telemetry
    power = ride.power_display
    st = {
        "connected": t.trainer_connected,
        "power": power,
        "power_avg_s": s.power_avg_s,
        "avg_power": ride.avg_power,
        "wkg": round(power / s.weight_kg, 1) if power is not None and s.weight_kg else None,
        "hr": t.heart_rate,
        "cadence": t.cadence,
        "speed": None if ride.speed_kmh is None else round(ride.speed_kmh, 1),
        "distance": round(ride.distance_km, 2),
        "time": round(ride.ride_time),
        "mode": "iso" if ride.iso else "torque" if ride.torque_target is not None else (
            "erg" if ride.erg_active else "gear"),
        "torque": None if ride.torque_target is None else round(ride.torque_target),
        "gear": s.gear,
        "iso_rpm": s.iso_cadence,
        "show_wbal": s.show_wbal,
        "wbal": None if not s.show_wbal else ride.wbal.fraction(),
        "status": status,
        "music": music,
        "cue": list(cue),
        "workout": None,
        "card": None,
    }
    p = ride.player
    if p is not None:
        wo = p.workout
        w = {
            "elapsed": round(p.elapsed, 1),
            "remaining": round(max(wo.duration - p.elapsed, 0)),
            "finished": p.finished,
            "name": wo.name,
            "trace_point": [round(ride.trace[-1][0], 1), ride.trace[-1][1]] if ride.trace else None,
        }
        if not p.finished:
            idx, seg, into, left = p.current()
            frac = seg.power_at(into)
            name = seg.label or ("Ramp" if seg.is_ramp else f"Interval {idx + 1}")
            extra = []
            if seg.cadence:
                extra.append(f"@ {seg.cadence} rpm")
            if ride.torque_target is not None:
                rpm = ride.torque_cadence()
                extra.append(f"{ride.torque_target:.0f} Nm" + (f" @ {rpm} rpm" if rpm else ""))
            if seg.is_ramp and frac is not None:
                extra.append(f"{ride.watts_for(seg.start)} → {ride.watts_for(seg.end)} W")
            if seg.target_range:
                extra.append(f"{ride.watts_for(seg.target_range[0])}–{ride.watts_for(seg.target_range[1])} W")
            if s.intensity != 100:
                extra.append(f"{s.intensity}% intensity")
            nxt = p.next_segment()
            next_txt = None
            if nxt is not None:
                nt = ride.watts_for(nxt.power_at(0))
                what = f"{nt} W" if nt is not None else (nxt.label or "free ride")
                if nxt.is_ramp:
                    what = f"{nt} → {ride.watts_for(nxt.end)} W"
                if nxt.cadence:
                    what += f" @ {nxt.cadence} rpm"
                next_txt = f"{_fmt_time(nxt.duration)}  {what}"
            if p.paused:
                state = "PAUSED"
            elif ride.clock_held:
                state = "Clock waits for ERG"
            elif not p.started or not ride.pedaling:
                state = "Start pedaling"
            else:
                state = ""
            w.update({
                "index": idx, "count": len(wo.segments), "label": name, "message": seg.text_at(into),
                "extra": "   ".join(extra), "target": ride.target_watts(), "frac": frac,
                "into": round(into, 1), "seg_duration": seg.duration, "left": round(left),
                "next": next_txt, "state": state,
            })
        st["workout"] = w
    if card:
        summary, card_status = card
        st["card"] = {**dataclasses.asdict(summary), "status": card_status}
    return st


def _fmt_time(s: float) -> str:
    s = int(round(s))
    h, rem = divmod(s, 3600)
    m, sec = divmod(rem, 60)
    return f"{h}:{m:02d}:{sec:02d}" if h else f"{m}:{sec:02d}"
