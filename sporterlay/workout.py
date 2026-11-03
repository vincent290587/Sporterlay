"""Workout model, .zwo parser and the player that tracks progress through a workout."""

from __future__ import annotations

import logging
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

log = logging.getLogger(__name__)


@dataclass
class Segment:
    """One block of a workout. Powers are fractions of FTP (0.75 = 75 %)."""

    duration: float  # seconds
    start: Optional[float]  # None = free ride / no target
    end: Optional[float]
    cadence: Optional[int] = None
    label: str = ""
    target_range: Optional[tuple[float, float]] = None  # (low, high) when the step is a range
    texts: list[tuple[float, str, float]] = field(default_factory=list)  # (offset s, message, duration s)
    torque: Optional[float] = None  # Nm at the cranks, held in simulation mode (see apply_torques)

    def text_at(self, t: float) -> Optional[str]:
        for off, msg, dur in self.texts:
            if off <= t < off + dur:
                return msg
        return None

    def power_at(self, t: float) -> Optional[float]:
        """Target as FTP fraction, t seconds into the segment."""
        if self.start is None or self.end is None:
            return None
        if self.duration <= 0:
            return self.end
        f = min(max(t / self.duration, 0.0), 1.0)
        return self.start + (self.end - self.start) * f

    @property
    def is_ramp(self) -> bool:
        return self.start is not None and self.end is not None and abs(self.start - self.end) > 1e-6

    @property
    def peak(self) -> float:
        return max(self.start or 0.0, self.end or 0.0)


@dataclass
class Workout:
    name: str
    segments: list[Segment] = field(default_factory=list)
    description: str = ""
    ftp_override: Optional[int] = None  # <ftpOverride>: targets are relative to this FTP, not the rider's

    @property
    def duration(self) -> float:
        return sum(s.duration for s in self.segments)


def _f(el: ET.Element, *names: str) -> Optional[float]:
    for n in names:
        # zwo attribute names are case-inconsistent in the wild
        for k, v in el.attrib.items():
            if k.lower() == n.lower():
                try:
                    return float(v)
                except ValueError:
                    return None
    return None


def _i(el: ET.Element, *names: str) -> Optional[int]:
    v = _f(el, *names)
    return int(v) if v is not None else None


def parse_zwo(path: str | Path) -> Workout:
    """Parse a Zwift-format .zwo workout file."""
    return _parse_root(ET.parse(path).getroot(), Path(path).stem)


def parse_zwo_bytes(data: bytes, fallback_name: str = "Workout") -> Workout:
    return _parse_root(ET.fromstring(data), fallback_name)


def _parse_root(root: ET.Element, fallback_name: str) -> Workout:
    name = (root.findtext("name") or fallback_name).strip()
    try:
        ftp_override = int(float(root.findtext("ftpOverride") or 0)) or None
    except ValueError:
        ftp_override = None
    desc = (root.findtext("description") or "").strip()
    body = root.find("workout")
    if body is None:
        raise ValueError("No <workout> element found")

    segs: list[Segment] = []
    for el in body:
        tag = el.tag.lower()
        dur = _f(el, "Duration") or 0.0
        cad = _i(el, "Cadence")
        lo = _f(el, "PowerLow")
        hi = _f(el, "PowerHigh")

        texts = [(_f(t, "timeoffset") or 0.0, t.get("message", ""), _f(t, "duration") or 10.0)
                 for t in el if t.tag.lower() == "textevent" and t.get("message")]
        first = len(segs)

        if tag in ("steadystate", "solidstate"):
            p = _f(el, "Power")
            rng = None
            if p is None and lo is not None and hi is not None:
                p, rng = (lo + hi) / 2, (min(lo, hi), max(lo, hi))
            segs.append(Segment(dur, p, p, cad, target_range=rng))
        elif tag == "warmup":
            a, b = sorted((lo or 0.25, hi or 0.75))
            segs.append(Segment(dur, a, b, cad, "Warm up"))
        elif tag == "cooldown":
            a, b = sorted((lo or 0.25, hi or 0.75), reverse=True)
            segs.append(Segment(dur, a, b, cad, "Cool down"))
        elif tag == "ramp":
            segs.append(Segment(dur, lo or 0.5, hi or 0.5, cad))
        elif tag == "intervalst":
            reps = _i(el, "Repeat") or 1
            on_d = _f(el, "OnDuration") or 0.0
            off_d = _f(el, "OffDuration") or 0.0
            on_p = _f(el, "OnPower", "PowerOnHigh", "PowerOnLow") or 1.0
            off_p = _f(el, "OffPower", "PowerOffLow", "PowerOffHigh") or 0.5
            cad_rest = _i(el, "CadenceResting")
            for r in range(reps):
                segs.append(Segment(on_d, on_p, on_p, cad, f"Interval {r + 1}/{reps}"))
                segs.append(Segment(off_d, off_p, off_p, cad_rest, f"Recovery {r + 1}/{reps}"))
        elif tag == "freeride":
            segs.append(Segment(dur, None, None, cad, "Free ride"))
        elif tag == "maxeffort":
            segs.append(Segment(dur, None, None, cad, "Max effort"))
        # unknown tags are ignored

        # text messages: offsets are relative to the whole element, so hand each one to
        # the segment it falls into (IntervalsT expands into several segments)
        for off, msg, tdur in texts:
            t0 = 0.0
            for seg in segs[first:]:
                if off < t0 + seg.duration:
                    seg.texts.append((off - t0, msg, tdur))
                    break
                t0 += seg.duration

    segs = [s for s in segs if s.duration > 0]
    if not segs:
        raise ValueError("Workout has no segments")
    return Workout(name, segs, desc, ftp_override)


