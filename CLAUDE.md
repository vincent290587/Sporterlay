# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Sporterlay is a PyQt6 transparent, always-on-top, click-through HUD that reads an ANT+ smart trainer (FE-C) and HR strap via `openant`, shows Zwift-style ride data, runs intervals.icu planned workouts (fetched as `.zwo`) with ERG control, and uses a Zwift Click v2 (BLE via `bleak`) for virtual shifting outside ERG. **The target platform is Windows** (a separate PC). Development happens on Linux (GNOME Wayland), where always-on-top over fullscreen windows can't work, so verify UI changes with demo mode and offscreen renders rather than by watching the live window.

## Commands

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python -m sporterlay --demo --workout workouts/VO2max_5x3.zwo   # simulated trainer
.venv/bin/python -m sporterlay -v                                          # real ANT+ dongle, debug logging
QT_QPA_PLATFORM=xcb .venv/bin/python -m sporterlay --demo                  # on Wayland: makes on-top/click-through work
```

There is no test suite or linter configured. Checks that have been used:
- `python -m py_compile sporterlay/*.py`
- Exercise `WorkoutPlayer` / `Ride` directly in a script (they have no Qt dependency).
- Render the overlay to PNG headlessly: build `Ride(Settings(), DemoSource())`, call `ride.tick(0.25)` in a loop, then `Overlay(ride, lambda: "status").grab().save(path)` under `QT_QPA_PLATFORM=offscreen`. Set `XDG_CONFIG_HOME` to a temp dir so the real settings aren't overwritten.

Windows: `run.bat` / `run_demo.bat` run from source. `build_exe.bat` and `.github/workflows/build-windows.yml` build a single exe with PyInstaller from `launcher.py`. The flags `--collect-all libusb_package --collect-submodules openant --collect-submodules usb --add-data "workouts;workouts"` are required. Keep the two build definitions in sync.

## Architecture

The data flow is a single 4 Hz poll loop on the Qt thread (`App.tick` in `app.py`):
`source.snapshot()` → `Ride.tick(dt)` → `Overlay.refresh()` (repaint).

- **`sources.py`**: `AntSource` and `DemoSource` share a duck-typed interface: `snapshot() -> Telemetry`, `set_target_power(w)`, `set_free_ride(grade)`, `status`, `close()`.
  - `AntSource` runs openant's blocking `Node.start()` on a background thread. If that fails (no dongle, permission error), it retries every 3 s and maps the exception to a user-facing `status` string.
  - openant callbacks write `(value, timestamp)` pairs under a lock. `snapshot()` returns `None` for any value older than `STALE_S`, which is how "--" and "not pedaling" are detected.
  - Trainer commands are deduplicated (`_last_cmd`) and sent from a dedicated sender thread that only keeps the latest command, because acknowledged ANT sends can block.
  - ERG uses openant's `set_target_power` (FE-C page 49). Free ride sends FE-C page 51 (track resistance / grade) by hand.
  - `_prepare_libusb()` adds the bundled `libusb-package` DLL to the search path on Windows. openant calls `usb.core.find` without a backend argument, so the DLL has to be findable.
- **`intervals.py`**: urllib client, called from a worker thread; results come back to Qt through the `Signals` QObject in `app.py`. Uses `GET /api/v1/athlete/{id}/events?category=WORKOUT&ext=zwo` (each event gets `workout_file_base64`) and `GET /api/v1/athlete/{id}` (FTP from `sportSettings`, weight from `icu_weight`). Auth is basic `API_KEY:<key>`, and the client also accepts an already-base64 token. The OpenAPI spec is at `https://intervals.icu/api/v1/docs`.
- **`click.py`**: `ClickController` runs its own asyncio loop in a thread and reconnects forever. The protocol notes (UUIDs, v2 activation writes plus the 3 s `RideOn` keep-alive, bitmask with cleared bit = pressed) are in the module docstring. It connects to only one v2 pod, because the other pod's presses arrive on the same connection. Shifts reach the Qt thread through `Signals.shift`.
- **`shifting.py`**: virtual gears on a plain FE-C trainer. Sim-mode grade is solved in closed form, so the trainer's resistance at its real speed equals flat-road resistance at the virtual speed. `CRR` and `WIND_K` must match what `sources.py` sends in FE-C pages 51/50 (and rider/bike mass in page 55). FE-C air drag is `0.5 * coeff * v²`.
- **`ride.py`**: no Qt. Holds power smoothing, moving time, distance and energy, the `WorkoutPlayer`, and the workout power trace. `_control_trainer()` runs every tick: ERG target when `erg_active`, otherwise the sim grade for the current gear (throttled to every 0.5 s, and applied immediately on a shift). Re-sending is safe because the source deduplicates. Speed and distance shown are virtual (gear-adjusted) outside ERG. `workout_ftp` honors a `.zwo` `<ftpOverride>`.
- **`workout.py`**: `.zwo` parser into `Segment`s, with power as a fraction of FTP and `None` meaning no target (FreeRide/MaxEffort). `IntervalsT` is expanded into on/off segments. Ranges (PowerLow/PowerHigh on SteadyState) aim for the midpoint and keep `target_range`. `textevent` messages are attached to the segment they fall in. Warmup and Cooldown endpoints are sorted, because real-world files are inconsistent about PowerLow/PowerHigh. `WorkoutPlayer` time only advances while pedaling and not paused.
- **`overlay.py`**: one frameless widget painted entirely with `QPainter`, using a fixed base layout (`BASE_W` etc.) scaled by `settings.scale`.
  - `WindowTransparentForInput` = locked/click-through. Toggling it requires re-applying window flags and calling `show()` again.
  - On Windows, a timer re-asserts `HWND_TOPMOST` via ctypes every 2 s so the overlay stays above browser fullscreen.
- **`app.py`**: tray menu (rebuilt on every `aboutToShow`), Windows-only global hotkeys (Ctrl+Alt+P/N/B/E/L/H/↑/↓), wiring.
  - Hotkeys are registered with `RegisterHotKey(None, …)` as thread messages and caught in a `QAbstractNativeEventFilter`. Don't bind them to the overlay's HWND, because changing window flags recreates that window.
- **`settings.py`**: dataclass persisted as JSON in `%APPDATA%\Sporterlay` (Linux: `~/.config/sporterlay`). The log file `sporterlay.log` is written there too. User `.zwo` files go in its `workouts/` subfolder; bundled ones are in `./workouts` (in the exe they're under `sys._MEIPASS`).

## Gotchas

- Windowed exe and `pythonw` have `sys.stderr is None`, so don't log to or print to stderr unconditionally.
- On Windows the ANT stick must use the WinUSB driver (Zadig), and only one app can hold it at a time (Zwift, Garmin Express). On Linux it needs a udev rule (see README). The dev machine's stick is an ANTUSB-m (`0fcf:1009`).
- `DemoSource` simulates sim-mode physics (speed from cadence, power from grade), so shifting can be tested with `--demo`. Don't derive demo speed from power, because that creates a feedback loop with the gear grade.
- The Click v2 must have been paired with the official Zwift app once, or it answers the handshake with `0xFF` (locked).
- Real-hardware ERG/FE-C behavior has not been verified yet. Treat trainer-control changes as untested until someone tries them on a trainer.
