# Sporterlay World (Godot 4)

First-person rides through stylized, cel-shaded worlds. Everything is generated from a
seed when a world loads, so there are no art assets in the repo.

| World | `--world=` | What | Build time |
|---|---|---|---|
| Valley | `valley` | Green valley, snowy mountain ring, a wobbly loop. Pure noise. | ~1.6 s |
| Riverlands | `riverlands` | Autumn river basin shaped by simulated water, biomes from terrain analysis, a planned road with bridges and fences | ~4.5 s |

F2 switches to the next world while riding.

## How Riverlands is generated

Modelled on how big open-world teams build terrain (analysis maps first, then
freshwater, then rule-based biomes and layered placement):

1. **Base land** (`RiverLand.base`): domain-warped hills, a basin tilted towards an
   outlet, a mountain ring with a gap at the outlet.
2. **Freshwater**: a priority flood finds where every cell drains and fills hollows;
   flow accumulation counts the uphill area. Valleys are cut in proportion to the
   flow, hollows mostly silt up into flats, and a second flood gives rivers (enough
   upstream area) and lakes (hollows deeper than 2 m).
3. **Analysis maps** on a 10 m grid: slope, concavity, sun exposure, moisture,
   distance to water (and the nearest water level).
4. **Biomes**: forest, conifer share (high and shady), wetland (by water, flat), heath
   (sunny and dry), alpine (high or steep), each 0..1; they colour the ground.
5. **Road** (`RiverRoad`): A* between waypoints around the basin, paying for grade²,
   rough ground and water crossings; spurs and hairpins cut, smoothed, grade capped.
   Bridges where it crosses water.
6. **Scatter** (`RiverScenery`), biggest first, each layer keeping clear of earlier
   footprints: cliff rocks on steep ground, trees (patches of autumn colour, birches
   by water, conifers up high), bushes thickest at forest edges, logs and stumps in
   the woods, boulders; then reeds at the shore, grass and wildflowers along the road;
   then bridges and fences through open meadow.

`--map=out.png` saves a top-down picture of the biomes, water and road.

The full logic, parameters, tools and tuning guide are in
[docs/riverlands-generation.md](docs/riverlands-generation.md).

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

Keys: **Esc** quit, **H** hide the status line, **F2** next world, **F11** fullscreen/windowed,
**Up/Down** manual power while Sporterlay isn't sending.

Options (after `--` when launching the editor binary, directly on an exported exe):
`--port=47810` (must match Sporterlay's `world_port`), `--world=riverlands`,
`--seed=7` (another variant), `--map=out.png`,
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

| Path | What |
|---|---|
| `scripts/main.gd` | Picks and builds a world, status line, options, keys |
| `scripts/common/` | Shared: `PowerLink` (UDP), `Rider` (physics, camera), `Route` (road from a rough loop, grade cap), `Roads` (road surface), `Look` (sky, fog, sun), `Instancer` (chunked instances, LOD), `MeshBuilder`, `Meshes` (props), `MinHeap` |
| `scripts/worlds/valley/` | `ValleyWorld`, `ValleyTerrain`, `ValleyScenery` |
| `scripts/worlds/riverlands/` | `RiverWorld`, `RiverLand` (terrain, water, maps, biomes), `RiverRoad` (A*), `RiverScenery` (layers, bridges, fences) |
| `shaders/` | Shared toon lighting (`toon.gdshaderinc`), ground/props, grass, water, sky |

A new world is a class with `route` and `build(parent, seed)`, registered in
`main.gd`'s `worlds`.

Rider tuning is at the top of `rider.gd`: with 85 kg, CdA 0.32 and Crr 0.004, 250 W
gives ~37 km/h on the flat. Look tuning: colours at the top of each world's terrain script and `meshes.gd`,
light and fog in each world's `Look.apply()` overrides.
