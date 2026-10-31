"""The transparent, always-on-top, click-through HUD window."""

from __future__ import annotations

import sys
from typing import Optional

from PyQt6.QtCore import QPoint, QPointF, QRectF, Qt, QTimer
from PyQt6.QtGui import QColor, QFont, QFontDatabase, QPainter, QPainterPath, QPen, QPolygonF
from PyQt6.QtWidgets import QApplication, QWidget

from .ride import Ride
from .workout import Segment

# Training-zone colours (fraction of FTP upper bounds)
ZONES = [
    (0.60, QColor(128, 128, 128)),  # Z1 recovery - grey
    (0.76, QColor(50, 135, 255)),  # Z2 endurance - blue
    (0.90, QColor(80, 195, 90)),  # Z3 tempo - green
    (1.05, QColor(255, 205, 60)),  # Z4 threshold - yellow
    (1.19, QColor(255, 110, 50)),  # Z5 VO2max - orange
    (99.0, QColor(240, 50, 30)),  # Z6+ anaerobic - red
]
FREE = QColor(110, 110, 120)
PANEL = QColor(12, 14, 20, 175)
LABEL = QColor(170, 175, 185)
WHITE = QColor(255, 255, 255)

BASE_W = 730
BAR_H = 84
GAP = 8
WORKOUT_H = 182
STATUS_H = 26


def zone_color(frac: Optional[float]) -> QColor:
    if frac is None:
        return FREE
    for limit, c in ZONES:
        if frac < limit:
            return c
    return ZONES[-1][1]


def fmt_time(s: float) -> str:
    s = int(round(s))
    h, rem = divmod(s, 3600)
    m, sec = divmod(rem, 60)
    return f"{h}:{m:02d}:{sec:02d}" if h else f"{m}:{sec:02d}"


def _family() -> str:
    fams = set(QFontDatabase.families())
    for f in ("Segoe UI", "Inter", "Roboto", "Cantarell", "DejaVu Sans"):
        if f in fams:
            return f
    return QApplication.font().family()


