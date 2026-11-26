# Sporterlay World (Godot 4)

First-person rides through stylized, cel-shaded worlds. Everything is generated from a
seed when a world loads, so there are no art assets in the repo.

| World | `--world=` | What | Build time |
|---|---|---|---|
| Valley | `valley` | Green valley, snowy mountain ring, a wobbly loop. Pure noise. | ~1.6 s |
| Riverlands | `riverlands` | Autumn river basin (3.6 km across, 7.5 km loop) shaped by simulated water, layered cliffs and scree, forests of competing species, a planned road with bridges and fences | ~30 s |
| Canyon | `canyon` | Canyon country at golden hour (9.95 km loop): red mesas, a deep canyon with Petra-like ruins cut into its wall, an oasis with palms round a pool, vultures | ~5 s |
| Endless | `endless` | A road that never ends, through valley, autumn, dusk forest and canyon in turn, built around you as you ride; castles and arches now and then | instant |
| Giant | `giant` | A flooded giant world (15 km loop): islands and a mountain skirt, a wooden boardwalk over water, and trees at 10x normal size | ~3 s |
| Transylvania | `transylvania` | Late dusk in the Carpathians (6.9 km loop): misty hollows, dark spruce and dead trees, a torch-lit 120 m climb to a vampire's castle you ride through | ~4 s |

F2 switches to the next world while riding. A third world, `gallery`, is a test bench:
every tree model at each level of detail on flat ground (use with `--cam=`).

## How Riverlands is generated

Modelled on how big open-world teams build terrain (analysis maps first, then
freshwater, then rule-based biomes and layered placement):

1. **Base land** (`RiverLand.base`): domain-warped hills, a basin tilted towards an
   outlet, a mountain ring with a gap at the outlet.
2. **Freshwater**: a priority flood finds where every cell drains and fills hollows;
   flow accumulation counts the uphill area. Valleys are cut in proportion to the
   flow, hollows mostly silt up into flats, and a second flood gives rivers (enough
   upstream area) and lakes (hollows deeper than 2 m).
3. **Analysis maps** on a 5 m grid: slope, concavity, sun exposure, moisture,
   distance to water (and the nearest water level).
4. **Biomes**: forest, conifer share (high and shady), wetland (by water, flat), heath
   (sunny and dry), alpine (high or steep), each 0..1; they colour the ground.
5. **Road** (`RiverRoad`): A* between waypoints around the basin, paying for grade²,
   rough ground and water crossings; spurs and hairpins cut, smoothed, grade capped.
   Bridges where it crosses water.
6. **Cliffs** (`RiverCliffs`): a skin of rock layers over steep ground, the layer
   colours carried onto the terrain, rock fall leaving coloured scree, plants on ledges.
7. **Trees** (`RiverEcology`): each species' viability from the terrain maps; species
   compete for ground; size from age (young at forest edges, old in the core); the
   canopy colours and raises the forest floor.
8. **Understory and ground cover**: bushes at forest edges, ferns in the shade, mossy
   rocks by conifers, logs in old forest, rubble on scree; grass combed by the wind and
   leaning to water, reeds, flowers; then bridges and fences.

`--map=out.png` saves a top-down picture of the biomes, water and road.

The full logic, parameters, tools and tuning guide are in
[docs/riverlands-generation.md](docs/riverlands-generation.md).

## Transylvania

Properly dark, on purpose. `scripts/worlds/transylvania/`:

- **`TransLand`**: hills, a ring of high Carpathians with snow on the tops, and one
  ridge stamped along the road's own loop: it rises 120 m (eased, under the grade cap)
  to a flat crag halfway round, with flanks that steepen into cliffs near the top. The
  hills fade out on the ridge so the climb never dips. The loop is straightened through
  the castle so the road runs true through both gates.
