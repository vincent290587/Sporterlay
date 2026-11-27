"""Power out to a virtual world (the Godot project in `world/godot`) over UDP.

Every tick (4 Hz) one JSON datagram goes to 127.0.0.1:<world_port>:
    {"v": 1, "power": 245, "mark": 2}
`power` is the raw trainer power in W (0 when stale or not pedaling). `mark` counts
the "mark this spot" presses (a Click button) since Sporterlay started, left out
while 0; the world saves a mark each time it goes up, so a lost datagram loses
nothing (the next one carries the same count). It's one way:
nothing comes back, and Sporterlay's own riding (ERG, gears, speed) doesn't change.
The world turns power into speed with its own physics. Sending to a port nobody
listens on is harmless: Sporterlay never depends on the world running.

`WorldProcess` starts the world from the tray with `--world=`, `--seed=` and `--port=`.
The program is `settings.world_program` if set, else the exported
`world/godot/build/SporterlayWorld.exe`, else a Godot 4 binary found in the usual
places and run with `--path world/godot`. A fresh checkout has no `.godot/` cache, so
the project is imported once first (headless), otherwise the window stays black.
"""

from __future__ import annotations

import json
import logging
import os
import socket
import subprocess
import sys
import threading
from pathlib import Path
from typing import Callable, Optional

log = logging.getLogger(__name__)


class WorldLink:
    def __init__(self, port: int):
        self.addr = ("127.0.0.1", port)
        self._sock: Optional[socket.socket] = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._sock.setblocking(False)
        self.marks = 0
        log.info("Sending power to udp://%s:%d", *self.addr)

    def send(self, power: Optional[int]) -> None:
        if self._sock is None:
            return
        data = {"v": 1, "power": power or 0}
        if self.marks:
            data["mark"] = self.marks
        msg = json.dumps(data, separators=(",", ":")).encode()
        try:
            self._sock.sendto(msg, self.addr)
        except OSError as e:  # Windows: ICMP port unreachable from an earlier send, buffer full
            log.debug("World link send: %s", e)

    def mark(self) -> None:
        """Ask the world to mark the rider's spot (sent with the next tick)."""
        self.marks += 1

    def close(self) -> None:
        if self._sock is not None:
            self._sock.close()
            self._sock = None


# worlds offered in the tray (the world's `gallery` is a test bench, left out)
WORLDS = {"valley": "Valley", "riverlands": "Riverlands", "transylvania": "Transylvania", "canyon": "Canyon", "endless": "Endless", "giant": "Giant Wetland"}

PROJECT = Path(__file__).resolve().parent.parent / "world" / "godot"   # only in a source checkout


def _godot_candidates() -> list[Path]:
    home = Path.home()
    roots = [Path("C:/Tools/Godot"), home / "Downloads", home / "Desktop", home / "Apps",
             Path(os.environ.get("LOCALAPPDATA", home)) / "Programs", Path("C:/Program Files/Godot")]
    pats = ["Godot_v4*.exe", "*/Godot_v4*.exe"] if sys.platform == "win32" else ["Godot_v4*", "*/Godot_v4*"]
    found = []
    for r in roots:
        if r.is_dir():
            for pat in pats:
                found += [p for p in r.glob(pat) if p.is_file() and "console" not in p.name.lower()]
    found.sort(key=lambda p: p.name, reverse=True)   # newest version first
    return found


def is_godot(program: Path) -> bool:
    return program.name.lower().startswith("godot")


def find_program(configured: str) -> Optional[Path]:
    """The world program to run, or None. A Godot binary needs the project (`PROJECT`)."""
    if configured:
        p = Path(configured)
        return p if p.is_file() else None
    exported = PROJECT / "build" / ("SporterlayWorld.exe" if sys.platform == "win32" else "SporterlayWorld")
    if exported.is_file():
        return exported
    if (PROJECT / "project.godot").is_file():
        c = _godot_candidates()
        return c[0] if c else None
    return None


class WorldProcess:
    """The world program started from the tray. `status` is a short line for the menu."""

    def __init__(self, on_status: Callable[[str], None] = lambda _s: None):
        self._proc: Optional[subprocess.Popen] = None
        self._lock = threading.Lock()
        self._on_status = on_status
        self.status = ""

    @property
    def running(self) -> bool:
        return self._proc is not None and self._proc.poll() is None

    def start(self, program: Path, world: str, seed: int, port: int) -> None:
        self.stop()
        self.status = "Starting…"
        threading.Thread(target=self._start, args=(program, world, seed, port),
                         daemon=True, name="world-start").start()

    def _start(self, program: Path, world: str, seed: int, port: int) -> None:
        flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
        argv = [str(program)]
        if is_godot(program):
            if not (PROJECT / "project.godot").is_file():
                return self._set("Godot needs the world/godot project (run from source)")
            argv += ["--path", str(PROJECT)]
            if not (PROJECT / ".godot").is_dir():
                self._set("Importing the world project (first start)…")
                log.info("World: importing %s", PROJECT)
                try:
                    subprocess.run(argv + ["--headless", "--import"], timeout=600, creationflags=flags,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                except (OSError, subprocess.SubprocessError) as e:
                    return self._set(f"Import failed: {e}")
        argv += ["--", f"--world={world}", f"--seed={seed}", f"--port={port}"]
        log.info("World: starting %s", " ".join(argv))
        try:
            proc = subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError as e:
            return self._set(f"Couldn't start: {e}")
        with self._lock:
            self._proc = proc
        self._set(f"{WORLDS.get(world, world)}, seed {seed}")

    def _set(self, status: str) -> None:
        self.status = status
        self._on_status(status)

    def stop(self) -> None:
        with self._lock:
            proc, self._proc = self._proc, None
        if proc is not None and proc.poll() is None:
            log.info("World: stopping")
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
        self.status = ""
