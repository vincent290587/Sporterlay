"""Workout library window: browse the ai_advise workout database and pick one to ride."""

from __future__ import annotations

from typing import Callable, Optional

from PyQt6.QtCore import QRectF, Qt
from PyQt6.QtGui import QColor, QPainter
from PyQt6.QtWidgets import (QAbstractItemView, QComboBox, QDialog, QDialogButtonBox, QHBoxLayout, QHeaderView,
                             QLabel, QLineEdit, QTableWidget, QTableWidgetItem, QVBoxLayout, QWidget)

from .overlay import draw_profile, fmt_time
from .workoutdb import ZONE_NAMES, LibraryWorkout

LENGTHS = [("Any length", 0, 1e9), ("Up to 45 min", 0, 45), ("45–75 min", 45, 75),
           ("75–105 min", 75, 105), ("Over 105 min", 105, 1e9)]


class _NumItem(QTableWidgetItem):
    """Sorts by a number while showing formatted text."""

    def __init__(self, text: str, value: float):
        super().__init__(text)
        self.value = value
        self.setTextAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)

    def __lt__(self, other):
        return self.value < getattr(other, "value", 0)


class _Preview(QWidget):
    def __init__(self):
        super().__init__()
        self.workout = None
        self.setMinimumHeight(110)

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        p.fillRect(self.rect(), QColor(18, 20, 28))
        if self.workout:
            draw_profile(p, QRectF(8, 8, self.width() - 16, self.height() - 16), self.workout)
        p.end()


class LibraryDialog(QDialog):
    def __init__(self, workouts: list[LibraryWorkout], ftp_watts: Callable[[float], int],
                 source_name: str, parent=None):
        super().__init__(parent)
        self.setWindowTitle(f"Workout library · {source_name}")
        self.resize(820, 620)
        self.workouts = workouts
        self.watts = ftp_watts
        self.chosen: Optional[LibraryWorkout] = None

        self.search = QLineEdit(placeholderText="Search by name…")
        self.zone = QComboBox()
        self.zone.addItem("All zones", None)
        for code, name in ZONE_NAMES.items():
            n = sum(1 for w in workouts if name in w.labels)
            if n:
                self.zone.addItem(f"{name} ({n})", name)
        self.length = QComboBox()
        for label, lo, hi in LENGTHS:
            self.length.addItem(label, (lo, hi))
        top = QHBoxLayout()
        top.addWidget(self.search, 1)
        top.addWidget(self.zone)
        top.addWidget(self.length)

        self.table = QTableWidget(0, 5)
        self.table.setHorizontalHeaderLabels(["Workout", "Time", "TSS", "IF", "Zones"])
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.table.verticalHeader().setVisible(False)
        h = self.table.horizontalHeader()
        h.setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        for c in range(1, 5):
            h.setSectionResizeMode(c, QHeaderView.ResizeMode.ResizeToContents)
        self.table.setSortingEnabled(True)

        self.preview = _Preview()
        self.info = QLabel()
        self.info.setWordWrap(True)
        self.info.setTextFormat(Qt.TextFormat.PlainText)

        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        buttons.button(QDialogButtonBox.StandardButton.Ok).setText("Ride this workout")
        buttons.accepted.connect(self._accept)
        buttons.rejected.connect(self.reject)
        self.ok = buttons.button(QDialogButtonBox.StandardButton.Ok)

        lay = QVBoxLayout(self)
        lay.addLayout(top)
        lay.addWidget(self.table, 1)
        lay.addWidget(self.preview)
        lay.addWidget(self.info)
        lay.addWidget(buttons)

        self.search.textChanged.connect(self._fill)
        self.zone.currentIndexChanged.connect(self._fill)
        self.length.currentIndexChanged.connect(self._fill)
        self.table.itemSelectionChanged.connect(self._selected)
        self.table.itemDoubleClicked.connect(lambda _: self._accept())
        self._fill()
        self.table.sortItems(0)
        self.search.setFocus()

    def _visible(self) -> list[int]:
        q = self.search.text().strip().lower()
        zone = self.zone.currentData()
        lo, hi = self.length.currentData()
        out = []
        for i, w in enumerate(self.workouts):
            mins = w.duration / 60
            if q and q not in w.name.lower():
                continue
            if zone and zone not in w.labels:
                continue
            if not lo <= mins < hi:
                continue
            out.append(i)
        return out

    def _fill(self, *_):
        self.table.setSortingEnabled(False)
        rows = self._visible()
        self.table.setRowCount(len(rows))
        for r, i in enumerate(rows):
            w = self.workouts[i]
            name = QTableWidgetItem(w.name)
            name.setData(Qt.ItemDataRole.UserRole, i)
            self.table.setItem(r, 0, name)
            self.table.setItem(r, 1, _NumItem(fmt_time(w.duration), w.duration))
            self.table.setItem(r, 2, _NumItem(str(w.tss), w.tss))
            self.table.setItem(r, 3, _NumItem(f"{w.intensity_factor:.2f}", w.intensity_factor))
            self.table.setItem(r, 4, QTableWidgetItem(", ".join(l.split()[0] for l in w.labels)))
        self.table.setSortingEnabled(True)
        if rows:
            self.table.selectRow(0)
        self._selected()

    def _current(self) -> Optional[LibraryWorkout]:
        items = self.table.selectedItems()
        if not items:
            return None
        i = self.table.item(items[0].row(), 0).data(Qt.ItemDataRole.UserRole)
        return self.workouts[i]

    def _selected(self):
        w = self._current()
        self.ok.setEnabled(w is not None)
        self.preview.workout = w.workout if w else None
        self.preview.update()
        if not w:
            self.info.setText("No workout matches.")
            return
        segs = w.workout.segments
        peak = max((s.peak for s in segs), default=0)
        cad = sorted({s.cadence for s in segs if s.cadence})
        bits = [f"{fmt_time(w.duration)}", f"TSS {w.tss}", f"IF {w.intensity_factor:.2f}",
                f"peak {self.watts(peak)} W"]
        if cad:
            bits.append("cadence targets " + ", ".join(map(str, cad[:6])) + (" …" if len(cad) > 6 else "") + " rpm")
        if w.labels:
            bits.append(", ".join(w.labels))
        text = "   ·   ".join(bits)
        if w.workout.description:
            text += "\n" + w.workout.description[:400]
        self.info.setText(text)

    def _accept(self):
        self.chosen = self._current()
        if self.chosen:
            self.accept()
