# Sporterlay World (Godot 4)

A first-person ride through a stylized valley: cel-shaded hills, wind-blown grass,
round trees and conifers, lakes and a ring of snowy mountains. Everything is generated
from a seed when it starts (~2 s), so there are no art assets in the repo.

## How it connects to Sporterlay

One way, and optional on both sides:

```
Sporterlay ──UDP 127.0.0.1:47810, 4 Hz──▶ PowerLink ──▶ Rider (own bike physics) ──▶ camera on the Route
            {"v":1,"power":245}            0 W after 2 s without a packet
```

- Sporterlay only sends raw power (tray → Extras → *Send power to the virtual world*).
  Nothing comes back: the world's hills, grade and speed never reach Sporterlay or the
  trainer. ERG, gears and Sporterlay's own speed and distance are unaffected.
- Sporterlay doesn't need the world, and the world doesn't need Sporterlay: without
  packets it rides on manual power (Up/Down, ±10 W), or `--power=N`.

## Running

1. Download Godot 4.7 (standard, not .NET) from godotengine.org. It's a single exe.
2. Open `project.godot` in it and press Play (F5), or from a shell:
   `Godot_v4.7.2-stable_win64.exe --path world/godot`
3. In Sporterlay: tray → Extras → *Send power to the virtual world*.

Keys: **Esc** quit, **H** hide the status line, **F11** fullscreen/windowed,
**Up/Down** manual power while Sporterlay isn't sending.

Options (after `--` when launching the editor binary, directly on an exported exe):
`--port=47810` (must match Sporterlay's `world_port`), `--seed=7` (another world),
`--power=200`, `--at=1200` (start that far along the road),
`--shot=out.png --frames=90` (save a screenshot and quit; used for checks).

The game opens in borderless fullscreen (`window/size/mode=3`), not exclusive
fullscreen, so Sporterlay's always-on-top HUD stays visible above it.

### A standalone exe

*Project → Export → Windows Desktop → Export Project* (the editor offers to download
the export templates the first time). It writes `build/SporterlayWorld.exe` with the
game embedded. Icon/version editing (`application/modify_resources`) is off, so rcedit
isn't needed.

## Layout

| File | What |
|---|---|
| `scripts/main.gd` | Builds the world, environment, sun, status line; command-line options, keys |
| `scripts/link.gd` | `PowerLink`: UDP receive |
| `scripts/rider.gd` | `Rider`: power → speed (mass, CdA, Crr, grade), camera along the road |
| `scripts/route.gd` | `Route`: the closed road loop, heights smoothed and capped at 7.5 % |
| `scripts/terrain.gd` | `Terrain`: height field with the road carved in, mountain skirt, vertex colours |
| `scripts/scenery.gd` | Road mesh, lake, chunked grass/tree/rock instances |
| `scripts/meshes.gd`, `mesh_builder.gd` | Procedural props |
| `shaders/toon.gdshaderinc` | Shared toon lighting (lit band, highlight band, rim) |
| `shaders/*.gdshader` | Ground/props, grass (wind, distance fade), water, sky |

Rider tuning is at the top of `rider.gd`: with 85 kg, CdA 0.32 and Crr 0.004, 250 W
gives ~37 km/h on the flat. Look tuning: colours in `terrain.gd`/`meshes.gd`, light and
fog in `main.gd._environment()`.
