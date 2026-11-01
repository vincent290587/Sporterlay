"""intervals.icu client: planned workouts (as .zwo), athlete FTP / weight / W′, ride uploads.

Auth for personal use is HTTP basic with username "API_KEY" and the key from
intervals.icu → Settings → Developer settings. Athlete id "0" means "the owner of the key".
Plain urllib so there's no extra dependency; call from a worker thread.
"""

from __future__ import annotations

import base64
import datetime as dt
import json
import logging
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from .workout import Workout, parse_zwo_bytes

log = logging.getLogger(__name__)
BASE = "https://intervals.icu/api/v1"
RIDE_TYPES = {"Ride", "VirtualRide", "GravelRide", "MountainBikeRide"}


class IntervalsError(Exception):
    pass


@dataclass
class PlannedWorkout:
    event_id: int
    date: dt.date
    name: str
    sport: str
    duration_s: float
    workout: Workout


@dataclass
class AthleteInfo:
    ftp: Optional[int]
    weight_kg: Optional[float]
    w_prime: Optional[int] = None  # J


class IntervalsClient:
    def __init__(self, api_key: str, athlete_id: str = "0", timeout: float = 15.0):
        self.athlete_id = athlete_id or "0"
        self.timeout = timeout
        self._auth = f"Basic {self._basic_token(api_key)}"

    @staticmethod
    def _basic_token(api_key: str) -> str:
        """Accept the raw key, or an already-encoded base64("API_KEY:<key>") token."""
        k = api_key.strip()
        if k.lower().startswith("basic "):
            k = k[6:].strip()
        try:
            if base64.b64decode(k, validate=True).decode().startswith("API_KEY:"):
                return k
        except Exception:
            pass
        return base64.b64encode(f"API_KEY:{k}".encode()).decode()

    def _get(self, path: str, **params) -> object:
        return self._request(path, params)

    def _request(self, path: str, params: dict, data: Optional[bytes] = None, content_type: str = "") -> object:
        url = f"{BASE}/athlete/{urllib.parse.quote(self.athlete_id)}{path}"
        params = {k: v for k, v in params.items() if v is not None}
        if params:
            url += "?" + urllib.parse.urlencode(params)
        headers = {"Authorization": self._auth, "Accept": "application/json", "User-Agent": "Sporterlay"}
        if content_type:
            headers["Content-Type"] = content_type
        req = urllib.request.Request(url, data=data, headers=headers, method="POST" if data is not None else "GET")
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                raise IntervalsError("intervals.icu rejected the API key") from e
            raise IntervalsError(f"intervals.icu error {e.code}") from e
        except (urllib.error.URLError, TimeoutError) as e:
            raise IntervalsError(f"Can't reach intervals.icu ({getattr(e, 'reason', e)})") from e

    def planned_workouts(self, days_back: int = 1, days_ahead: int = 7) -> list[PlannedWorkout]:
        today = dt.date.today()
        events = self._get(
            "/events",
            oldest=(today - dt.timedelta(days=days_back)).isoformat(),
            newest=(today + dt.timedelta(days=days_ahead)).isoformat(),
            category="WORKOUT",
            ext="zwo",
        )
        out = []
        for ev in events or []:
            sport = ev.get("type") or ""
            b64 = ev.get("workout_file_base64")
            if sport not in RIDE_TYPES or not b64:
                continue
            name = ev.get("name") or "Workout"
            try:
                wo = parse_zwo_bytes(base64.b64decode(b64), name)
            except Exception as e:
                log.warning("Skipping intervals.icu workout %r: %s", name, e)
                continue
            wo.name = name  # the calendar name is what the user recognises
            date = dt.date.fromisoformat((ev.get("start_date_local") or today.isoformat())[:10])
            out.append(PlannedWorkout(int(ev["id"]), date, name, sport, wo.duration, wo))
        out.sort(key=lambda w: (w.date, w.event_id))
        return out

    def athlete(self) -> AthleteInfo:
        a = self._get("")
        ftp = w_prime = None
        for ss in a.get("sportSettings") or []:
            if RIDE_TYPES & set(ss.get("types") or []):
                ftp = ss.get("indoor_ftp") or ss.get("ftp")
                w_prime = ss.get("w_prime")
                break
        weight = a.get("icu_weight") or a.get("weight")
        return AthleteInfo(int(ftp) if ftp else None, float(weight) if weight else None,
                           int(w_prime) if w_prime and w_prime > 1000 else None)

    def upload_activity(self, path: Path, name: str = "", event_id: Optional[int] = None,
                        external_id: str = "") -> str:
        """Upload a .fit file; returns the new activity id. event_id pairs it with a planned workout."""
        boundary = f"----Sporterlay{uuid.uuid4().hex}"
        body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{path.name}\"\r\n"
                f"Content-Type: application/octet-stream\r\n\r\n").encode() + path.read_bytes() + \
            f"\r\n--{boundary}--\r\n".encode()
        res = self._request("/activities", {"name": name or None, "paired_event_id": event_id,
                                            "external_id": external_id or None, "device_name": "Sporterlay"},
                            data=body, content_type=f"multipart/form-data; boundary={boundary}")
        acts = (res or {}).get("activities") or []
        return str((acts[0] or {}).get("id") if acts else (res or {}).get("id") or "")
