"""Persistent user settings (JSON in %APPDATA%\\Sporterlay or ~/.config/sporterlay)."""

from __future__ import annotations

import json
import logging
import os
import sys
from dataclasses import asdict, dataclass, field, fields
from pathlib import Path
from typing import Optional

from .media import BROWSERS

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
    # ERG soft start: only engage once the rider is spinning, ramp the target in, and let go
    # again when cadence drops (otherwise starting from standstill means huge torque)
    erg_engage_rpm: int = 50
    erg_engage_s: float = 3.0
    erg_release_rpm: int = 40
    erg_release_s: float = 2.0
    erg_ramp_s: float = 5.0
    intensity: int = 100  # % applied to workout targets
    scale: float = 1.0
    x: Optional[int] = None  # None = centred at top of primary screen
    y: Optional[int] = None
    opacity: float = 0.92
    locked: bool = True
    last_workout: str = ""  # .zwo path, "icu:<event id>" or "lib:<name>"
    workout_db: str = ""  # ai_advise workouts.json / workoutDB.bin ("" = look in the config folder)
    fe_device_id: int = 0  # 0 = pair with the first trainer found
    hr_device_id: int = 0
    # intervals.icu (Settings → Developer settings → API key); athlete "0" = owner of the key
    icu_api_key: str = ""
    icu_athlete_id: str = "0"
    icu_sync_ftp: bool = True  # take FTP and weight from intervals.icu
    icu_autoload_today: bool = True
    # virtual shifting (Zwift Click / Ctrl+Alt+←/→), used whenever the trainer isn't in ERG
    click_enabled: bool = True
    click_pods: dict = field(default_factory=dict)  # Click pod address -> device type, filled automatically
    click_map: dict = field(default_factory=dict)  # Click button -> action key, only where it differs from the default
    show_button_map: bool = False  # corner panel showing what each Click button does
    gears: int = 24
    gear: int = 0  # current gear, 0 = start at the neutral gear
    real_chainring: int = 50  # gear the bike is actually in on the trainer
    real_cog: int = 17
    bike_weight_kg: float = 9.0
    # bikes swapped onto the trainer: choosing one (tray → Bike) copies its gear and weight above
    bikes: list = field(default_factory=list)  # [{"name", "chainring", "cog", "weight_kg"}]
    bike: str = ""  # name of the bike on the trainer
    wheel_m: float = 2.096  # wheel circumference the trainer's speed is based on (700x25c)
    # Tacx Neo isokinetic mode: target cadence in the real gear (the mode itself is never saved,
    # so the trainer always starts in ERG / normal mode)
    iso_cadence: int = 60
    # countdown beeps before workout step changes
    beeps: bool = True
    # W′ balance gauge; CP is taken as FTP. W′ comes from intervals.icu when FTP sync is on
    show_wbal: bool = True
    w_prime_j: int = 20000
    # summary card in the overlay when a ride ends (also saved as a .png next to the .fit)
    ride_card: bool = True
    ride_card_s: int = 30
    # ride recording (.fit in the activities/ subfolder) and upload to intervals.icu
    record_rides: bool = True
    icu_auto_upload: bool = True
    # Windows: pause the browser video when the rider stops (other apps, e.g. Spotify, are left alone)
    autopause_video: bool = True
    autopause_delay_s: float = 3.0
    autopause_apps: list = field(default_factory=lambda: list(BROWSERS))  # app id substrings
    now_playing: str = "change"  # Spotify track in the overlay: "off", "change" (for a few s) or "always"
    # offer raw power, cadence and HR to Zwift as a Direct Connect device (power meter + HRM only)
    zwift_share: bool = False
    # second screen: the ride on a phone/tablet at http://<this PC>:<web_port>/
    web_screen: bool = False
    web_port: int = 8686
    # HUD: "shown", "hidden", or "auto" = hidden while a second screen is open
    hud_mode: str = "shown"
    # Wahoo KICKR Headwind over BLE, speed from HR and W′ (curves in fan.json in this folder)
    fan: bool = False
    fan_address: str = ""  # filled in after the first connection

    @classmethod
    def load(cls) -> "Settings":
        p = config_dir() / "settings.json"
        try:
            raw = json.loads(p.read_text(encoding="utf-8"))
            known = {f.name for f in fields(cls)}
            s = cls(**{k: v for k, v in raw.items() if k in known})
            if s.bike:
                s.use_bike(s.bike)  # picks up edits to the bike list
            return s
        except FileNotFoundError:
            return cls()
        except Exception as e:
            log.warning("Ignoring unreadable settings %s: %s", p, e)
            return cls()

    def use_bike(self, name: str) -> bool:
        """Make `name` from `bikes` the bike on the trainer (real gear and bike weight)."""
        for b in self.bikes:
            if b.get("name") == name:
                self.bike = name
                self.real_chainring = int(b.get("chainring", self.real_chainring))
                self.real_cog = int(b.get("cog", self.real_cog))
                self.bike_weight_kg = float(b.get("weight_kg", self.bike_weight_kg))
                return True
        return False

    def save(self) -> None:
        d = config_dir()
        try:
            d.mkdir(parents=True, exist_ok=True)
            (d / "settings.json").write_text(json.dumps(asdict(self), indent=2), encoding="utf-8")
        except Exception as e:
            log.warning("Could not save settings: %s", e)
