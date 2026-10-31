"""Ride state: smoothing, totals, workout progress and trainer (ERG) control.

Pure Python, no Qt, so it can be tested on its own.
"""

from __future__ import annotations

from collections import deque
from typing import Optional

from .settings import Settings
from .shifting import gear_ratios, neutral_gear, sim_grade
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
        self.ratios = gear_ratios(max(2, settings.gears))
        if not 1 <= settings.gear <= len(self.ratios):
            settings.gear = neutral_gear(self.ratios, self.real_ratio)
        self.grade = 0.0  # last grade sent in simulation mode
        self._last_grade_t = -1.0
        # ERG soft start state
        self.erg_engaged = False
        self._spin_since: Optional[float] = None  # cadence above engage threshold since
        self._slow_since: Optional[float] = None  # cadence below release threshold since
        self._ramp_from = 0.0
        self._ramp_t0 = 0.0

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

    # ---- virtual shifting -------------------------------------------------------
    @property
    def real_ratio(self) -> float:
        return self.settings.real_chainring / max(1, self.settings.real_cog)

    @property
    def gear_factor(self) -> float:
        return self.ratios[self.settings.gear - 1] / self.real_ratio

    def shift(self, delta: int) -> None:
        self.settings.gear = max(1, min(len(self.ratios), self.settings.gear + delta))
        self._last_grade_t = -1.0
        self._control_trainer()  # apply now, not on the next tick

    @property
    def erg_wanted(self) -> bool:
        """The workout calls for ERG right now (ERG on, workout running, step has a target)."""
        p = self.player
        return (self.settings.erg and p is not None and not p.paused and not p.finished
                and p.target_fraction() is not None)

    @property
    def erg_active(self) -> bool:
        """ERG is actually holding the power (wanted, and the rider is spinning)."""
        return self.erg_wanted and self.erg_engaged

    @property
    def erg_waiting(self) -> bool:
        return self.erg_wanted and not self.erg_engaged

    @property
    def erg_at_target(self) -> bool:
        """ERG engaged and its soft-start ramp is finished."""
        return self.erg_active and self._now - self._ramp_t0 >= self.settings.erg_ramp_s

    @property
    def clock_held(self) -> bool:
        """Pedaling, but the workout clock waits for ERG to be back at the target."""
        return self.pedaling and self.erg_wanted and not self.erg_at_target

    def erg_thresholds(self) -> tuple[int, int]:
        """(engage rpm, release rpm); lowered for steps with a low cadence target
        (e.g. 50 rpm strength efforts), so ERG can come back without spinning up."""
        s = self.settings
        engage, release = s.erg_engage_rpm, s.erg_release_rpm
        if self.player and not self.player.finished:
            cad = self.player.current()[1].cadence
            if cad:
                engage, release = min(engage, cad - 10), min(release, cad - 15)
        return engage, release

    def _update_erg_engagement(self) -> None:
        s, t = self.settings, self.telemetry
        if not self.erg_wanted:
            self.erg_engaged = False
            self._spin_since = self._slow_since = None
            return
        cad, power = t.cadence, t.power or 0
        if cad is None:  # trainer without cadence: fall back to "producing real power"
            spinning, slow = power > 50, power <= 20
        else:
            engage, release = self.erg_thresholds()
            spinning, slow = cad >= engage, cad < release
        if not self.erg_engaged:
            self._spin_since = (self._spin_since or self._now) if spinning else None
            if self._spin_since is not None and self._now - self._spin_since >= s.erg_engage_s:
                self.erg_engaged = True
                self._slow_since = None
                self._ramp_from = float(self.power_display or power)
                self._ramp_t0 = self._now
        else:
            self._slow_since = (self._slow_since or self._now) if slow else None
            if self._slow_since is not None and self._now - self._slow_since >= s.erg_release_s:
                self.erg_engaged = False
                self._spin_since = None

    def erg_target(self) -> Optional[int]:
        """Workout target, ramped in over erg_ramp_s right after ERG engages."""
        target = self.target_watts()
        if target is None:
            return None
        ramp = self.settings.erg_ramp_s
        f = (self._now - self._ramp_t0) / ramp if ramp > 0 else 1.0
        if f >= 1.0:
            return target
        return round(self._ramp_from + (target - self._ramp_from) * max(f, 0.0))

    @property
    def speed_kmh(self) -> Optional[float]:
        """Speed to show: virtual speed in the current gear when shifting is in effect."""
        v = self.telemetry.speed_kmh
        if v is None:
            return None
        return v if self.erg_active else v * self.gear_factor

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

    @property
    def workout_ftp(self) -> int:
        wo = self.player.workout if self.player else None
        return (wo.ftp_override if wo and wo.ftp_override else None) or self.settings.ftp

    def watts_for(self, frac: Optional[float]) -> Optional[int]:
        if frac is None:
            return None
        return round(frac * self.workout_ftp * self.settings.intensity / 100)

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
            self.distance_km += (self.speed_kmh or 0) * dt / 3600

        self._update_erg_engagement()
        if self.player:
            before = self.player.elapsed
            # after a start or a stop, the clock waits until ERG is back at the target, so the
            # soft start doesn't eat into the interval
            self.player.tick(dt, self.pedaling and not self.clock_held)
            if self.player.elapsed > before and t.power is not None:
                # keep ~1 sample per second for the trace
                if not self.trace or self.player.elapsed - self.trace[-1][0] >= 1.0:
                    self.trace.append((self.player.elapsed, t.power))

        self._control_trainer()

    def _control_trainer(self) -> None:
        self.source.configure(self.settings.weight_kg, self.settings.bike_weight_kg)
        if self.erg_active:
            self.source.set_target_power(self.erg_target())
            self._last_grade_t = -1.0  # resend sim grade at once when ERG lets go
            return
        # simulation mode with virtual gears; grade depends on speed, so refresh ~2x per second
        if self._now - self._last_grade_t < 0.5:
            return
        self._last_grade_t = self._now
        v = (self.telemetry.speed_kmh or 0) / 3.6
        mass = self.settings.weight_kg + self.settings.bike_weight_kg
        self.grade = sim_grade(v, self.gear_factor, mass)
        self.source.set_free_ride(self.grade)
