"""Ride recording: a crash-safe journal while riding, turned into a .fit file at the end.

While riding, one sample per second is appended to `activities/ride-<start>.jsonl` (and
flushed every few seconds). Finishing converts the journal to a .fit file and deletes it. A
journal left behind by a crash is converted at the next start (`recover()`).

Uploads are queued as `activities/pending/<fit name>.json` (name, intervals.icu event id,
external id) and removed once intervals.icu accepted the file. Pure Python, no Qt.
"""

from __future__ import annotations

import datetime as dt
import json
import logging
import re
from pathlib import Path
from typing import Optional

from .fit import Lap, Sample, build_activity

log = logging.getLogger(__name__)

MIN_RIDE_S = 120  # shorter rides are thrown away
PAUSE_GAP_S = 5  # a gap this long between samples is recorded as a timer stop
FLUSH_EVERY = 5  # samples


class RideRecorder:
    def __init__(self, folder: Path, demo: bool = False):
        self.folder = folder
        self.demo = demo  # simulated rides are saved but never uploaded
        self._f = None
        self._path: Optional[Path] = None
        self._meta: dict = {"demo": demo}
        self._last_t: Optional[float] = None  # unix time of the last sample
        self._lap_key = None
        self._d0 = 0.0
        self._unflushed = 0
        self.samples = 0  # moving seconds recorded in the current ride
        self.last_rows: list[tuple] = []  # samples of the ride that finish() just saved (for the summary)

    @property
    def active(self) -> bool:
        return self._f is not None

    def idle_s(self, now: float) -> float:
        return now - self._last_t if self._last_t is not None else 0.0

    def set_meta(self, name: str = "", event_id: Optional[int] = None, **extra) -> None:
        """Workout name and intervals.icu event (for pairing), plus extras (e.g. ramp=True).
        The last one set wins."""
        self._meta = {"name": name, "event_id": event_id, "demo": self.demo, **extra}
        if self.active:
            self._write({"meta": self._meta})

    def sample(self, now: float, moving: bool, power, hr, cadence, speed_ms, distance_m: float, lap_key,
               target=None) -> None:
        """Called every tick; keeps one sample per second while moving. target = workout target (W)."""
        if not moving or (self._last_t is not None and int(now) == int(self._last_t)):
            return
        now = float(int(now))
        if not self.active:
            self._start(now, distance_m)
        elif now - self._last_t >= PAUSE_GAP_S:
            self._write({"stop": self._last_t + 1, "restart": now})
        if lap_key != self._lap_key and self.samples:
            self._write({"lap": now})
        self._lap_key = lap_key
        self._last_t = now
        self.samples += 1
        self._write([now, power, hr, cadence, None if speed_ms is None else round(speed_ms, 3),
                     round(max(0.0, distance_m - self._d0), 1), target])

    def _start(self, now: float, distance_m: float) -> None:
        try:
            self.folder.mkdir(parents=True, exist_ok=True)
            self._path = self.folder / f"ride-{int(now)}.jsonl"
            self._f = open(self._path, "a", encoding="utf-8")
        except OSError as e:
            log.warning("Can't record the ride: %s", e)
            self._f = None
            return
        self._d0 = distance_m
        self._lap_key = None
        self.samples = 0
        self._write({"start": now, "meta": self._meta})
        log.info("Recording ride to %s", self._path)

    def _write(self, obj) -> None:
        if self._f is None:
            return
        try:
            self._f.write(json.dumps(obj, separators=(",", ":")) + "\n")
            self._unflushed += 1
            if self._unflushed >= FLUSH_EVERY:
                self._f.flush()
                self._unflushed = 0
        except OSError as e:
            log.warning("Ride journal write failed: %s", e)

    def finish(self) -> Optional[tuple[Path, dict]]:
        """End the current ride: returns (fit path, meta), or None if nothing worth keeping."""
        if not self.active:
            return None
        self._f.close()
        self._f = None
        self._last_t = None
        path, self.samples = self._path, 0
        result = _convert(path)
        if result is None:
            self.last_rows = []
            return None
        fit, meta, self.last_rows = result
        return fit, meta