_NM = re.compile(r"(\d+(?:\.\d+)?)\s*nm\b", re.I)
_REPEAT = re.compile(r"^(\d+)\s*x\b", re.I)


def step_torques(description: str) -> list[Optional[float]]:
    """Torque (Nm) of each step in an intervals.icu workout text, repeats expanded.

    Steps are the "- " lines; "5x …" starts a block that repeats until the next blank or
    heading line. intervals.icu doesn't export torque ("- 300s 50Nm") to the .zwo or its
    workout_doc, so the text is the only place it survives.
    """
    out: list[Optional[float]] = []
    block: list[Optional[float]] = []
    reps = 1
    for line in [*description.splitlines(), ""]:
        s = line.strip()
        if s.startswith("-"):
            m = _NM.search(s)
            block.append(float(m.group(1)) if m else None)
            continue
        out.extend(block * reps)
        block = []
        m = _REPEAT.match(s)
        reps = int(m.group(1)) if m else 1
    return out


def apply_torques(workout: Workout, description: str) -> int:
    """Give the workout's segments the torque targets from its intervals.icu text.
    Returns how many segments got one (0 when the steps don't line up with the segments)."""
    torques = step_torques(description)
    if not any(t is not None for t in torques):
        return 0
    if len(torques) != len(workout.segments):
        log.warning("%s: %d steps in the text but %d in the .zwo, ignoring its torque targets",
                    workout.name, len(torques), len(workout.segments))
        return 0
    n = 0
    for seg, nm in zip(workout.segments, torques):
        if nm is not None:
            seg.torque = nm
            seg.label = seg.label or f"Torque {nm:g} Nm"
            n += 1
    return n


class WorkoutPlayer:
    """Tracks position in a workout. Time only advances while the rider pedals."""

    def __init__(self, workout: Workout):
        self.workout = workout
        self.elapsed = 0.0  # seconds into the workout
        self.paused = False
        self._starts = []
        t = 0.0
        for s in workout.segments:
            self._starts.append(t)
            t += s.duration

    @property
    def finished(self) -> bool:
        return self.elapsed >= self.workout.duration

    @property
    def started(self) -> bool:
        return self.elapsed > 0

    def tick(self, dt: float, pedaling: bool) -> None:
        if not self.paused and pedaling and not self.finished:
            self.elapsed = min(self.elapsed + dt, self.workout.duration)

    def index(self) -> int:
        for i in range(len(self._starts) - 1, -1, -1):
            if self.elapsed >= self._starts[i]:
                return i
        return 0

    def current(self) -> tuple[int, Segment, float, float]:
        """(index, segment, seconds into segment, seconds remaining in segment)"""
        i = self.index()
        s = self.workout.segments[i]
        into = self.elapsed - self._starts[i]
        return i, s, into, max(s.duration - into, 0.0)

    def next_segment(self) -> Optional[Segment]:
        i = self.index() + 1
        return self.workout.segments[i] if i < len(self.workout.segments) else None

    def target_fraction(self) -> Optional[float]:
        if self.finished:
            return None
        _, s, into, _ = self.current()
        return s.power_at(into)

    def segment_start(self, i: int) -> float:
        return self._starts[i]

    def skip(self) -> None:
        i = self.index() + 1
        self.elapsed = self._starts[i] if i < len(self._starts) else self.workout.duration

    def back(self) -> None:
        i, _, into, _ = self.current()
        # like a media player: restart this interval, or go to the previous one if we just started
        if into < 3 and i > 0:
            i -= 1
        self.elapsed = self._starts[i]
