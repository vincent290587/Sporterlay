"""Minimal FIT activity file writer (no dependency), enough for intervals.icu / Strava / Garmin.

Writes file_id, timer events, 1 Hz records, laps, one session and the activity message.
Field numbers and scales follow the FIT SDK profile.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field
from typing import Optional

FIT_EPOCH = 631065600  # 1989-12-31 00:00:00 UTC in unix seconds

# base types: (id, struct format, invalid value)
ENUM = (0x00, "B", 0xFF)
UINT8 = (0x02, "B", 0xFF)
UINT16 = (0x84, "H", 0xFFFF)
UINT32 = (0x86, "I", 0xFFFFFFFF)
UINT32Z = (0x8C, "I", 0)

# global message numbers
FILE_ID, SESSION, LAP, RECORD, EVENT, DEVICE_INFO, ACTIVITY = 0, 18, 19, 20, 21, 23, 34
TIMESTAMP = 253
MESSAGE_INDEX = 254

SPORT_CYCLING, SUB_SPORT_VIRTUAL = 2, 58
EVENT_TIMER, EVENT_LAP, EVENT_SESSION, EVENT_ACTIVITY = 0, 9, 8, 26
EVENT_TYPE_START, EVENT_TYPE_STOP, EVENT_TYPE_STOP_ALL = 0, 1, 4
MANUFACTURER_DEVELOPMENT = 255

_CRC_TABLE = [0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
              0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400]


def crc16(data: bytes, crc: int = 0) -> int:
    for byte in data:
        for nibble in (byte & 0xF, byte >> 4):
            tmp = _CRC_TABLE[crc & 0xF]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ _CRC_TABLE[nibble]
    return crc


def fit_time(unix_s: float) -> int:
    return int(unix_s) - FIT_EPOCH


class FitWriter:
    def __init__(self) -> None:
        self._body = bytearray()
        self._defs: dict[tuple, int] = {}  # (global msg, field layout) -> local message type

    def message(self, global_num: int, fields: list[tuple[int, tuple, Optional[float]]]) -> None:
        """fields: (field number, base type, value); None or out-of-range values are written as invalid."""
        layout = tuple((num, bt) for num, bt, _ in fields)
        key = (global_num, layout)
        local = self._defs.get(key)
        if local is None:
            local = len(self._defs) % 16
            # a local type slot gets reused after 16 layouts: forget whatever used it
            self._defs = {k: v for k, v in self._defs.items() if v != local}
            self._defs[key] = local
            self._body += struct.pack("<BBBHB", 0x40 | local, 0, 0, global_num, len(fields))
            for num, (bid, fmt, _), _v in fields:
                self._body += struct.pack("<BBB", num, struct.calcsize(fmt), bid)
        self._body.append(local)
        for _, (_, fmt, invalid), value in fields:
            v = invalid if value is None else int(round(value))
            if not 0 <= v < (1 << (8 * struct.calcsize(fmt))):
                v = invalid
            self._body += struct.pack("<" + fmt, v)

    def to_bytes(self) -> bytes:
        header = struct.pack("<BBHI4s", 14, 0x20, 2132, len(self._body), b".FIT")
        header += struct.pack("<H", crc16(header))
        data = header + bytes(self._body)
        return data + struct.pack("<H", crc16(data))


# ---- activity model ----------------------------------------------------------------------
@dataclass
class Sample:
    t: float  # unix seconds
    power: Optional[int] = None
    hr: Optional[int] = None
    cadence: Optional[int] = None
    speed: Optional[float] = None  # m/s
    distance: float = 0.0  # m since the start


@dataclass
class Lap:
    start: float  # unix seconds
    samples: list[Sample] = field(default_factory=list)


def _clamp_int(v: Optional[float], hi: int) -> Optional[int]:
    if v is None:
        return None
    return max(0, min(hi, int(round(v))))


def _stats(samples: list[Sample]) -> dict:
    def avg(vals):
        vals = [v for v in vals if v is not None]
        return sum(vals) / len(vals) if vals else None

    def mx(vals):
        vals = [v for v in vals if v is not None]
        return max(vals) if vals else None

    pw = [s.power for s in samples]
    return {
        "avg_power": avg(pw), "max_power": mx(pw),
        "avg_hr": avg(s.hr for s in samples), "max_hr": mx(s.hr for s in samples),
        # like head units: average cadence over pedaling samples only
        "avg_cad": avg(s.cadence for s in samples if s.cadence), "max_cad": mx(s.cadence for s in samples),
        "avg_speed": avg(s.speed for s in samples), "max_speed": mx(s.speed for s in samples),
        "work": sum(p or 0 for p in pw),  # J, 1 Hz samples
    }


def _timer_s(samples: list[Sample]) -> float:
    """Moving time: one second per sample (they're 1 Hz and only taken while riding)."""
    return float(len(samples))


def build_activity(laps: list[Lap], stops: list[tuple[float, float]], serial: int = 1) -> bytes:
    """laps: in order, each with its 1 Hz samples. stops: (stop time, restart time) pauses."""
    laps = [lap for lap in laps if lap.samples]
    if not laps:
        raise ValueError("no samples")
    all_samples = [s for lap in laps for s in lap.samples]
    t0, t_end = laps[0].start, all_samples[-1].t + 1
    w = FitWriter()
    w.message(FILE_ID, [(0, ENUM, 4), (1, UINT16, MANUFACTURER_DEVELOPMENT), (2, UINT16, 0),
                        (3, UINT32Z, serial), (4, UINT32, fit_time(t0))])
    w.message(DEVICE_INFO, [(TIMESTAMP, UINT32, fit_time(t0)), (0, UINT8, 0),
                            (2, UINT16, MANUFACTURER_DEVELOPMENT), (4, UINT16, 0), (3, UINT32Z, serial)])

    def event(t, kind):
        w.message(EVENT, [(TIMESTAMP, UINT32, fit_time(t)), (0, ENUM, EVENT_TIMER), (1, ENUM, kind)])

    event(t0, EVENT_TYPE_START)
    pending_stops = sorted(stops)
    for lap_i, lap in enumerate(laps):
        for s in lap.samples:
            while pending_stops and pending_stops[0][1] <= s.t:
                stop, restart = pending_stops.pop(0)
                event(stop, EVENT_TYPE_STOP_ALL)
                event(restart, EVENT_TYPE_START)
            w.message(RECORD, [
                (TIMESTAMP, UINT32, fit_time(s.t)),
                (3, UINT8, _clamp_int(s.hr, 254)),
                (4, UINT8, _clamp_int(s.cadence, 254)),
                (5, UINT32, round(s.distance * 100)),
                (6, UINT16, None if s.speed is None else _clamp_int(s.speed * 1000, 65534)),
                (7, UINT16, _clamp_int(s.power, 65534)),
            ])
        end = laps[lap_i + 1].start if lap_i + 1 < len(laps) else t_end
        st = _stats(lap.samples)
        d0 = laps[lap_i - 1].samples[-1].distance if lap_i else 0.0
        w.message(LAP, [
            (TIMESTAMP, UINT32, fit_time(end)), (0, ENUM, EVENT_LAP), (1, ENUM, EVENT_TYPE_STOP),
            (2, UINT32, fit_time(lap.start)),
            (7, UINT32, (end - lap.start) * 1000), (8, UINT32, _timer_s(lap.samples) * 1000),
            (9, UINT32, (lap.samples[-1].distance - d0) * 100),
            (13, UINT16, _scaled(st["avg_speed"], 1000)), (14, UINT16, _scaled(st["max_speed"], 1000)),
            (15, UINT8, _clamp_int(st["avg_hr"], 254)), (16, UINT8, _clamp_int(st["max_hr"], 254)),
            (17, UINT8, _clamp_int(st["avg_cad"], 254)), (18, UINT8, _clamp_int(st["max_cad"], 254)),
            (19, UINT16, _clamp_int(st["avg_power"], 65534)), (20, UINT16, _clamp_int(st["max_power"], 65534)),
            (24, ENUM, 7 if lap_i == len(laps) - 1 else 1),  # session_end / time
            (25, ENUM, SPORT_CYCLING), (39, ENUM, SUB_SPORT_VIRTUAL),
            (41, UINT32, st["work"]), (MESSAGE_INDEX, UINT16, lap_i),
        ])
    event(t_end, EVENT_TYPE_STOP_ALL)

    st = _stats(all_samples)
    timer = _timer_s(all_samples)
    w.message(SESSION, [
        (TIMESTAMP, UINT32, fit_time(t_end)), (0, ENUM, EVENT_SESSION), (1, ENUM, EVENT_TYPE_STOP),
        (2, UINT32, fit_time(t0)), (5, ENUM, SPORT_CYCLING), (6, ENUM, SUB_SPORT_VIRTUAL),
        (7, UINT32, (t_end - t0) * 1000), (8, UINT32, timer * 1000),
        (9, UINT32, all_samples[-1].distance * 100),
        (11, UINT16, _clamp_int(st["work"] / 1000, 65534)),  # kcal ≈ kJ of work for cycling
        (14, UINT16, _scaled(st["avg_speed"], 1000)), (15, UINT16, _scaled(st["max_speed"], 1000)),
        (16, UINT8, _clamp_int(st["avg_hr"], 254)), (17, UINT8, _clamp_int(st["max_hr"], 254)),
        (18, UINT8, _clamp_int(st["avg_cad"], 254)), (19, UINT8, _clamp_int(st["max_cad"], 254)),
        (20, UINT16, _clamp_int(st["avg_power"], 65534)), (21, UINT16, _clamp_int(st["max_power"], 65534)),
        (25, UINT16, 0), (26, UINT16, len(laps)), (28, ENUM, 0),
        (48, UINT32, st["work"]), (MESSAGE_INDEX, UINT16, 0),
    ])
    w.message(ACTIVITY, [
        (TIMESTAMP, UINT32, fit_time(t_end)), (0, UINT32, timer * 1000), (1, UINT16, 1),
        (2, ENUM, 0), (3, ENUM, EVENT_ACTIVITY), (4, ENUM, EVENT_TYPE_STOP),
        (5, UINT32, fit_time(t_end) + _utc_offset(t_end)),
    ])
    return w.to_bytes()


def _scaled(v: Optional[float], scale: float) -> Optional[int]:
    return None if v is None else _clamp_int(v * scale, 65534)


def _utc_offset(unix_s: float) -> int:
    import datetime as dt

    off = dt.datetime.fromtimestamp(unix_s).astimezone().utcoffset()
    return int(off.total_seconds()) if off else 0
