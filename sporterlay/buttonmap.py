"""Corner panel showing what each Zwift Click button does (click-through, always on top)."""

from __future__ import annotations

import time
from typing import Callable, Optional

from PyQt6.QtCore import QPointF, QRectF, Qt, QTimer
from PyQt6.QtGui import QColor, QPainter, QPainterPath, QPolygonF, QScreen
from PyQt6.QtWidgets import QWidget

from .click import LEFT_POD, RIGHT_POD
from .overlay import LABEL, PANEL, WHITE, Overlay, _family, raise_topmost

W = 440
PAD = 12
HEAD_H = 24
COL_H = 20
ROW_H = 28
H = PAD + HEAD_H + COL_H + ROW_H * max(len(LEFT_POD), len(RIGHT_POD)) + PAD
MARGIN = 16  # from the screen corner
BADGE = QColor(255, 255, 255, 38)
ACCENT = QColor(255, 110, 50)
PRESS_S = 1.0  # how long a pressed button's row stays highlighted
# d-pad badges drawn as triangles: corner offsets in units of the arrow size
ARROWS = {
    "▲": [(0, -1), (1.1, 0.75), (-1.1, 0.75)],
    "▼": [(0, 1), (1.1, -0.75), (-1.1, -0.75)],
    "◀": [(-1, 0), (0.75, -1.1), (0.75, 1.1)],
    "▶": [(1, 0), (-0.75, -1.1), (-0.75, 1.1)],
}


class ButtonMap(QWidget):
    """describe(button) -> short text for the action bound to it ("" = nothing bound);
    click_status() -> str shown in the header while the Click isn't connected, else None;
    screen() -> the screen to sit in the bottom-right corner of (the overlay's)."""

    # same drop-shadow text and fonts as the overlay
    text = Overlay.text
    _font = Overlay._font

    def __init__(self, settings, describe: Callable[[str], str], click_status: Callable[[], Optional[str]],
                 screen: Callable[[], QScreen]):
        super().__init__()
        self.settings = settings
        self.describe = describe
        self.click_status = click_status
        self.screen_of = screen
        self._family = _family()
        self._show_until = 0.0
        self.suppressed = False  # the HUD is hidden: never show the map either
        self._highlight: tuple[Optional[str], float] = (None, 0.0)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)
        self.setWindowTitle("Sporterlay buttons")
        self.setWindowFlags(Qt.WindowType.FramelessWindowHint | Qt.WindowType.WindowStaysOnTopHint
                            | Qt.WindowType.Tool | Qt.WindowType.WindowDoesNotAcceptFocus
                            | Qt.WindowType.WindowTransparentForInput)
        self._topmost = QTimer(self)
        self._topmost.timeout.connect(lambda: raise_topmost(self))
        self._topmost.start(2000)

    def flash(self, button: Optional[str] = None, seconds: float = 4.0) -> None:
        """Show the map for a few seconds even if it's toggled off (e.g. after a rebind)."""
        self._show_until = time.monotonic() + seconds
        if button:
            self._highlight = (button, self._show_until)
        self.refresh()

    def pressed(self, button: str) -> None:
        self._highlight = (button, time.monotonic() + PRESS_S)
        self.update()

    def refresh(self) -> None:
        """Called by the app after each data tick."""
        want = (self.settings.show_button_map or time.monotonic() < self._show_until) and not self.suppressed
        if want:
            s = self.settings.scale
            self.setFixedSize(int(W * s), int(H * s))
            g = self.screen_of().availableGeometry()
            self.move(g.x() + g.width() - self.width() - MARGIN, g.y() + g.height() - self.height() - MARGIN)
            self.setWindowOpacity(self.settings.opacity)
            if not self.isVisible():
                self.show()
            self.update()
        elif self.isVisible():
            self.hide()

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        p.setRenderHint(QPainter.RenderHint.TextAntialiasing)
        p.scale(self.settings.scale, self.settings.scale)
        path = QPainterPath()
        path.addRoundedRect(QRectF(0, 0, W, H), 12, 12)
        p.fillPath(path, PANEL)

        left = Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter
        right = Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter
        self.text(p, QRectF(PAD, PAD, W - 2 * PAD, HEAD_H), "ZWIFT CLICK", 12, LABEL, True, left)
        status = self.click_status()
        if status:
            self.text(p, QRectF(PAD, PAD, W - 2 * PAD, HEAD_H), status, 12, LABEL, False, right)

        lit, until = self._highlight
        lit = lit if time.monotonic() < until else None
        col_w = (W - 3 * PAD) / 2
        for i, (title, pod) in enumerate((("LEFT", LEFT_POD), ("RIGHT", RIGHT_POD))):
            x = PAD + i * (col_w + PAD)
            y = PAD + HEAD_H
            self.text(p, QRectF(x, y, col_w, COL_H), title, 11, LABEL, True, left)
            y += COL_H
            for name, badge, _ in pod:
                row = QRectF(x, y, col_w, ROW_H)
                if name == lit:
                    hl = QPainterPath()
                    hl.addRoundedRect(row.adjusted(-4, 1, 0, -1), 8, 8)
                    p.fillPath(hl, QColor(ACCENT.red(), ACCENT.green(), ACCENT.blue(), 70))
                d = ROW_H - 6
                circle = QRectF(x, y + 3, d, d)
                p.setPen(Qt.PenStyle.NoPen)
                p.setBrush(ACCENT if name == lit else BADGE)
                p.drawEllipse(circle)
                if badge in ARROWS:  # fonts draw ◀▶ smaller than ▲▼, so draw all four
                    c, r = circle.center(), d * 0.22
                    p.setBrush(WHITE)
                    p.drawPolygon(QPolygonF([c + QPointF(dx, dy) * r for dx, dy in ARROWS[badge]]))
                else:
                    self.text(p, circle, badge, 12 if badge.isalpha() else 18, WHITE, True)
                action = self.describe(name)
                self.text(p, QRectF(x + d + 8, y, col_w - d - 8, ROW_H), action or "—", 14,
                          WHITE if action else LABEL, bool(action), left)
                y += ROW_H
        p.end()
