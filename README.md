# Sporterlay

A transparent, always-on-top HUD for indoor cycling that you can put over YouTube (or anything else).
It reads your smart trainer and heart-rate strap over **ANT+**, shows live data in a Zwift-style layout,
runs your planned **intervals.icu** workouts with **ERG mode**, and turns a **Zwift Click** into
virtual gears when you're not following a workout.

- Top bar: power (3 s avg by default) + ride average, W/kg, heart rate, cadence, speed, distance, moving time
- Workout panel: target watts in its zone colour, cadence target, time left in the interval, interval progress,
  the whole workout profile with your actual power drawn over it, and what's next
- Click-through: the overlay never steals clicks from the video
- Workout clock only runs while you pedal; ERG is released when the workout is paused, done, or in a free-ride step
- ERG soft start: ERG only engages once you've spun at ≥ 60 rpm for 3 s (until then the trainer rides like a flat
  road in your current gear), ramps from your power to the target over 5 s, and lets go again if cadence stays
  under 40 rpm for 2 s, so starting or restarting never means grinding against the full target
- Virtual shifting (24 gears) whenever ERG isn't holding the power: Zwift Click or Ctrl+Alt+←/→

## Windows setup

### 1. Get the app
**Option A – run from source** (easiest to update): install Python 3.10+ from python.org,
copy this folder to the PC and double-click `run.bat` (first run installs dependencies).
`run_demo.bat` starts it with a simulated trainer so you can check the overlay without a dongle.

**Option B – single .exe**: double-click `build_exe.bat` on the PC → `dist\Sporterlay.exe`.
If the project is on GitHub, the *Build Windows exe* action builds it on every push to `main`
(download it from the run's *Artifacts*).

### 2. Dongle driver (once)
Sporterlay talks to the ANT+ stick through libusb, which needs the stick bound to **WinUSB**.
If the status line says *"needs the WinUSB driver"* or *"No ANT+ dongle found"* while it is plugged in:

1. Download [Zadig](https://zadig.akeo.ie/) and run it.
2. *Options → List All Devices*, pick **ANT USB-m Stick** (or ANTUSB2).
3. Target driver **WinUSB** → *Replace Driver*.

To undo it later: Device Manager → the stick → *Update driver / Roll back*.

Only one program can use the stick at a time: **close Zwift, TrainerRoad, Garmin Express** etc. before starting Sporterlay.

### 3. intervals.icu (once)
Tray icon (orange **S**) → **intervals.icu → Set API key…**. The key is at intervals.icu → Settings →
*Developer settings* (either the raw key or the base64 `API_KEY:<key>` token works).
FTP and weight are then taken from intervals.icu, and today's planned ride is loaded automatically at startup.
Planned rides for the next 7 days are listed in the same menu (*Refresh* after editing your calendar).
Workouts with a fixed FTP (`ftpOverride` in the export) use that FTP, as in Zwift.

### 4. Zwift Click v2 (once)
- The PC needs Bluetooth LE.
- The Click must have been **paired with the official Zwift app at least once**, otherwise it stays locked
  (the status line says so). Close Zwift / other apps so they don't hold the connection.
- Press a button on each pod to wake it. Sporterlay connects to every pod that's awake (about 10 s each).
  The left pod's connection carries both pods' buttons, so while it's connected the right one is ignored
  (no double shifts). With only the right pod awake you get its buttons only: press the left pod once.
- Buttons (each action is confirmed briefly in the overlay's status line):

  | Left pod | Action | Right pod | Action |
  |---|---|---|---|
  | Paddle | Shift easier | Paddle | Shift harder |
  | ↑ / ↓ | Jump 4 gears harder / easier | A | Pause / resume workout |
  | ← | Restart interval (twice quickly: previous) | B | Next interval |
  | → | ERG on / off | Y / Z | Intensity +5 % / −5 % |

  The mapping is `CLICK_ACTIONS` in `sporterlay/app.py`.

### 5. Ride
1. Wake the trainer (pedal a few strokes) and put the HR strap on. It pairs with the first trainer/strap it hears.
2. Load a workout (intervals.icu menu, or *Local workout files*) — or none, to just ride and shift.
3. Start the YouTube video. The workout starts when you start pedaling.

Browser fullscreen (`F` on YouTube) is a borderless window on Windows, and the overlay re-asserts
"on top" every 2 s, so it should stay visible over it. If it ever doesn't, use theater mode (`T`) in a maximised window.

## Hotkeys (work while YouTube has focus)

| Keys | Action |
|---|---|
| Ctrl+Alt+P | Pause / resume workout |
| Ctrl+Alt+N | Next interval |
| Ctrl+Alt+B | Restart interval (press twice quickly: previous) |
| Ctrl+Alt+E | ERG on/off |
| Ctrl+Alt+↑ / ↓ | Workout intensity ±5 % |
| Ctrl+Alt+→ / ← | Shift harder / easier (same as the Click) |
| Ctrl+Alt+L | Unlock to move (drag) / resize (scroll wheel), press again to lock |
| Ctrl+Alt+H | Hide / show overlay |

Clicking the tray icon also hides/shows the overlay.

## Virtual shifting
Outside ERG the trainer runs in simulation mode, and Sporterlay sets the slope from your speed and the
virtual gear so it feels like changing gear on a flat road (one gear ≈ 7 %, roughly +1 % slope at 30 km/h).
The SPEED shown is the virtual speed in that gear. Set `real_chainring` / `real_cog` in the settings file to
the gear your bike is actually in on the trainer (default 50×17); the starting gear matches it.
Rider + bike weight are sent to the trainer so its physics match.

## Workout library (ai_advise database)
Tray → **Workout library…** opens a browser for your ai_advise workout database: search by name, filter by
zone and length, sort by time/TSS/IF, and preview the profile before riding it. Put `workouts.json`
(preferred, since it includes ai_advise's TSS and zone labels) or `workoutDB.bin` in `%APPDATA%\Sporterlay`, or
point to it with *Local workout files → Choose workout library file…*. The file is re-read when it changes.

## Local workouts
Any Zwift-format `.zwo` file works (SteadyState, Warmup, Cooldown, Ramp, IntervalsT, FreeRide, MaxEffort).
Drop files into the user workouts folder (tray → *Workouts → Open workouts folder*, i.e.
`%APPDATA%\Sporterlay\workouts`) and they show up in the menu.
Good sources: intervals.icu, TrainerDay and whatsonzwift.com all export `.zwo`.

## Credits
Zwift Click protocol details come from community reverse-engineering:
[zwift-click-bridge](https://github.com/michalbychawski/zwift-click-bridge),
[zwift_click_handling](https://github.com/jat255/zwift_click_handling) and
[ajchellew/zwiftplay](https://github.com/ajchellew/zwiftplay).

## Settings & logs
`%APPDATA%\Sporterlay\settings.json` (FTP, weight, position, scale, smoothing, device IDs, …) and
`sporterlay.log` next to it. Set `fe_device_id` / `hr_device_id` to pin a specific trainer or strap
if a neighbour's device gets picked up (the IDs are in the log).

## Running on Linux (for development)
```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python -m sporterlay --demo --workout workouts/VO2max_5x3.zwo
```
For a real dongle, allow access to the stick:
```bash
echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="0fcf", MODE="0666"' | sudo tee /etc/udev/rules.d/99-ant-usb.rules
sudo udevadm control --reload && sudo udevadm trigger
```
On GNOME Wayland run with `QT_QPA_PLATFORM=xcb` so always-on-top/click-through work (fullscreen video will still cover it).
