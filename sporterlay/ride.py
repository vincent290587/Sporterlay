"""Ride state: smoothing, totals, workout progress and trainer (ERG) control.

Pure Python, no Qt, so it can be tested on its own.
"""

from __future__ import annotations

from collections import deque
from typing import Optional

from .settings import Settings
from .sources import Telemetry
from .workout import Workout, WorkoutPlayer


class Ride:
    def __init__(self, settings: Settings, source):
        self.settings = settings
        self.source = source
        self.telemetry = Telemetry()
        self.player: Optional[WorkoutPlayer] = None
        self.ride_time = 0.0  # moving time, s
        self.distance_km = 0.0
        self._energy_j = 0.0
        self._recent: deque[tuple[float, int]] = deque()  # (t, power) for smoothing
        self._now = 0.0
        # (workout seconds, watts) samples for drawing the power trace on the workout graph
        self.trace: list[tuple[float, int]] = []

    # ---- workout ---------------------------------------------------------
    def load_workout(self, workout: Workout) -> None:
        self.player = WorkoutPlayer(workout)
        self.trace = []

    def unload_workout(self) -> None:
        self.player = None
        self.trace = []

    def reset(self) -> None:
        self.ride_time = 0.0
        self.distance_km = 0.0
        self._energy_j = 0.0
        if self.player:
            self.load_workout(self.player.workout)

    # ---- derived values -----------------------------------------------------
    @property
    def pedaling(self) -> bool:
        t = self.telemetry
        return bool((t.power or 0) > 0 or (t.cadence or 0) > 0)

    @property
    def power_display(self) -> Optional[int]:
        if self.telemetry.power is None:
            return None
        if not self._recent:
            return self.telemetry.power
        return round(sum(p for _, p in self._recent) / len(self._recent))

    @property
    def avg_power(self) -> Optional[int]:
        return round(self._energy_j / self.ride_time) if self.ride_time > 1 else None

    @property
    def kj(self) -> float:
        return self._energy_j / 1000

    def target_watts(self) -> Optional[int]:
        if not self.player or self.player.finished:
            return None
        return self.watts_for(self.player.target_fraction())

    def watts_for(self, frac: Optional[float]) -> Optional[int]:
        if frac is None:
            return None
        return round(frac * self.settings.ftp * self.settings.intensity / 100)

    # ---- update loop -------------------------------------------------------
    def tick(self, dt: float) -> None:
        self._now += dt
        self.telemetry = t = self.source.snapshot()

        win = max(1, self.settings.power_avg_s)
        if t.power is not None:
            self._recent.append((self._now, t.power))
        while self._recent and self._now - self._recent[0][0] > win - 1e-6:
            self._recent.popleft()

        if self.pedaling:
            self.ride_time += dt
            self._energy_j += (t.power or 0) * dt
            self.distance_km += (t.speed_kmh or 0) * dt / 3600

        if self.player:
            before = self.player.elapsed
            self.player.tick(dt, self.pedaling)
            if self.player.elapsed > before and t.power is not None:
                # keep ~1 sample per second for the trace
                if not self.trace or self.player.elapsed - self.trace[-1][0] >= 1.0:
                    self.trace.append((self.player.elapsed, t.power))

        self._control_trainer()

    def _control_trainer(self) -> None:
        target = self.target_watts()
        workout_active = self.player is not None and not self.player.paused and not self.player.finished
        if self.settings.erg and workout_active and target is not None:
            self.source.set_target_power(target)
        else:
            self.source.set_free_ride(0.0)
