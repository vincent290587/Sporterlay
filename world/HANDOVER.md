# Virtual world: handover (2026-11-25)

Where the virtual world stands, and what to do first on the Sports PC (Windows,
RTX 3060 Ti 8 GB, i7-13700K, 16 GB RAM, 1080p).

## State

- Branch **`feature/virtual-world`**, pushed to GitHub. It holds everything below.
- `experiment/megakit` was merged into it and only exists on the Linux dev box. It's
  kept there on purpose.
- Sporterlay itself is unchanged apart from wording. Its only link to the world is a
  UDP datagram with the power, sent to `127.0.0.1:47810` 4 times a second. Nothing comes
  back. Sporterlay runs the same without the world, and the world never touches the
  trainer, ERG or gears.

## What exists

The Godot 4.7 project is in `world/godot`. The earlier Unreal 5 version is in
`world/unreal` (never compiled, kept for later).

| World | `--world=` | What |
|---|---|---|
| Valley | `valley` | Green summer valley in a ring of snowy mountains, 4.7 km loop. Builds in ~3 s |
| Riverlands | `riverlands` | Autumn river basin, 3.6 km across, 7.4 km loop. Builds in ~40 s on the dev box |
| Gallery | `gallery` | Test bench: every tree, grass and flower model side by side |

Riverlands, roughly in the order it's generated:
- **Land and water:** droplet erosion, simulated rivers and lakes, analysis maps,
  biomes, and a road planned with A* that has bridges and fences.
- **Cliffs:** layered rock skin with scree below.
- **Trees:** competing species (broadleaf, birch, pine, spruce, twisted, dead), with
  tree age shaping forest edges.
- **Understory:** bushes, ferns, mushrooms, rocks.
- **Grass:** four types (short, average, tall, flowering), with drifts of plumes, stars
  and purple haze.
- **Far forests:** forest colour baked into the far ground, plus woods on the
  surrounding mountains.

Look: our own cel-shading. Models are partly procedural (our trees and grass) and partly
from Quaternius' Stylized Nature MegaKit (CC0, 33 models in `world/godot/assets/megakit`,
already in the repo).

A level-of-detail manager holds the frame rate. It cuts the least important things first
(root mounds, ferns, props) and keeps trees and grass for last.

## First steps on the Sports PC

1. `git fetch` and `git switch feature/virtual-world` in the Sporterlay folder.
2. Download **Godot 4.7.2 standard** (not .NET) for Windows from godotengine.org. It's a
   single exe; put it in e.g. `C:\Tools\Godot\`. No install, and no export templates
   needed to run.
3. Open a terminal in the Sporterlay folder and run the benchmark:
   ```
   C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe --path world/godot -- --world=riverlands --bench=60
   ```
   Wait ~40 s for the build plus 60 s of riding. It quits by itself. The result is in
   `%APPDATA%\Godot\app_userdata\Sporterlay World\bench.txt`. **This is the number we
   need:** frame rates so far are estimates from the dev box's RX 7900 XT. The estimate
   is ~65 fps at "high", and the manager should hold 60 regardless.
4. Ride it with Sporterlay:
   - start Sporterlay (`run.bat`);
   - tray → Extras → *Send power to the virtual world*;
   - start the world without `--bench`, and check that the status line shows
     `[Sporterlay]` and the rider moves.
5. Check that **Sporterlay's HUD stays above the world's fullscreen window**. The world
   opens in borderless fullscreen, which should allow it, but it's never been checked on
   Windows.

Keys in the world:

| Key | Does |
|---|---|
| Esc | Quit |
| H | Hide the status line |
| F2 | Next world |
| F3 | Frame rate |
| F4 | Detail levels and frame cost |
| F11 | Fullscreen / windowed |
| Up/Down | Manual power, without Sporterlay |

## Useful options

All go after `--` on the command line:

| Option | Does |
|---|---|
| `--world=valley\|riverlands\|gallery` | Which world |
| `--seed=7` | Which variant of it |
| `--at=1500` | Start that many metres along the road |
| `--power=200` | Fixed power, for testing without Sporterlay |
| `--quality=low\|medium\|high\|ultra` | Starting detail |
| `--target-fps=60` | Frame rate the detail manager holds |
| `--auto-lod=on\|off` | Let it adjust detail while riding |
| `--bench=60` | Ride that many seconds, report frame rate and memory, quit |
| `--size=1920x1080` | Window size |
| `--shot=out.png --frames=90` | Save a screenshot and quit |
| `--look=90 --pitch=-8` | Turn the view sideways from the road |
| `--cam=x,y,z,tx,ty,tz` | Fixed camera |
| `--map=out.png` | Top-down Riverlands map |

## Open items

- **Not yet measured on the Sports PC:** frame rate, the HUD on top, and the world's
  build time on the 13700K.
- **No standalone exe yet.** In the Godot editor: Project → Export → Windows Desktop
  (it downloads export templates the first time). The preset is ready and writes
  `world/godot/build/SporterlayWorld.exe`.
- **Camera:** on bends the rider's camera can pass close to a tree trunk.
- **Build time:** Riverlands takes ~40 s and is single-threaded. You said build time
  doesn't matter; quality comes first.
- **Possible next steps** (none started):
  - streams in the valley;
  - more worlds;
  - picking the world and seed from Sporterlay's tray;
  - snow or other seasons.

## Where things are documented

| File | Covers |
|---|---|
| `world/godot/README.md` | How to run, the options, the layout, the third-party models |
| `world/godot/docs/riverlands-generation.md` | Every generation step, parameters, tuning guide, known limitations |
| `world/godot/docs/level-of-detail.md` | The detail manager and the per-tree dissolve |
| `CLAUDE.md` | The virtual-world paragraph, for Claude Code sessions |

The Far Cry 5 slides and transcript are in `world/` on the dev box only, ignored by
git. They are not on the Sports PC.

## Working with Claude Code on the Sports PC

The project's memory folder (`~/.claude/...`) is per machine, so a session on the Sports
PC won't know the session history. Point it at this file and at `CLAUDE.md`. Preferences
to restate if needed:
- commit after each finished step;
- push only when asked;
- the world stays one-way and optional for Sporterlay;
- build time doesn't matter, frame rate does;
- new experiments go in a separate branch.
