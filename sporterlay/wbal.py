"""W′ balance: how much of the anaerobic work capacity above CP is left.

Differential model (Froncioni / Skiba / Clarke):
  above CP:  dW/dt = -(P - CP)
  below CP:  dW/dt = (W′ - W) * (CP - P) / W′
Recovery is applied in its exact exponential form, so it doesn't depend on the tick length.
CP is taken as FTP. Pure Python, no Qt.
"""

from __future__ import annotations

import math
from typing import Optional

from .workout import Workout


def step(bal: float, power: float, cp: float, w_prime: float, dt: float) -> float:
    if power > cp:
        return bal - (power - cp) * dt
    # W′ - W decays exponentially with rate (CP - P) / W′
    return w_prime - (w_prime - bal) * math.exp(-(cp - power) * dt / w_prime)


class WPrimeBalance:
    def __init__(self) -> None:
        self.balance: Optional[float] = None  # J; None until the first update
        self._w_prime = 0.0

    def reset(self) -> None:
        self.balance = None

    def update(self, power: float, cp: float, w_prime: float, dt: float) -> None:
        if cp <= 0 or w_prime <= 0:
            return
        if self.balance is None:
            self.balance = w_prime
        elif w_prime != self._w_prime and self._w_prime > 0:
            self.balance *= w_prime / self._w_prime  # W′ setting changed mid-ride: keep the same fraction
        self._w_prime = w_prime
        # can go below zero when FTP is set too low; shown as 0 %, but kept so recovery stays honest
        self.balance = min(w_prime, step(self.balance, power, cp, w_prime, dt))

    def fraction(self) -> Optional[float]:
        if self.balance is None or self._w_prime <= 0:
            return None
        return self.balance / self._w_prime


FREE_RIDE_FRACTION = 0.55  # assumed effort (of CP) for steps without a target when predicting


def predict(workout: Workout, watts_for, cp: float, w_prime: float, step_s: float = 2.0) -> list[tuple[float, float]]:
    """Expected W′ balance over a workout if every target is hit: [(workout seconds, fraction)].
    watts_for(frac) converts a target (FTP fraction) to watts, honouring intensity and FTP override."""
    if cp <= 0 or w_prime <= 0:
        return []
    bal, t = w_prime, 0.0
    out = [(0.0, 1.0)]
    for seg in workout.segments:
        n = max(1, math.ceil(seg.duration / step_s))
        dt = seg.duration / n
        for k in range(n):
            w = watts_for(seg.power_at((k + 0.5) * dt))
            bal = min(w_prime, step(bal, cp * FREE_RIDE_FRACTION if w is None else w, cp, w_prime, dt))
            t += dt
            out.append((t, bal / w_prime))
    return out
