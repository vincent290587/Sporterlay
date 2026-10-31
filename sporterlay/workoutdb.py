"""Reader for the ai_advise workout database: workoutDB.bin (`RawWorkoutDB` protobuf)
or workouts.json (the same message in protobuf JSON form, which also carries the TSS and
zone labels ai_advise computed).

Schema (ai_advise/proto/Workout.proto), only the parts used here:
    RawWorkoutDB { repeated RawWorkout rawDB = 1; }
    RawWorkout   { string name = 1; string author = 2; string description = 3; uint32 TSS = 4;
                   repeated WorkoutFocus labels = 7;  // enum Zone1 = 0 … Zone7 = 6
                   repeated Repetition reps = 10 [deprecated]; repeated Block blocks = 11; }
    Repetition   { repeated RawInterval intervals = 1; }
    Block        { repeated RawInterval intervals = 1; uint32 repeats = 2; }
    RawInterval  { uint32 duration = 1;  // seconds
                   double powerStart = 2; double powerEnd = 3;  // fraction of FTP
                   uint32 cadence = 4; }  // 0 = no target
Like ai_advise's getIntervals(): use `blocks` (each repeated `repeats` times) when
present, else the older flat `reps`.

A tiny wire-format decoder is used instead of generated code, so there's no protobuf
dependency; unknown fields are skipped.
"""

from __future__ import annotations

import json
import struct
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator

from .workout import Segment, Workout

ZONE_NAMES = {
    "Zone1": "Z1 Recovery", "Zone2": "Z2 Endurance", "Zone3": "Z3 Tempo", "Zone4": "Z4 Threshold",
    "Zone5": "Z5 VO2max", "Zone6": "Z6 Anaerobic", "Zone7": "Z7 Neuromuscular",
}


def _varint(b: bytes, i: int) -> tuple[int, int]:
    r = s = 0
    while True:
        x = b[i]
        i += 1
        r |= (x & 0x7F) << s
        if not x & 0x80:
            return r, i
        s += 7


def _fields(b: bytes) -> Iterator[tuple[int, object]]:
    i = 0
    while i < len(b):
        key, i = _varint(b, i)
        num, wt = key >> 3, key & 7
        if wt == 0:
            v, i = _varint(b, i)
        elif wt == 1:
            v = struct.unpack_from("<d", b, i)[0]
            i += 8
        elif wt == 2:
            n, i = _varint(b, i)
            v = b[i:i + n]
            i += n
        elif wt == 5:
            v = struct.unpack_from("<f", b, i)[0]
            i += 4
        else:
            raise ValueError(f"unsupported protobuf wire type {wt}")
        yield num, v


def _interval(b: bytes) -> Segment:
    dur, start, end, cad = 0, 0.0, 0.0, 0
    for num, v in _fields(b):
        if num == 1:
            dur = v
        elif num == 2:
            start = v
        elif num == 3:
            end = v
        elif num == 4:
            cad = v
    return Segment(float(dur), start, end, cad or None)


def _intervals(container: bytes) -> list[Segment]:
    return [_interval(v) for num, v in _fields(container) if num == 1]


@dataclass
class LibraryWorkout:
    workout: Workout
    author: str
    intensity_factor: float  # IF (derived from the stored TSS when there is one)
    tss: int
    labels: list[str] = field(default_factory=list)  # e.g. ["Z4 Threshold", "Z6 Anaerobic"]

    @property
    def name(self) -> str:
        return self.workout.name

    @property
    def duration(self) -> float:
        return self.workout.duration


def _np_fraction(segs: list[Segment]) -> float:
    """4th-power mean of the target (same closed form as ai_advise calculateNP)."""
    total = acc = 0.0
    for s in segs:
        a, b = s.start or 0.0, s.end or 0.0
        if abs(b - a) < 1e-9:
            acc += s.duration * a**4
        else:
            acc += s.duration * (b**5 - a**5) / (5 * (b - a))
        total += s.duration
    return (acc / total) ** 0.25 if total else 0.0


