# Sporterlay

A transparent, always-on-top HUD for indoor cycling that you can put over YouTube (or anything else).
It reads your smart trainer and heart-rate strap over **ANT+**, shows live data in a Zwift-style layout,
and runs structured workouts (`.zwo` files) with **ERG mode** controlling the trainer's resistance.

- Top bar: power (3 s avg by default) + ride average, W/kg, heart rate, cadence, speed, distance, moving time
- Workout panel: target watts in its zone colour, cadence target, time left in the interval, interval progress,
  the whole workout profile with your actual power drawn over it, and what's next
- Click-through: the overlay never steals clicks from the video
- Workout clock only runs while you pedal; ERG is released (flat-road sim) when the workout is paused or done

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

### 3. Ride
1. Wake the trainer (pedal a few strokes) and put the HR strap on. It pairs with the first trainer/strap it hears.
2. Right-click the tray icon (orange **S**) → set **FTP** and **weight**.
3. **Workouts** → pick one (or *Load workout file…*).
4. Start the YouTube video. The workout starts when you start pedaling.

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
| Ctrl+Alt+L | Unlock to move (drag) / resize (scroll wheel), press again to lock |
| Ctrl+Alt+H | Hide / show overlay |

Clicking the tray icon also hides/shows the overlay.

## Workouts
Any Zwift-format `.zwo` file works (SteadyState, Warmup, Cooldown, Ramp, IntervalsT, FreeRide, MaxEffort).
Drop files into the user workouts folder (tray → *Workouts → Open workouts folder*, i.e.
`%APPDATA%\Sporterlay\workouts`) and they show up in the menu.
Good sources: intervals.icu, TrainerDay and whatsonzwift.com all export `.zwo`.

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
