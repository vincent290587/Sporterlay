"""Countdown beeps before workout step changes.

`cues_between()` is pure: it looks at how far the workout clock moved during one tick and
returns the cues crossed. It only fires on the workout clock moving forward naturally, so
pausing, the ERG ramp hold and not pedaling can't make it beep early or twice, and skip /
back (which jump the clock outside a tick) stay silent.

`Beeper` plays them without blocking the Qt thread: short WAV tones are generated once into
the config folder and played with winsound's SND_ASYNC (it mixes over Spotify / YouTube).
"""

from __future__ import annotations

import logging
import math
import struct
import sys
import wave
from pathlib import Path
from typing import Optional

from .workout import WorkoutPlayer

log = logging.getLogger(__name__)

COUNTDOWN = (3, 2, 1)
MIN_CHANGE = 0.05  # FTP fraction; smaller target changes (e.g. ramp pieces) don't get a countdown
HEADS_UP_S = 10  # extra warning before a hard effort...
HARD = 1.05  # ...that is above threshold...
HEADS_UP_MIN_SEG_S = 60  # ...when the current step is long enough for it to make sense


def _change(player: WorkoutPlayer, i: int) -> Optional[str]:
    """Kind of change at the end of segment i: "up", "down", "finish" or None (not worth a beep)."""
    segs = player.workout.segments
    if i + 1 >= len(segs):
        return "finish"
    a, b = segs[i], segs[i + 1]
    pa, pb = a.power_at(a.duration), b.power_at(0)
    if pa is None and pb is None:
        return None
    if pa is None or pb is None:  # into or out of a free ride / max effort
        return "up" if pb is None or pb > (pa or 0) else "down"
    if abs(pb - pa) < MIN_CHANGE:
        return None
    return "up" if pb > pa else "down"


def cues_between(player: WorkoutPlayer, before: float, after: float) -> list[str]:
    """Cues for the workout clock moving from `before` to `after` within one tick:
    "tick" (3-2-1), "up" / "down" (step change), "finish", "heads_up"."""
    if after <= before:
        return []
    segs = player.workout.segments
    out: list[str] = []
    # normally a single boundary, but a long tick (or a 1 s segment) can cross more than one
    for i in range(len(segs)):
        end = player.segment_start(i) + segs[i].duration
        if end <= before:
            continue
        if end - before > HEADS_UP_S + 1.0 and end - after > HEADS_UP_S + 1.0:
            break  # this boundary and every later one are too far away
        kind = _change(player, i)
        if kind is None:
            continue
        rem_a, rem_b = end - before, end - after
        if (kind == "up" and segs[i].duration >= HEADS_UP_MIN_SEG_S and i + 1 < len(segs)
                and (segs[i + 1].power_at(0) or 0) >= HARD and rem_a > HEADS_UP_S >= rem_b):
            out.append("heads_up")
        for k in COUNTDOWN:
            if rem_a > k >= rem_b and k < segs[i].duration:
                out.append("tick")
        if rem_a > 0 >= rem_b:
            out.append(kind)
    return out


# ---- sound -------------------------------------------------------------------------------
# name -> list of (frequency Hz, duration s); 0 Hz is a silence
TONES = {
    "tick": [(880, 0.12)],
    "up": [(1320, 0.45)],
    "down": [(660, 0.45)],
    "finish": [(880, 0.15), (0, 0.05), (1100, 0.15), (0, 0.05), (1320, 0.4)],
    "heads_up": [(660, 0.08), (0, 0.07), (660, 0.08)],
}
RATE = 22050
VOLUME = 0.45
TONE_VERSION = 1  # bump when TONES change so the cached files are rebuilt


def write_tone(path: Path, parts: list[tuple[float, float]]) -> None:
    frames = bytearray()
    for freq, dur in parts:
        n = int(RATE * dur)
        fade = min(int(RATE * 0.01), n // 2)  # 10 ms fade in/out: no clicks
        for k in range(n):
            if freq <= 0:
                v = 0.0
            else:
                env = min(1.0, k / fade if fade else 1.0, (n - k) / fade if fade else 1.0)
                v = VOLUME * env * math.sin(2 * math.pi * freq * k / RATE)
            frames += struct.pack("<h", int(v * 32767))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))


class Beeper:
    def __init__(self, folder: Path):
        self.folder = folder
        self._files: dict[str, Path] = {}

    def _file(self, name: str) -> Optional[Path]:
        if name not in self._files:
            path = self.folder / f"{name}_v{TONE_VERSION}.wav"
            if not path.exists():
                try:
                    self.folder.mkdir(parents=True, exist_ok=True)
                    write_tone(path, TONES[name])
                except OSError as e:
                    log.warning("Could not write %s: %s", path, e)
                    return None
            self._files[name] = path
        return self._files[name]

    def play(self, name: str) -> None:
        if sys.platform == "win32":
            import winsound

            path = self._file(name)
            if path is not None:
                # SND_ASYNC returns at once; a new sound cuts the previous one short, which is fine
                winsound.PlaySound(str(path), winsound.SND_FILENAME | winsound.SND_ASYNC | winsound.SND_NODEFAULT)
        else:
            from PyQt6.QtWidgets import QApplication

            QApplication.beep()
