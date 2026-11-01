"""End-of-ride numbers for the summary card, from the recorder's 1 Hz samples (the same data
that goes into the .fit file, so they match what intervals.icu shows). Pure Python, no Qt."""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from typing import Optional

from .wbal import step as wbal_step

# Upper bounds (fraction of FTP) of the zones the HUD colours by: Z1 … Z6
ZONE_LIMITS = (0.60, 0.76, 0.90, 1.05, 1.19, 99.0)
ON_TARGET = 0.05  # within ±5 % of the target counts as on target...
ON_TARGET_AVG_S = 3  # ...using a 3 s average, raw 1 Hz power is too jumpy outside ERG


@dataclass
class RideSummary:
    name: str
    start: float  # unix time
    moving_s: int
    distance_km: float
    avg_power: int
    np: int
    intensity: float  # IF
    tss: int
    kj: int
    avg_hr: Optional[int]
    max_hr: Optional[int]
    avg_cadence: Optional[int]
    wbal_min: Optional[float]  # lowest W′ balance, fraction
    zones: list[int] = field(default_factory=list)  # seconds in Z1..Z6
    on_target: Optional[float] = None  # fraction of the seconds with a target spent within ±5 %
    note: str = ""  # e.g. the ramp test result


def normalized_power(powers: list[float]) -> float:
    """30 s rolling average, 4th-power mean, 4th root (needs 1 Hz samples)."""
    if len(powers) < 30:
        return sum(powers) / len(powers) if powers else 0.0
    win: deque = deque()
    total = acc = 0.0
    n = 0
    for p in powers:
        win.append(p)
        total += p
        if len(win) > 30:
            total -= win.popleft()
        if len(win) == 30:
            acc += (total / 30) ** 4
            n += 1
    return (acc / n) ** 0.25


def summarize(rows: list[tuple], ftp: int, w_prime: int, name: str = "", start: Optional[float] = None) -> RideSummary:
    """rows: (t, power, hr, cadence, speed m/s, distance m, target W) per moving second."""
    powers = [float(r[1] or 0) for r in rows]
    n = len(rows)
    np_ = normalized_power(powers)
    intensity = np_ / ftp if ftp else 0.0
    hrs = [r[2] for r in rows if r[2]]
    cads = [r[3] for r in rows if r[3]]

    zones = [0] * len(ZONE_LIMITS)
    for p in powers:
        f = p / ftp if ftp else 0.0
        zones[next(i for i, lim in enumerate(ZONE_LIMITS) if f < lim or i == len(ZONE_LIMITS) - 1)] += 1

    # W′ balance over the ride; stops in between count as recovery at 0 W
    bal, low, prev_t = float(w_prime), float(w_prime), None
    if w_prime > 0 and ftp:
        for r, p in zip(rows, powers):
            if prev_t is not None and r[0] - prev_t > 1:
                bal = wbal_step(bal, 0.0, ftp, w_prime, r[0] - prev_t - 1)
            bal = wbal_step(bal, p, ftp, w_prime, 1.0)
            low = min(low, bal)
            prev_t = r[0]

    with_target = on = 0
    recent: deque = deque(maxlen=ON_TARGET_AVG_S)
    for r, p in zip(rows, powers):
        recent.append(p)
        target = r[6] if len(r) > 6 else None
        if target:
            with_target += 1
            if abs(sum(recent) / len(recent) - target) <= ON_TARGET * target:
                on += 1

    return RideSummary(
        name=name,
        start=start if start is not None else (rows[0][0] if rows else 0.0),
        moving_s=n,
        distance_km=(max((r[5] or 0) for r in rows) / 1000) if rows else 0.0,
        avg_power=round(sum(powers) / n) if n else 0,
        np=round(np_),
        intensity=intensity,
        tss=round(n * intensity * intensity / 36) if ftp else 0,  # s × IF² / 3600 × 100
        kj=round(sum(powers) / 1000),
        avg_hr=round(sum(hrs) / len(hrs)) if hrs else None,
        max_hr=max(hrs) if hrs else None,
        avg_cadence=round(sum(cads) / len(cads)) if cads else None,
        wbal_min=low / w_prime if w_prime > 0 and ftp and rows else None,
        zones=zones,
        on_target=on / with_target if with_target >= 60 else None,
    )
