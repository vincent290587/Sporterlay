"""Persistent user settings (JSON in %APPDATA%\\Sporterlay or ~/.config/sporterlay)."""

from __future__ import annotations

import json
import logging
import os
import sys
from dataclasses import asdict, dataclass, fields
from pathlib import Path
from typing import Optional

log = logging.getLogger(__name__)


def config_dir() -> Path:
    if sys.platform == "win32":
        base = Path(os.environ.get("APPDATA", Path.home()))
        return base / "Sporterlay"
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "sporterlay"


@dataclass
class Settings:
    ftp: int = 250
    weight_kg: float = 75.0
    power_avg_s: int = 3  # smoothing for the big power number (1 = instantaneous)
    erg: bool = True
    intensity: int = 100  # % applied to workout targets
    scale: float = 1.0
    x: Optional[int] = None  # None = centred at top of primary screen
    y: Optional[int] = None
    opacity: float = 0.92
    locked: bool = True
    last_workout: str = ""
    fe_device_id: int = 0  # 0 = pair with the first trainer found
    hr_device_id: int = 0

    @classmethod
    def load(cls) -> "Settings":
        p = config_dir() / "settings.json"
        try:
            raw = json.loads(p.read_text(encoding="utf-8"))
            known = {f.name for f in fields(cls)}
            return cls(**{k: v for k, v in raw.items() if k in known})
        except FileNotFoundError:
            return cls()
        except Exception as e:
            log.warning("Ignoring unreadable settings %s: %s", p, e)
            return cls()

    def save(self) -> None:
        d = config_dir()
        try:
            d.mkdir(parents=True, exist_ok=True)
            (d / "settings.json").write_text(json.dumps(asdict(self), indent=2), encoding="utf-8")
        except Exception as e:
            log.warning("Could not save settings: %s", e)