def convert(journal: Path) -> Optional[tuple[Path, dict]]:
    """Turn a ride journal into a .fit file next to it and delete the journal.
    Returns (fit path, meta), or None if the ride was too short (or unreadable)."""
    result = _convert(journal)
    return None if result is None else result[:2]


def _convert(journal: Path) -> Optional[tuple[Path, dict, list[tuple]]]:
    """convert(), plus the samples as (t, power, hr, cadence, speed m/s, distance m, target W) rows."""
    meta: dict = {}
    rows: list[tuple] = []
    start = None
    laps: list[Lap] = []
    stops: list[tuple[float, float]] = []
    try:
        lines = journal.read_text(encoding="utf-8").splitlines()
    except OSError as e:
        log.warning("Can't read ride journal %s: %s", journal, e)
        return None
    for line in lines:
        try:
            obj = json.loads(line)
        except ValueError:
            continue  # the last line can be cut off by a crash
        if isinstance(obj, list):
            t, p, hr, cad, spd, dist = obj[:6]
            rows.append((t, p, hr, cad, spd, dist, obj[6] if len(obj) > 6 else None))  # older journals: no target
            if not laps:
                laps.append(Lap(t))
            laps[-1].samples.append(Sample(t, p, hr, cad, spd, dist))
        elif "lap" in obj:
            laps.append(Lap(obj["lap"]))
        elif "stop" in obj:
            stops.append((obj["stop"], obj["restart"]))
        if isinstance(obj, dict):
            start = obj.get("start", start)
            meta = obj.get("meta", meta) or meta
    n = sum(len(lap.samples) for lap in laps)
    if n < MIN_RIDE_S:
        log.info("Ride journal %s: only %d s of riding, not saved", journal.name, n)
        journal.unlink(missing_ok=True)
        return None
    for lap in laps:  # a lap starts with its first sample
        if lap.samples:
            lap.start = lap.samples[0].t
    start = start or laps[0].start
    meta = {**meta, "start": start, "moving_s": n}
    try:
        data = build_activity(laps, stops)
        fit = journal.with_name(fit_name(start, meta.get("name") or ""))
        n_try = 2
        while fit.exists():  # two rides started in the same minute
            fit = journal.with_name(f"{Path(fit_name(start, meta.get('name') or '')).stem}_{n_try}.fit")
            n_try += 1
        fit.write_bytes(data)
    except Exception as e:  # keep the journal so nothing is lost
        log.exception("Could not write the FIT file for %s: %s", journal, e)
        return None
    journal.unlink(missing_ok=True)
    log.info("Saved ride %s (%d s moving)", fit, n)
    return fit, meta, rows


def fit_name(start: float, name: str) -> str:
    stamp = dt.datetime.fromtimestamp(start).strftime("%Y-%m-%d_%H%M")
    slug = re.sub(r"[^\w\-]+", "_", name, flags=re.UNICODE).strip("_")[:40]
    return f"{stamp}_{slug}.fit" if slug else f"{stamp}.fit"


def recover(folder: Path) -> list[tuple[Path, dict]]:
    """Convert journals left behind by a crash."""
    out = []
    for j in sorted(folder.glob("ride-*.jsonl")):
        log.info("Recovering unfinished ride %s", j.name)
        r = convert(j)
        if r:
            out.append(r)
    return out


# ---- upload queue -------------------------------------------------------------------------
def queue_upload(fit: Path, meta: dict) -> None:
    d = fit.parent / "pending"
    d.mkdir(parents=True, exist_ok=True)
    (d / (fit.name + ".json")).write_text(json.dumps({**meta, "file": fit.name}), encoding="utf-8")


def pending_uploads(folder: Path) -> list[tuple[Path, dict]]:
    out = []
    for p in sorted((folder / "pending").glob("*.fit.json")):
        try:
            meta = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        fit = folder / meta.get("file", p.name[:-5])
        if fit.exists():
            out.append((fit, meta))
        else:
            p.unlink(missing_ok=True)
    return out


def mark_uploaded(fit: Path) -> None:
    (fit.parent / "pending" / (fit.name + ".json")).unlink(missing_ok=True)