- **`TransCastle`**: built in code in the castle's own frame (x right of the road, z
  along it): curtain wall with battlements, two gatehouses with a raised portcullis,
  round towers with red spires, a gabled keep with corner turrets, a great tower that
  stands in front of the moon on the climb, stables, a well. Lit windows
  (`window.gdshader`) flicker warm, a few blood red. The ground is levelled under it (`level()`), and the
  walls go 40 m down so nothing floats on the cliffs.
- **`TransTorches`**: torch pairs up the climb (16 m apart near the gates, 46 m low
  down), wall torches at the gates, braziers in the courtyard, and a troiță (roofed
  wayside cross) with a candle lantern every ~500 m. Flames are instanced quads
  (`flame.gdshader`); a pool of 18 omni lights follows the nearest fires, fading by
  distance, the nearest 4 with shadows.
- **`TransBats`**: big flocks round the great tower and the keep, and small groups
  low over the road all round the loop, closer together and bigger near the castle.
  One MultiMesh flown entirely in `bat.gdshader` (orbit and wingbeat from per-instance
  custom data); they're lit, so the torches catch them.
- **`TransScenery`**: spruce, late-autumn beech, dead and twisted trees (more near the
  castle and in the hollows), rocks, ferns, black pools. The mist is a FogVolume
  (`mist.gdshader`) below `TransLand.MIST` over a thin volumetric haze; the height fog
  carries it beyond the volumetric range.
- **Light**: `night_sky.gdshader` (afterglow, stars, moon with maria and halo, thin
  clouds). The moon is the directional light, placed behind the castle as seen from
  the climb. The ground mesh casts no shadows.

On the Sports PC (RTX 3060 Ti, 1080p, high): 116 fps on the castle climb, 107 fps in
the valley mist.

## Canyon

Golden hour in red-rock desert. `scripts/worlds/canyon/`:

- **`CanyonLand`**: a sandy floor with stepped mesas and buttes (`_terrace`: cliffs
  with benches, rock coloured in strata bands by height, desert varnish on the
  steepest faces). Mesas are kept off the open road; around the ruins the road runs
  down a 1.4 km canyon whose walls (up to 72 m) are stamped along the loop from a
  signed distance field (`ld`, `lu`): a slot in the middle, a wide plaza at the
  ruins where the right wall opens to the sun and the left rises sheer. The loop is
  straightened through the plaza. `flatten()` levels to a target height function;
  `hollows` are dug after the road is carved, `greens` colour the ground.
- **`CanyonRuins`**: in the plaza's own frame, with heights following the road's
  through it: a temple front cut into the sheer wall in the manner of Petra's
  Treasury, a colonnaded street (broken columns, fallen drums, lintels), a Roman
  arch at the plaza's mouth, house foundations.
- **`CanyonOasis`**: a hollow left of the road with a pool (the water shader on a
  plane), date palms built in code, reeds, green ground, and a hamlet of mud-brick
  houses with roof beams, domes and upper rooms.
- **`CanyonScenery`**: junipers, sagebrush, dead trees, desert grass,
  boulders fallen at the foot of cliffs. **`CanyonBirds`**: vultures circling high,
  flown by the bats' shader with slow, shallow wingbeats.
- **`CanyonCacti`**: saguaros (ribbed trunks, arms that bend up, some in bloom),
  barrel cacti with a crown of flowers, prickly pear clumps with magenta fruit, over
  the open desert out to ~360 m from the road (none in the canyon or the oasis).
- **`CanyonRocks`**: hoodoo gardens near the road, lone stepped spires out in the
  desert, and a natural arch the road passes under (`ARCH_AT`).
- **`canyon_ground.gdshader`**: detail painted in world space, fading with distance:
  strata lines and joints on rock (steep faces drawn faceted, so cliffs read as cut
  rock), ripples and pebbles on sand; `masonry` (blocks and joints) for the built
  ruins, `plaster` (blotches, bricks showing) for the oasis houses.
