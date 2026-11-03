"""Workout text messages in their own click-through window just below the HUD, word-wrapped,
so long ones aren't cut off like they were in the workout panel's headline."""

from __future__ import annotations

from typing import Optional

from PyQt6.QtCore import QRect, QRectF, Qt, QTimer
from PyQt6.QtGui import QColor, QFontMetrics, QPainter, QPainterPath
from PyQt6.QtWidgets import QWidget

from .overlay import BASE_W, GAP, PANEL, WHITE, Overlay, _family, raise_topmost

PAD = 14
ACCENT_W = 5  # amber stripe on the left
BAR_H = 3  # time left for the message, along the bottom
MAX_LINES = 4
SIZES = (20, 17, 15)  # font px, tried in turn until the text fits in MAX_LINES
AMBER = QColor(255, 205, 60)
WRAP = int(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter) | int(Qt.TextFlag.TextWordWrap)


class MessageBox(QWidget):
    # same drop-shadow text and fonts as the overlay
    text = Overlay.text
    _font = Overlay._font

    def __init__(self, ride, overlay: Overlay):
        super().__init__()
        self.ride = ride
        self.settings = ride.settings
        self.overlay = overlay
        self._family = _family()
        self._msg: Optional[tuple[str, float, float]] = None
        self._layout: tuple[str, int, float] = ("", SIZES[0], 0.0)  # text drawn, font px, its height
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)
        self.setWindowTitle("Sporterlay message")
        self.setWindowFlags(Qt.WindowType.FramelessWindowHint | Qt.WindowType.WindowStaysOnTopHint
                            | Qt.WindowType.Tool | Qt.WindowType.WindowDoesNotAcceptFocus
                            | Qt.WindowType.WindowTransparentForInput)
        self._topmost = QTimer(self)
        self._topmost.timeout.connect(lambda: raise_topmost(self))
        self._topmost.start(2000)

    def current(self) -> Optional[tuple[str, float, float]]:
        player = self.ride.player
        if player is None or player.finished or not self.overlay.isVisible() or self.overlay.card():
            return None
        _, seg, into, _ = player.current()
        return seg.message_at(into)

    def _fit(self, msg: str) -> tuple[str, int, float]:
        """Largest font that fits MAX_LINES; past the smallest one, cut at a word with "…"."""
        width = BASE_W - 2 * PAD - ACCENT_W
        for px in SIZES:
            fm = QFontMetrics(self._font(px, True))

            def height(s: str) -> int:
                return fm.boundingRect(QRect(0, 0, width, 10000), WRAP, s).height()

            room = fm.lineSpacing() * MAX_LINES
            if height(msg) <= room:
                return msg, px, height(msg)
        words = msg.split()
        lo, hi = 0, len(words)  # most words that still fit with the ellipsis
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if height(" ".join(words[:mid]) + " …") <= room:
                lo = mid
            else:
                hi = mid - 1
        cut = " ".join(words[:lo]) + " …"
        return cut, SIZES[-1], height(cut)

    def refresh(self) -> None:
        """Called by the app after each data tick."""
        msg = self.current()
        if msg is None:
            self._msg = None
            if self.isVisible():
                self.hide()
            return
        if self._msg is None or self._msg[0] != msg[0]:
            self._layout = self._fit(msg[0])
        self._msg = msg
        s = self.settings.scale
        w, h = int(BASE_W * s), int((2 * PAD + self._layout[2] + BAR_H) * s)
        if (self.width(), self.height()) != (w, h):
            self.setFixedSize(w, h)
        og = self.overlay.frameGeometry()
        screen = self.overlay.screen().availableGeometry()
        y = og.y() + og.height() + int(GAP * s)
        if y + h > screen.y() + screen.height():  # HUD near the bottom: go above it instead
            y = og.y() - int(GAP * s) - h
        self.move(og.x(), y)
        self.setWindowOpacity(self.settings.opacity)
        if not self.isVisible():
            self.show()
        self.update()

    def paintEvent(self, _):
        if self._msg is None:
            return
        _, shown, dur = self._msg
        msg, px, th = self._layout
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        p.setRenderHint(QPainter.RenderHint.TextAntialiasing)
        p.scale(self.settings.scale, self.settings.scale)
        h = 2 * PAD + th + BAR_H
        r = QRectF(0, 0, BASE_W, h)
        path = QPainterPath()
        path.addRoundedRect(r, 12, 12)
        p.fillPath(path, PANEL)
        p.save()
        p.setClipPath(path)
        p.fillRect(QRectF(0, 0, ACCENT_W, h), AMBER)
        left = 1.0 - min(1.0, shown / dur) if dur > 0 else 0.0
        p.fillRect(QRectF(ACCENT_W, h - BAR_H, (BASE_W - ACCENT_W) * left, BAR_H), QColor(255, 205, 60, 150))
        p.restore()
        self.text(p, QRectF(ACCENT_W + PAD, PAD, BASE_W - 2 * PAD - ACCENT_W, th), msg, px, WHITE, True, WRAP)
        p.end()
