"""FTP ramp test: the workout, and spotting the moment the rider can't hold the ramp any more.

The FTP itself isn't computed here: the ride is uploaded and intervals.icu's eFTP for that
activity (`icu_pm_ftp`, from its power-curve model) is offered as the new FTP (see `App`).
Pure Python, no Qt.
"""

from __future__ import annotations

from typing import Optional

from .workout import Segment, Workout

NAME = "Ramp test"
WARMUP_S = 300
STEP_S = 60
STEP_W = 20
COOLDOWN_S = 300
FAIL_RPM = 60  # below this cadence...
FAIL_S = 5  # ...for this long, the ramp is over
MAX_FRACTION = 2.0  # the ramp goes up to 2 × FTP (nobody gets there)


def ramp_workout(ftp: int, step_w: int = STEP_W) -> Workout:
    """Warm-up, +step_w W every minute from ~half FTP, then a cool-down. Targets are fractions of
    the given FTP, like any workout."""
    ftp = max(ftp, 50)
    start = max(80, round(ftp * 0.5 / 10) * 10)
    segs = [Segment(WARMUP_S, 0.35, (start - step_w) / ftp, label="Warm-up")]
    w = start
    while w <= ftp * MAX_FRACTION:
        segs.append(Segment(STEP_S, w / ftp, w / ftp, label=f"Ramp {w} W"))
        w += step_w
    segs.append(Segment(COOLDOWN_S, 0.4, 0.4, label="Cool-down"))
    wo = Workout(NAME, segs, description="Ramp test: +20 W every minute until you can't hold it.")
    wo.is_ramp_test = True
    return wo


def is_ramp_test(workout: Optional[Workout]) -> bool:
    return bool(getattr(workout, "is_ramp_test", False))


class RampTest:
    """Watches a ramp test in progress; `update()` returns True once, when the rider has failed
    (cadence under FAIL_RPM for FAIL_S during the ramp, after its first step)."""

    def __init__(self, workout: Workout):
        self.workout = workout
        self.ramp_start = workout.segments[0].duration
        self.cooldown_start = workout.duration - workout.segments[-1].duration
        self.ended = False
        self.peak_step_w: Optional[int] = None  # last ramp step reached
        self._slow_since: Optional[float] = None

    def in_ramp(self, elapsed: float) -> bool:
        return self.ramp_start <= elapsed < self.cooldown_start

    def update(self, now: float, elapsed: float, cadence: Optional[int], target_w: Optional[int]) -> bool:
        if self.ended or not self.in_ramp(elapsed):
            if elapsed >= self.cooldown_start and not self.ended:
                self.ended = True  # rode the whole ramp (!)
            return False
        if target_w is not None:
            self.peak_step_w = target_w
        if elapsed < self.ramp_start + STEP_S or (cadence or 0) >= FAIL_RPM:
            self._slow_since = None
            return False
        if self._slow_since is None:
            self._slow_since = now
        if now - self._slow_since >= FAIL_S:
            self.ended = True
            return True
        return False

    def end(self) -> None:
        """The rider says they're done."""
        self.ended = True
