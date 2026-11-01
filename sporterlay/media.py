"""Windows media sessions: pause YouTube when the rider stops, and show what Spotify plays.

Windows lists every app playing media as its own session (System Media Transport Controls),
each with an app id: "Chrome", "MSEdge", "308046B0AF4A39CB" (Firefox), "Spotify.exe", ... The
global play/pause *key* goes to whichever session Windows thinks is current, often Spotify,
so instead `MediaSessions` talks to the browser's session directly and leaves Spotify alone.

`MediaSessions` polls the sessions twice a second on its own thread (asyncio loop for the
WinRT calls) and keeps a snapshot; commands are queued to that thread. Off Windows, or
without the winrt packages, it stays empty and does nothing.

`AutoPause` and `NowPlaying` are pure logic on top of the snapshot, testable anywhere.
"""

from __future__ import annotations

import asyncio
import logging
import sys
import threading
from dataclasses import dataclass
from typing import Optional

log = logging.getLogger(__name__)

POLL_S = 0.5
BROWSERS = ["chrome", "msedge", "firefox", "308046b0af4a39cb", "brave", "opera", "vivaldi"]


@dataclass(frozen=True)
class Session:
    app: str  # SourceAppUserModelId
    status: str  # "playing", "paused", "stopped", "other"
    title: str = ""
    artist: str = ""

    @property
    def key(self) -> tuple[str, str]:
        # sessions have no stable id; app + title tells the paused video apart from other tabs
        return self.app, self.title


def is_spotify(s: Session) -> bool:
    return "spotify" in s.app.lower()


def matches(s: Session, apps: list[str]) -> bool:
    a = s.app.lower()
    return not is_spotify(s) and any(m.lower() in a for m in apps if m)


class MediaSessions:
    def __init__(self) -> None:
        self.available = False
        self.error = ""
        self._sessions: list[Session] = []
        self._lock = threading.Lock()
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._stop = False
        self._seen_apps: set[str] = set()
        if sys.platform == "win32":
            self._thread = threading.Thread(target=self._run, name="media", daemon=True)
            self._thread.start()

    @property
    def sessions(self) -> list[Session]:
        with self._lock:
            return list(self._sessions)

    def pause(self, keys: list[tuple[str, str]]) -> None:
        self._command("pause", keys)

    def play(self, keys: list[tuple[str, str]]) -> None:
        self._command("play", keys)

    def close(self) -> None:
        self._stop = True

    # ---- worker thread -------------------------------------------------------------------
    def _command(self, what: str, keys) -> None:
        if self._loop is not None and keys:
            asyncio.run_coroutine_threadsafe(self._apply(what, set(keys)), self._loop)

    def _run(self) -> None:
        try:
            # winrt.windows.foundation.collections makes the session list iterable
            import winrt.windows.foundation.collections  # noqa: F401
            from winrt.windows.media.control import (
                GlobalSystemMediaTransportControlsSessionManager as Manager,
                GlobalSystemMediaTransportControlsSessionPlaybackStatus as Status,
            )
        except Exception as e:  # missing package in a source checkout
            self.error = f"media sessions unavailable ({e})"
            log.warning("Media sessions unavailable: %s", e)
            return
        self._Manager = Manager
        self._status = {Status.PLAYING: "playing", Status.PAUSED: "paused", Status.STOPPED: "stopped"}
        self._mgr = None
        self._raw: list = []  # (Session, WinRT session object) from the last poll
        self._loop = asyncio.new_event_loop()
        self.available = True
        try:
            self._loop.run_until_complete(self._poll_forever())
        finally:
            self._loop.close()

    async def _poll_forever(self) -> None:
        failures = 0
        while not self._stop:
            try:
                if self._mgr is None:
                    self._mgr = await self._Manager.request_async()
                await self._poll()
                failures = 0
            except Exception as e:
                failures += 1
                if failures == 1:
                    log.warning("Media sessions: %s", e)
                self._mgr = None  # get a fresh manager next time
            await asyncio.sleep(POLL_S if failures < 5 else 10)

    async def _poll(self) -> None:
        raw = []
        for ws in self._mgr.get_sessions():
            app = ws.source_app_user_model_id or ""
            info = ws.get_playback_info()
            status = self._status.get(info.playback_status if info else None, "other")
            title = artist = ""
            try:
                props = await ws.try_get_media_properties_async()
                title, artist = props.title or "", props.artist or ""
            except Exception:
                pass
            raw.append((Session(app, status, title, artist), ws))
            if app not in self._seen_apps:  # helps adding a browser that isn't recognised
                self._seen_apps.add(app)
                log.info("Media session found: app id %r", app)
        self._raw = raw
        with self._lock:
            self._sessions = [s for s, _ in raw]

    async def _apply(self, what: str, keys: set) -> None:
        for s, ws in self._raw:
            if s.key not in keys:
                continue
            try:
                ok = await (ws.try_pause_async() if what == "pause" else ws.try_play_async())
                log.info("Media: %s %s %r -> %s", what, s.app, s.title, ok)
            except Exception as e:
                log.warning("Media: could not %s %s: %s", what, s.app, e)