- **Light**: the sun 24 deg up, square-on from the plaza's open side so it lights the
  temple front; the canyon floor in shade under glowing rims.

Walls rise ~130 m, mesas up to 140 m. Desert grass: ~60k tufts, bunch grass,
grey-green clumps and yellow flowers out to ~180 m from the road. Tomb fronts with
stepped crowns line the canyon walls; the hamlet has ladders, jars and garden walls.

## Endless

A streamed world (`scripts/worlds/endless/`): nothing is built at load, everything
around the rider is generated as they ride and dropped behind them. The same
`--seed` always gives the same road and the same landscapes.

- **`StreamRoute`** (extends `Route`): the road, integrated from s = 0 in 2 m steps.
  Heading: a slow wander of at most ~70 deg round one direction plus bends (it can
  never cross itself). Height: follows the land and the cols ahead (looking 60-420 m
  on), grade eased in, capped at 6 % on the flat and 9 % on a col. Only ~6 km either side of the rider is kept (`ensure`, `trim`).
- **`EndlessClimbs`**: a col every 5-15 km: 150-450 m over 3-7 km (eased profile,
  ~5-6.5 % on the long middle, capped at 9 %), a short summit, a descent. The road
  follows it and the land rises with it, less away from the road (a shoulder with
  the valley below); the land's own bumps are flattened on a col so the grade is
  clean. Seed 7: cols at 8.3, 28.5 and 46.4 km.
- **`EndlessBiomes`**: the road in 6-10 km stretches (seeded order, starting in the
  valley), blended over 1.2 km: relief and ground colours per biome. Tiles blend
  them per vertex by the road distance of the nearest road point.
- **`EndlessLand`**: thread-safe height and colour; `build_tile()` runs on
  WorkerThreadPool. Landmark `pads` raise a crag or level ground.
- **`EndlessStream`**: 256 m near tiles along the road (400 m behind to 1.8 km
  ahead), 1 km far tiles out to 4.2 km; one tile lands per frame and its props a few
  kinds per frame; unloaded nodes are freed and `Lod.forget()`-ed.
