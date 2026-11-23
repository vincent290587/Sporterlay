# Sporterlay World (Unreal Engine 5 experiment)

A first-person ride through an Unreal level. Sporterlay only **sends power**. The world
works out speed with its own physics: gravity on the road's grade, rolling resistance, air
drag and inertia. Nothing goes back to the trainer, so ERG, gears and Sporterlay's own
speed and distance don't change. Climbs slow you down on screen, but the trainer won't get
harder.

```
Sporterlay ──UDP 127.0.0.1:47810, 4 Hz──▶ USporterlayLink ──▶ ARiderPawn ──▶ follows ARideRoute
            {"v":1,"power":245}             (latest W,          (physics,        (spline + road,
                                             0 W after 2 s)      camera)          grade from it)
```

## Setup

1. Install Unreal Engine 5.6 or newer (Epic Games Launcher on Windows). Installing the
   editor also installs the C++ toolchain (Visual Studio 2022 with "Game development with
   C++").
2. Right-click `SporterlayWorld.uproject` → *Generate Visual Studio project files*, then
   open the `.uproject` and let it build the module. If your engine isn't 5.6, change
   `EngineAssociation` or pick it in *Switch Unreal Engine version*.
3. Make a level: *File → New Level → Open World* (or *Basic*). Sculpt a Landscape, or
   download one from Fab (*Window → Fab*, Quixel Megascans are free) and dress it with
   Megascans foliage and rocks. Lumen, virtual shadow maps and TSR are already enabled in
   `Config/DefaultEngine.ini`.
4. Drag a **RideRoute** into the level (Place Actors, search for "RideRoute"). Then either
   - edit its spline points in the viewport (Alt-drag a point to add one), then click
     **Snap To Ground**, or
   - set **GPX File** and click **Import GPX**. Turn off *Use GPX Elevation* to put the
     track on your landscape instead of on its real elevation profile.
   A track that ends where it starts becomes a loop. The road surface is the engine cube
   stretched along the spline. Set **Road Mesh / Road Material** to a road kit from Fab,
   or clear Road Mesh if the landscape already has a road.
5. Make the level the default map (*Project Settings → Maps & Modes*). The game mode is
   already set: it spawns a **RiderPawn**, which rides the first RideRoute in the level.
6. In Sporterlay: tray → *Extras* → **Send power to the virtual world (Unreal)**. Press
   Play. The corner text shows `W  km/h  grade  km  [Sporterlay]` once power arrives.

On Linux, `--demo` Sporterlay sends demo power too.

## Tuning

`Config/DefaultGame.ini`, `[/Script/SporterlayWorld.RiderPawn]`: `TotalMassKg` (rider +
bike), `CdA` (0.32 on the hoods, ~0.25 in the drops), `Crr`, `AirDensity`,
`DrivetrainEfficiency`. With the defaults, 250 W gives ~37 km/h flat, 21 km/h at 4 %,
12 km/h at 8 %. The port must match Sporterlay's `world_port` (settings.json, default 47810).

On the pawn (place one in the level to edit it, or subclass it in Blueprint): `EyeHeight`,
`LaneOffset` (keep right), `LookAhead` (how far ahead the camera aims). On the route:
`GradeWindow` (grade measured over ±15 m), `SegmentLength`, `RoadWidth`.

## Running on the ride PC

Package with *Platforms → Windows → Package Project*. The game runs in borderless windowed
fullscreen (`DefaultGameUserSettings.ini`). Keep it that way: exclusive fullscreen would
cover Sporterlay's always-on-top HUD.

## Status

Written without an engine on the dev machine: **not compiled yet**. Expect a round of
compile fixes the first time it's built.