class AutoPause:
    """Pause playing browser videos once the rider has stopped for `delay` seconds, and resume
    exactly those when pedaling starts again. Only arms after the rider has pedaled once, so
    cueing up a video before getting on the bike doesn't pause it."""

    def __init__(self) -> None:
        self.paused: set[tuple[str, str]] = set()  # what we paused, to resume
        self._held: set[tuple[str, str]] = set()  # already paused by the rider when we paused
        self._armed = False
        self._stopped_since: Optional[float] = None
        self._acted = False  # paused already during this stop (don't fight a manual play)

    def update(self, now: float, pedaling: bool, sessions: list[Session], enabled: bool, delay: float,
               apps: list[str]) -> tuple[list, list]:
        """Returns (keys to pause, keys to resume)."""
        if not enabled:
            self.paused.clear()
            self._stopped_since, self._acted = None, False
            return [], []
        if pedaling:
            self._armed = True
            self._stopped_since, self._acted = None, False
            if not self.paused:
                return [], []
            # resume only what's still paused: if the rider pressed play (or closed the tab), leave it
            paused = [s for s in sessions if s.status == "paused"]
            resume = [s.key for s in paused if s.key in self.paused]
            # the title can change while paused (YouTube ad ending, autoplay): if one of ours is
            # gone, resume that app's paused sessions, except those the rider had paused already
            gone = {app for app, title in self.paused if (app, title) not in {s.key for s in sessions}}
            resume += [s.key for s in paused
                       if s.app in gone and s.key not in self.paused and s.key not in self._held]
            self.paused.clear()
            return [], resume
        if not self._armed:
            return [], []
        if self._stopped_since is None:
            self._stopped_since = now
        if self._acted or now - self._stopped_since < delay:
            return [], []
        self._acted = True
        pause = [s.key for s in sessions if s.status == "playing" and matches(s, apps)]
        self.paused.update(pause)
        self._held = {s.key for s in sessions if s.status == "paused"}
        return pause, []


class NowPlaying:
    """Spotify's current track, and when it last changed."""

    def __init__(self) -> None:
        self.track: Optional[tuple[str, str]] = None  # (title, artist) while Spotify plays
        self.changed_at = 0.0

    def update(self, now: float, sessions: list[Session]) -> None:
        s = next((s for s in sessions if is_spotify(s) and s.status == "playing" and s.title), None)
        track = (s.title, s.artist) if s else None
        if track != self.track:
            if track is not None:
                self.changed_at = now
            self.track = track

    def text(self, now: float, mode: str, show_s: float = 6.0) -> Optional[str]:
        if self.track is None or mode == "off":
            return None
        if mode != "always" and now - self.changed_at > show_s:
            return None
        title, artist = self.track
        return f"♪ {artist} — {title}" if artist else f"♪ {title}"