class Overlay(QWidget):
    def __init__(self, ride: Ride, status_text):
        super().__init__()
        self.ride = ride
        self.settings = ride.settings
        self.status_text = status_text  # callable -> str | None
        self._drag: Optional[QPoint] = None
        self._family = _family()
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)
        self.setWindowTitle("Sporterlay")
        self._apply_flags()
        self._resize()
        self._place()

        # Windows: other topmost windows (or a browser going fullscreen) can end up above us;
        # re-assert topmost every couple of seconds.
        self._topmost = QTimer(self)
        self._topmost.timeout.connect(self._raise_topmost)
        self._topmost.start(2000)

    # ---- window behaviour -----------------------------------------------------
    def _apply_flags(self) -> None:
        flags = (
            Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.WindowStaysOnTopHint
            | Qt.WindowType.Tool
            | Qt.WindowType.WindowDoesNotAcceptFocus
        )
        if self.settings.locked:
            flags |= Qt.WindowType.WindowTransparentForInput
        visible = self.isVisible()
        self.setWindowFlags(flags)
        self.setWindowOpacity(self.settings.opacity)
        if visible:
            self.show()

    def set_locked(self, locked: bool) -> None:
        self.settings.locked = locked
        self.settings.save()
        self._apply_flags()
        self.update()

    def _raise_topmost(self) -> None:
        if not self.isVisible():
            return
        if sys.platform == "win32":
            import ctypes

            HWND_TOPMOST = -1
            SWP_NOSIZE, SWP_NOMOVE, SWP_NOACTIVATE = 0x1, 0x2, 0x10
            ctypes.windll.user32.SetWindowPos(
                int(self.winId()), HWND_TOPMOST, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE
            )
        else:
            self.raise_()

    def _base_height(self) -> int:
        h = BAR_H
        if self.ride.player:
            h += GAP + WORKOUT_H
        h += GAP + STATUS_H  # always reserve, keeps the window from jumping around
        return h

    def _resize(self) -> None:
        s = self.settings.scale
        self.setFixedSize(int(BASE_W * s), int(self._base_height() * s))

    def _place(self) -> None:
        if self.settings.x is not None and self.settings.y is not None:
            self.move(self.settings.x, self.settings.y)
            return
        screen = QApplication.primaryScreen().availableGeometry()
        self.move(screen.x() + (screen.width() - self.width()) // 2, screen.y() + 16)

    def reset_position(self) -> None:
        self.settings.x = self.settings.y = None
        self.settings.save()
        self._place()

    def refresh(self) -> None:
        """Called by the app after each data tick."""
        target = (int(BASE_W * self.settings.scale), int(self._base_height() * self.settings.scale))
        if (self.width(), self.height()) != target:
            self._resize()
        self.update()

    # dragging / resizing when unlocked
    def mousePressEvent(self, e):
        if e.button() == Qt.MouseButton.LeftButton:
            self._drag = e.globalPosition().toPoint() - self.frameGeometry().topLeft()

    def mouseMoveEvent(self, e):
        if self._drag is not None:
            self.move(e.globalPosition().toPoint() - self._drag)

    def mouseReleaseEvent(self, e):
        if self._drag is not None:
            self._drag = None
            self.settings.x, self.settings.y = self.x(), self.y()
            self.settings.save()

    def wheelEvent(self, e):
        step = 0.05 if e.angleDelta().y() > 0 else -0.05
        self.settings.scale = round(min(2.5, max(0.5, self.settings.scale + step)), 2)
        self.settings.save()
        self._resize()
        self.update()

    # ---- painting ---------------------------------------------------------------
    def _font(self, px: float, bold: bool = False) -> QFont:
        f = QFont(self._family)
        f.setPixelSize(max(1, int(px)))
        f.setWeight(QFont.Weight.Bold if bold else QFont.Weight.Medium)
        return f

    def text(self, p: QPainter, rect: QRectF, s: str, px: float, color=WHITE, bold=False,
             align=Qt.AlignmentFlag.AlignCenter) -> None:
        p.setFont(self._font(px, bold))
        p.setPen(QColor(0, 0, 0, 160))
        p.drawText(rect.translated(1, 1.5), int(align), s)  # drop shadow for readability over video
        p.setPen(color)
        p.drawText(rect, int(align), s)

    def value_unit(self, p: QPainter, rect: QRectF, value: str, unit: str, vpx: float,
                   color=WHITE, unit_color=LABEL) -> None:
        """Big number with a small unit right after it, centred together."""
        fv, fu = self._font(vpx, True), self._font(vpx * 0.42, True)
        p.setFont(fv)
        wv = p.fontMetrics().horizontalAdvance(value)
        p.setFont(fu)
        wu = p.fontMetrics().horizontalAdvance(unit) + (3 if unit else 0)
        x0 = rect.center().x() - (wv + wu) / 2
        self.text(p, QRectF(x0, rect.y(), wv, rect.height()), value, vpx, color, True,
                  Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter)
        if unit:
            # baseline-ish alignment: nudge the unit down a little
            ur = QRectF(x0 + wv + 3, rect.y() + vpx * 0.18, wu, rect.height())
            self.text(p, ur, unit, vpx * 0.42, unit_color, True,
                      Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter)

    def panel(self, p: QPainter, rect: QRectF) -> None:
        path = QPainterPath()
        path.addRoundedRect(rect, 12, 12)
        p.fillPath(path, PANEL)

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        p.setRenderHint(QPainter.RenderHint.TextAntialiasing)
        p.scale(self.settings.scale, self.settings.scale)

        y = 0
        self.paint_bar(p, QRectF(0, y, BASE_W, BAR_H))
        y += BAR_H + GAP
        if self.ride.player:
            self.paint_workout(p, QRectF(0, y, BASE_W, WORKOUT_H))
            y += WORKOUT_H + GAP

        status = self.status_text()
        if not self.settings.locked:
            status = "Unlocked: drag to move, scroll to resize, Ctrl+Alt+L to lock"
            pen = QPen(QColor(255, 255, 255, 160), 1.5, Qt.PenStyle.DashLine)
            p.setPen(pen)
            p.drawRoundedRect(QRectF(1, 1, BASE_W - 2, y - GAP - 2), 12, 12)
        if status:
            p.setFont(self._font(13, True))
            w = p.fontMetrics().horizontalAdvance(status) + 28
            r = QRectF((BASE_W - w) / 2, y, w, STATUS_H)
            path = QPainterPath()
            path.addRoundedRect(r, STATUS_H / 2, STATUS_H / 2)
            p.fillPath(path, PANEL)
            self.text(p, r, status, 13, LABEL, True)
        p.end()

    def paint_bar(self, p: QPainter, r: QRectF) -> None:
        self.panel(p, r)
        ride, t = self.ride, self.ride.telemetry
        power = ride.power_display
        dash = "--"

        v = 25  # value size for the small cells
        cells = [  # (weight, label, value, unit, size, colour)
            (1.5, f"POWER{'' if self.settings.power_avg_s <= 1 else f' ({self.settings.power_avg_s}s)'}",
             dash if power is None else str(power), "W", 46, WHITE),
            (0.8, "W/KG", dash if power is None else f"{power / self.settings.weight_kg:.1f}", "", v, WHITE),
            (1.0, "HEART RATE", dash if t.heart_rate is None else str(t.heart_rate), "bpm", v,
             QColor(255, 95, 95) if t.heart_rate else WHITE),
            (0.95, "CADENCE", dash if t.cadence is None else str(t.cadence), "rpm", v, WHITE),
            (1.15, "SPEED", dash if ride.speed_kmh is None else f"{ride.speed_kmh:.1f}", "km/h", v, WHITE),
            (1.05, "DISTANCE", f"{ride.distance_km:.1f}", "km", v, WHITE),
            (1.05, "TIME", fmt_time(ride.ride_time), "", v, WHITE),
            # gears only matter in simulation mode; dimmed while ERG holds the power
            (0.85, "ERG" if ride.erg_active else "GEAR", str(self.settings.gear), "",
             v + 3, LABEL if ride.erg_active else QColor(255, 205, 60)),
        ]
        total = sum(c[0] for c in cells)
        x = r.x() + 8
        inner_w = r.width() - 16
        for i, (wgt, label, val, unit, size, col) in enumerate(cells):
            w = inner_w * wgt / total
            cell = QRectF(x, r.y(), w, r.height())
            vr = QRectF(cell.x(), cell.y() + 8, w, r.height() - 32)
            self.value_unit(p, vr, val, unit, size, col)
            sub = label
            if i == 0 and ride.avg_power is not None:
                sub = f"AVG {ride.avg_power} W"
            self.text(p, QRectF(cell.x(), r.bottom() - 26, w, 18), sub, 11, LABEL, True)
            if i in (1, 3, 6):  # subtle separators between groups
                p.setPen(QPen(QColor(255, 255, 255, 40), 1))
                p.drawLine(QPointF(x + w, r.y() + 16), QPointF(x + w, r.bottom() - 16))
            x += w

    def paint_workout(self, p: QPainter, r: QRectF) -> None:
        self.panel(p, r)
        ride, player = self.ride, self.ride.player
        assert player is not None
        wo = player.workout
        pad = 14
        x0, x1 = r.x() + pad, r.right() - pad

        # ---- header: target / label / time left -----------------------------------
        hy, hh = r.y() + 8, 52
        if player.finished:
            self.text(p, QRectF(x0, hy, x1 - x0, hh), "Workout complete", 26, WHITE, True)
        else:
            idx, seg, into, left = player.current()
            frac = seg.power_at(into)
            col = zone_color(frac)
            tw = ride.target_watts()
            # target pill
            pill = QRectF(x0, hy + 6, 150, hh - 12)
            path = QPainterPath()
            path.addRoundedRect(pill, 10, 10)
            p.fillPath(path, col)
            if tw is None:
                self.text(p, pill, seg.label.upper() or "FREE RIDE", 17, WHITE, True)
            else:
                self.value_unit(p, pill, str(tw), "W", 30, unit_color=WHITE)
            # cadence target + label in the middle
            mid = QRectF(pill.right() + 12, hy, 290, hh)
            name = seg.label or ("Ramp" if seg.is_ramp else f"Interval {idx + 1}")
            extra = []
            if seg.cadence:
                extra.append(f"@ {seg.cadence} rpm")
            if seg.is_ramp and tw is not None:
                extra.append(f"{ride.watts_for(seg.start)} → {ride.watts_for(seg.end)} W")
            if seg.target_range:
                extra.append(f"{ride.watts_for(seg.target_range[0])}–{ride.watts_for(seg.target_range[1])} W")
            if self.settings.intensity != 100:
                extra.append(f"{self.settings.intensity}% intensity")
            if wo.ftp_override:
                extra.append(f"FTP {wo.ftp_override} (workout)")
            msg = seg.text_at(into)
            if msg:  # workout text message takes the headline, Zwift-style
                extra.insert(0, name)
                name = msg
            self.text(p, QRectF(mid.x(), mid.y() + 4, mid.width(), 24), name, 18,
                      QColor(255, 205, 60) if msg else WHITE, True,
                      Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter)
            self.text(p, QRectF(mid.x(), mid.y() + 26, mid.width(), 20),
                      "   ".join(extra) or f"{idx + 1} / {len(wo.segments)}", 13, LABEL, True,
                      Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter)
            # time left in interval
            tr = QRectF(x1 - 130, hy, 130, hh)
            self.text(p, QRectF(tr.x(), tr.y() - 2, tr.width(), 38), fmt_time(left), 34, WHITE, True,
                      Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
            self.text(p, QRectF(tr.x(), tr.y() + 34, tr.width(), 16), "INTERVAL LEFT", 10, LABEL, True,
                      Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)

            # progress bar for the current interval
            by = hy + hh + 6
            bar = QRectF(x0, by, x1 - x0, 7)
            path = QPainterPath()
            path.addRoundedRect(bar, 3.5, 3.5)
            p.fillPath(path, QColor(255, 255, 255, 45))
            done = QRectF(bar.x(), bar.y(), bar.width() * (into / seg.duration if seg.duration else 1), bar.height())
            path = QPainterPath()
            path.addRoundedRect(done, 3.5, 3.5)
            p.fillPath(path, col)

        # ---- whole-workout profile ----------------------------------------------
        gy = r.y() + 82
        graph = QRectF(x0, gy, x1 - x0, 66)
        self.paint_profile(p, graph)

        # ---- footer --------------------------------------------------------------
        fy = graph.bottom() + 6
        nxt = player.next_segment()
        if nxt is not None and not player.finished:
            nt = ride.watts_for(nxt.power_at(0))
            what = f"{nt} W" if nt is not None else (nxt.label or "free ride")
            if nxt.is_ramp:
                what = f"{nt} → {ride.watts_for(nxt.end)} W"
            if nxt.cadence:
                what += f" @ {nxt.cadence} rpm"
            left_txt = f"NEXT  {fmt_time(nxt.duration)}  {what}"
        else:
            left_txt = wo.name
        self.text(p, QRectF(x0, fy, (x1 - x0) * 0.62, 20), left_txt, 13, WHITE, True,
                  Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter)
        state = "PAUSED" if player.paused else ("Start pedaling" if not player.started else "")
        right = f"{state}   " if state else ""
        right += f"{fmt_time(max(wo.duration - player.elapsed, 0))} left"
        self.text(p, QRectF(x0 + (x1 - x0) * 0.4, fy, (x1 - x0) * 0.6, 20), right, 13,
                  QColor(255, 205, 60) if state else LABEL, True,
                  Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)

    def paint_profile(self, p: QPainter, g: QRectF) -> None:
        player = self.ride.player
        px, py = draw_profile(p, g, player.workout)

        # dim the part already done and draw the actual power over it
        xpos = px(player.elapsed)
        p.fillRect(QRectF(g.x(), g.y(), xpos - g.x(), g.height()), QColor(0, 0, 0, 120))
        trace = self.ride.trace
        if len(trace) > 1:
            ftp = self.ride.workout_ftp
            pts = QPolygonF([QPointF(px(ts), py(w / ftp)) for ts, w in trace])
            p.setPen(QPen(QColor(255, 255, 255, 220), 1.6))
            p.drawPolyline(pts)
        # position marker
        p.setPen(QPen(WHITE, 2))
        p.drawLine(QPointF(xpos, g.y() - 3), QPointF(xpos, g.bottom()))
        p.setBrush(WHITE)
        p.drawPolygon(QPolygonF([QPointF(xpos - 5, g.y() - 8), QPointF(xpos + 5, g.y() - 8), QPointF(xpos, g.y() - 2)]))
        p.setBrush(Qt.BrushStyle.NoBrush)


def draw_profile(p: QPainter, g: QRectF, wo):
    """Draw a workout's zone-coloured profile into g; returns the (time→x, FTP fraction→y) mappers."""
    total = wo.duration or 1.0
    top = max(1.3, max((s.peak for s in wo.segments), default=1.0) * 1.08)

    def px(t: float) -> float:
        return g.x() + g.width() * t / total

    def py(frac: float) -> float:
        return g.bottom() - g.height() * min(frac, top) / top

    t = 0.0
    for s in wo.segments:
        _draw_segment(p, s, t, px, py, g)
        t += s.duration

    # FTP reference line
    p.setPen(QPen(QColor(255, 255, 255, 70), 1, Qt.PenStyle.DashLine))
    p.drawLine(QPointF(g.x(), py(1.0)), QPointF(g.right(), py(1.0)))
    return px, py


def _draw_segment(p: QPainter, s: Segment, t0: float, px, py, g: QRectF) -> None:
    x_a, x_b = px(t0), px(t0 + s.duration)
    if s.start is None:
        p.fillRect(QRectF(x_a, py(0.5), max(x_b - x_a - 0.5, 0.5), g.bottom() - py(0.5)), FREE)
        return
    # draw in slices so ramps get a colour gradient through the zones
    slices = max(1, int((x_b - x_a) / 3)) if s.is_ramp else 1
    for k in range(slices):
        fa, fb = k / slices, (k + 1) / slices
        pa, pb = s.start + (s.end - s.start) * fa, s.start + (s.end - s.start) * fb
        xa, xb = x_a + (x_b - x_a) * fa, x_a + (x_b - x_a) * fb
        # thin separator between blocks, only when there's room for it
        gap = 0.5 if k == slices - 1 and x_b - x_a > 1.5 else 0.0
        poly = QPolygonF([QPointF(xa, g.bottom()), QPointF(xa, py(pa)), QPointF(xb - gap, py(pb)),
                          QPointF(xb - gap, g.bottom())])
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(zone_color((pa + pb) / 2))
        p.drawPolygon(poly)
    p.setBrush(Qt.BrushStyle.NoBrush)