- **`EndlessScatter`** + **`EndlessKit`**: props worked out on the tile's thread
  (each spot picks a biome by its weights, then that biome's rules), drawn with
  models made once from all our worlds.
- **`EndlessSky`** + `journey_sky.gdshader`: sky, sun or moon, ambient and fog
  blended every frame from the biomes' looks (day sky and dusk sky in one shader).
- **`EndlessLandmarks`**: every 10-20 km, by biome, kept in their biome and off the
  cols: a village the road runs through, built from the village kit (valley); a lake
  with a jetty, a boathouse and a moored raft (autumn); Transylvania's castle on a
  crag in a clearing (dusk forest); the natural arch and a ruined desert fort from the
  Raft pack (canyon). A cairn with a banner on every col's summit. Pack models are
  loaded at world start, so building a landmark never stalls a frame.

Sports PC, riding at ~50 km/h: valley 240 fps, dusk forest 171 fps, worst frame
12.8 ms.

## Giant

A flooded giant world (`scripts/worlds/giant/`): the ground is mostly below the water
line, leaving islands and a mountain skirt. A wooden boardwalk runs over the water,
and the trees are `TreeGen` models drawn at 10x normal size on the islands.

- **`GiantLand`**: a noise height field (7.2 km square, 8 m grid) with a water level at
  2 m; low ground is submerged, high ground is green islands, a ring of mountains rises
  outside `RING` (3 km).
- **The loop** (`GiantWorld._loop`): a circle of ~2.15 km radius with broad lobes and a
  faster meander, kept inside the ring: about 15 km around.
- **`GiantScenery`**: the ground mesh, a swamp-water plane (`shaders/swamp_water.gdshader`:
  tea-coloured, the bottom showing through with depth and bent by small waves, the sky
  reflected by view angle, sun glitter, duckweed patches, lily pads and shore foam; the
  other worlds keep `water.gdshader`), the boardwalk deck (its own mesh
  with UVs in metres, drawn by `shaders/boardwalk.gdshader`: planks with their own tone,
  grain, staggered joints, knots, nails, gaps and mossy edges, faded with distance),
  posts and railings in varied shades, 10x trees with LOD tiers, and reeds along the
  shore and in the shallows.
- The road follows the land, but is lifted to `WATER + 1.4` over water; the deck is
  wooden and stands on posts. Land trees grow above `WATER + 1.4`; below
  that, down to `SWAMP_DEPTH` (7 m) of water, stand swamp trees (a tall, stout `SWAMP`
  profile, olive crowns) and dead snags, thinning out with depth. Each stands on prop roots and
  cypress knees (`_roots_mesh`, three variants), with ripples drifting out where it
  meets the water (`shaders/ripple.gdshader`, also at the boardwalk posts). Wet trees
  keep their root spread clear of the road.
  Real lily pads (notched discs, 0.6-1.6 m across, about 5 % with a white or pink
  flower) sit in clusters in shallow water off the boardwalk, out to ~300 m.

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
2. On a fresh checkout, import the project once (or open it in the editor once):
   `Godot_v4.7.2-stable_win64_console.exe --headless --path world/godot --import`.
   `.godot/` is not in git, and without it Godot doesn't know the global class names
   (`RiverWorld`, `Rider`, `Lod`…): `main.gd` fails to parse and the window stays black.
3. Open `project.godot` in it and press Play (F5), or from a shell:
   `Godot_v4.7.2-stable_win64.exe --path world/godot`
4. In Sporterlay: tray → Extras → Virtual world → *Send power to the virtual world*.

Or let Sporterlay start it: tray → Extras → Virtual world → *Start the virtual world*, with the
world and seed picked in the same submenu (a change restarts a running world). Sporterlay uses
`build/SporterlayWorld.exe` when it exists, otherwise a Godot 4 binary it finds in Downloads,
Desktop, `C:\Tools\Godot` and similar, or the program chosen with *Choose the world program…*.
It imports the project on the first start and closes the world when Sporterlay quits.

Keys: **Esc** quit, **H** hide the status line, **F3** frame rate, **F4** detail levels, **F2** next world, **F11** fullscreen/windowed,
**Up/Down** manual power while Sporterlay isn't sending.

Options (after `--` when launching the editor binary, directly on an exported exe):
`--port=47810` (must match Sporterlay's `world_port`), `--world=riverlands`,
`--seed=7` (another variant), `--map=out.png`, `--bench=60` (ride 60 s with vsync off; prints the frame rate, memory use, GPU and CPU, and saves them to `bench.txt` in the user data folder: `%APPDATA%\Godot\app_userdata\Sporterlay World` on Windows, `~/.local/share/godot/app_userdata/Sporterlay World` on Linux), `--size=1920x1080` (window size), `--cam=x,y,z,tx,ty,tz` (fixed camera), `--look=90 --pitch=-8` (turn the rider's view), `--quality=high`, `--target-fps=60`, `--auto-lod=on`,
`--fade=on` (see [docs/level-of-detail.md](docs/level-of-detail.md)),
`--power=200`, `--at=1200` (start that far along the road),
`--shot=out.png --frames=90` (save a screenshot and quit; used for checks).

The game opens in borderless fullscreen (`window/size/mode=3`), not exclusive
fullscreen, so Sporterlay's always-on-top HUD stays visible above it.

### A standalone exe

*Project → Export → Windows Desktop → Export Project* (the editor offers to download
the export templates the first time). It writes `build/SporterlayWorld.exe` with the
game embedded. Icon/version editing (`application/modify_resources`) is off, so rcedit
isn't needed.

## Third-party models

`tools/import_assets.py <pack> <unzipped folder>` copies the models we use from each
pack into `assets/`, dropping normal and roughness maps and shrinking textures:

| Pack | Folder | License | Used for |
|---|---|---|---|
| Quaternius Stylized Nature MegaKit | `assets/megakit` | CC0 | trees, plants, rocks |
| Quaternius Medieval Village MegaKit (Standard) | `assets/village` | CC0 | houses and the church (`VillageKit`), jetty, fences |
| Quaternius Fantasy Props MegaKit (Standard) | `assets/props` | CC0 | barrels, crates, stalls, lanterns, banners |
| Raft on the Desert (EmacEArt) | `assets/local/raft` | ships in a game, not as files | the desert fort, the lake's raft |

The Raft pack's license forbids handing the files on, and the repository is public, so
`assets/local/` is ignored by git. `tools/import_assets.py --bundle out.zip` packs it to
carry to another computer, `--unbundle out.zip` puts it back there. Everything that
uses a pack checks for it (`MegaKit.has_pack`) and falls back or leaves it out.

`VillageKit` (`scripts/common/village_kit.gd`) assembles buildings from the village
kit's modules (2 m wall panels 3.12 m tall, finished side at -z; roofs by footprint),
one MultiMesh per module type, with a dark interior box behind the openings.

### Stylized Nature MegaKit

`assets/megakit/` holds 33 models from Quaternius' [Stylized Nature
MegaKit](https://quaternius.com/packs/stylizednaturemegakit.html) (CC0, see its
`LICENSE.txt`): twisted and dead trees, bushes, ferns, plants, purple flowers, mushrooms,
rocks and pebbles. `tools/import_assets.py megakit <unzipped pack>` makes that
folder from the free Standard pack: it picks the models, removes normal maps and shrinks
textures (11 MB). Without the folder the worlds fall back to our own models. `MegaKit` (`scripts/common/megakit.gd`) turns a model into a mesh drawn
with our `toon_tex` shader (texture × tint, toon light, cut-outs, sway, LOD dissolve),
with normals reworked like our own trees (crown-centred leaves, upward-bent plants) and
their baked vertex darkening dropped.

`--world=gallery --megakit=toon` shows them in our style, `--megakit=shipped` as they
come.

## Layout

| Path | What |
|---|---|
| `scripts/main.gd` | Picks and builds a world, status line, options, keys |
| `scripts/common/` | Shared: `MegaKit` (imported models in our style), `PowerLink` (UDP), `Rider` (physics, camera), `Route` (road from a rough loop, grade cap), `Roads` (road surface), `Look` (sky, fog, sun), `Lod` (level-of-detail manager), `Instancer` (chunked instances, LOD tiers), `TreeGen` (branching trees, conifers), `FlowerGrass` (flowering grass drifts), `MeshBuilder`, `Meshes` (props), `MinHeap` |
| `scripts/worlds/gallery/` | `GalleryWorld`: all tree models side by side |
| `scripts/worlds/valley/` | `ValleyWorld`, `ValleyTerrain`, `ValleyScenery` |
| `scripts/worlds/riverlands/` | `RiverWorld`, `RiverLand` (terrain, water, maps, biomes), `RiverRoad` (A*), `RiverCliffs` (strata skin, scree, ledges), `RiverEcology` (species, competition, age, understory), `RiverScenery` (order, ground cover, bridges, fences) |
| `shaders/` | Shared toon lighting (`toon.gdshaderinc`), ground/props, foliage (cut-out leaves, crown normals, sway), `toon_lod` + `lod_fade.gdshaderinc` (per-instance tier dissolve), grass, water, sky |

A new world is a class with `route` and `build(parent, seed)`, registered in
`main.gd`'s `worlds`.

Rider tuning is at the top of `rider.gd`: with 85 kg, CdA 0.32 and Crr 0.004, 250 W
gives ~37 km/h on the flat. Look tuning: colours at the top of each world's terrain script and `meshes.gd`,
light and fog in each world's `Look.apply()` overrides.
