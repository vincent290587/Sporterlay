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
- **`workoutdb.py`** + **`library.py`**: the ai_advise workout database (`ai_advise/proto/Workout.proto`): `workouts.json` (protobuf JSON, zero fields omitted, carries ai_advise's `TSS` and `labels`) or `workoutDB.bin` (decoded with a hand-written wire-format reader, no protobuf dependency). Use `blocks` × `repeats` when present, otherwise the deprecated flat `reps`, which is all the current file uses. When stored TSS exists, IF is derived from it. Otherwise it's computed from a 4th-power mean of targets, which overstates sprint workouts. `library.py` is the picker dialog and reuses `overlay.draw_profile`. Workout names aren't unique, so `lib:<name>` restore picks the first match.
- **`click.py`**: `ClickController` runs its own asyncio loop in a thread. It keeps a session to **every** pod that's awake. The Click v2 hardware was verified: the left pod has a d-pad plus shift_down, and the right pod has a/b/y/z plus shift_up. The left pod's connection carries both pods' buttons, while the right pod's carries only its own, so frames from the right connection are ignored while the left is connected (otherwise presses double). Scanning runs in ~2 s windows, and connection setup holds `_connect_lock`. BlueZ connects take ~7–10 s and time out if a scan is running at the same time. `close()` must be called so the pods get disconnected, because BlueZ keeps connections from a dead process, and a connected pod stops advertising. On Linux, known pods (`settings.click_pods`) are released with `bluetoothctl disconnect` at startup. Shifts and other buttons reach the Qt thread through `Signals`. The other buttons map to App methods through `CLICK_ACTIONS` in `app.py`. Actions confirm themselves with `App.flash()`, a ~2 s message in the overlay status line, which hotkeys use too. Protocol notes are in the module docstring.
- **`shifting.py`**: virtual gears on a plain FE-C trainer. Sim-mode grade is solved in closed form, so the trainer's resistance at its real speed equals flat-road resistance at the virtual speed. `CRR` and `WIND_K` must match what `sources.py` sends in FE-C pages 51/50 (and rider/bike mass in page 55). FE-C air drag is `0.5 * coeff * v²`.
- **`ride.py`**: no Qt. Holds power smoothing, moving time, distance and energy, the `WorkoutPlayer`, and the workout power trace. ERG has a soft start. `erg_wanted` means the workout calls for ERG. `erg_active` means wanted *and* `erg_engaged`, which is set by `_update_erg_engagement()` from the `erg_engage_rpm/s` and `erg_release_rpm/s` settings, so the rider never starts from standstill against the full target. `erg_target()` ramps from current power to the target over `erg_ramp_s`. While ERG is wanted, the workout clock advances only once `erg_at_target` (ramp finished); see `clock_held`. Engage/release rpm drop for steps with a low cadence target (`erg_thresholds()`). `_control_trainer()` runs every tick: ERG target when `erg_active`, otherwise the sim grade for the current gear (throttled to every 0.5 s, and applied immediately on a shift). Re-sending is safe because the source deduplicates. Speed and distance shown are virtual (gear-adjusted) outside ERG. `workout_ftp` honors a `.zwo` `<ftpOverride>`.
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
- When testing the Click from a script, always `close()` the controller, or run `bluetoothctl disconnect <addr>` afterwards. Don't `pkill -f <script>` from a shell whose own command line contains that name, because it kills itself.
- Real-hardware ERG/FE-C behavior has not been verified yet. Treat trainer-control changes as untested until someone tries them on a trainer.
