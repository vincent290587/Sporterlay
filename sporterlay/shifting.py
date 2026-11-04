"""Virtual gears on a plain FE-C trainer.

The trainer is put in simulation mode (FE-C page 51, grade) and we pick the grade so
that, at the trainer's current speed v, the resistance equals what riding on a flat
road would need in the *virtual* gear.

Virtual speed is v' = v * k, where k = virtual ratio / real ratio (the chainring/cog
the bike is actually in on the trainer). Flat-road power at v' is
    P' = (Crr m g + K v'^2) v'
and the trainer, at its own speed v and grade G, applies
    P  = (m g (G + Crr) + K v^2) v
Setting P = P' gives a closed form:
    G = Crr (k - 1) + K v^2 (k^3 - 1) / (m g)
K = 0.5 x the FE-C wind resistance coefficient (the spec's air drag is
0.5 * coeff * v^2; we send the coefficient explicitly, page 50) and m is
rider + bike mass (page 55), so the trainer's internal model matches this one.
"""

from __future__ import annotations

import math

G_ACC = 9.81
CRR = 0.004  # sent in page 51
WIND_K = 0.51  # kg/m, FE-C default wind resistance coefficient; sent in page 50
AERO_K = 0.5 * WIND_K  # drag force = AERO_K * v^2


def gear_ratios(n: int = 24, lo: float = 0.9, hi: float = 4.8) -> list[float]:
    """Geometric gear table, roughly a 34x34 … 53x11 range with ~7 % steps."""
    if n < 2:
        return [lo]
    step = (hi / lo) ** (1 / (n - 1))
    return [lo * step**i for i in range(n)]


def neutral_gear(ratios: list[float], real_ratio: float) -> int:
    """1-based gear closest to the bike's real ratio (shifting there feels like no change)."""
    return 1 + min(range(len(ratios)), key=lambda i: abs(ratios[i] - real_ratio))


def sim_grade(speed_ms: float, k: float, mass_kg: float) -> float:
    """Grade in % to send to the trainer for gear factor k at trainer speed v."""
    v = max(speed_ms, 0.0)
    g = CRR * (k - 1) + AERO_K * v * v * (k**3 - 1) / (mass_kg * G_ACC)
    return max(-10.0, min(20.0, g * 100))