def _build(name: str, author: str, desc: str, stored_tss: int, labels: list[str],
           blocks: list[tuple[list[Segment], int]], reps: list[list[Segment]]) -> LibraryWorkout | None:
    segs: list[Segment] = []
    if blocks:  # newer layout, like ai_advise getIntervalsV2()
        for ivs, repeats in blocks:
            for r in range(repeats):
                for k, sg in enumerate(ivs):
                    label = f"{r + 1}/{repeats}" if repeats > 1 and k == 0 else ""
                    segs.append(Segment(sg.duration, sg.start, sg.end, sg.cadence, label))
    else:
        for ivs in reps:
            segs.extend(Segment(sg.duration, sg.start, sg.end, sg.cadence) for sg in ivs)

    segs = [sg for sg in segs if sg.duration > 0]
    if not segs:
        return None
    wo = Workout(name or "Workout", segs, desc)
    hours = wo.duration / 3600
    if stored_tss:
        tss, if_ = stored_tss, (stored_tss / (hours * 100)) ** 0.5
    else:
        if_ = _np_fraction(segs)
        tss = round(hours * if_ * if_ * 100)
    return LibraryWorkout(wo, author, if_, tss, [ZONE_NAMES.get(l, l) for l in labels])


def _workout_pb(b: bytes) -> LibraryWorkout | None:
    name = author = desc = ""
    tss, labels, reps, blocks = 0, [], [], []
    enum_names = list(ZONE_NAMES)  # enum value i -> "Zone{i+1}"
    for num, v in _fields(b):
        if num == 1:
            name = v.decode("utf-8", "replace")
        elif num == 2:
            author = v.decode("utf-8", "replace")
        elif num == 3:
            desc = v.decode("utf-8", "replace")
        elif num == 4:
            tss = v
        elif num == 7:
            vals = [v] if isinstance(v, int) else []
            if isinstance(v, bytes):  # packed repeated enum
                i = 0
                while i < len(v):
                    x, i = _varint(v, i)
                    vals.append(x)
            labels += [enum_names[x] for x in vals if 0 <= x < len(enum_names)]
        elif num == 10:
            reps.append(_intervals(v))
        elif num == 11:
            ivs, repeats = [], 0
            for n2, v2 in _fields(v):
                if n2 == 1:
                    ivs.append(_interval(v2))
                elif n2 == 2:
                    repeats = v2
            blocks.append((ivs, repeats))
    return _build(name, author, desc, tss, labels, blocks, reps)


def _interval_json(d: dict) -> Segment:
    # protobuf JSON leaves out fields that are 0
    return Segment(float(d.get("duration", 0)), float(d.get("powerStart", 0.0)),
                   float(d.get("powerEnd", 0.0)), int(d.get("cadence", 0)) or None)


def _workout_json(d: dict) -> LibraryWorkout | None:
    reps = [[_interval_json(i) for i in r.get("intervals", [])] for r in d.get("reps", [])]
    blocks = [([_interval_json(i) for i in b.get("intervals", [])], int(b.get("repeats", 0)))
              for b in d.get("blocks", [])]
    labels = [l if isinstance(l, str) else f"Zone{int(l) + 1}" for l in d.get("labels", [])]
    return _build(d.get("name", ""), d.get("author", ""), d.get("description", ""),
                  int(d.get("TSS", d.get("tSS", 0)) or 0), labels, blocks, reps)


def load_workout_db(path: str | Path) -> list[LibraryWorkout]:
    """Load workouts.json or workoutDB.bin (decided by extension)."""
    path = Path(path)
    if path.suffix.lower() == ".json":
        doc = json.loads(path.read_text(encoding="utf-8"))
        items = (doc.get("rawDB", []) if isinstance(doc, dict) else doc)
        parsed = (_workout_json(d) for d in items)
    else:
        parsed = (_workout_pb(v) for num, v in _fields(path.read_bytes()) if num == 1)
    return [w for w in parsed if w is not None]
