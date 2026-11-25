# Level of detail

All worlds share one level-of-detail manager, `Lod` (`scripts/common/lod.gd`). It decides
how far each kind of prop is drawn, and at which level of detail. Its goal is to hold the
frame rate while spending the remaining frame time where it shows most.

## Categories

Every drawn node belongs to a category with an **importance** from 0 to 1:

| Category | Importance | What |
|---|---|---|
| trees | 1.0 | all tree tiers, dead trees |
| grass | 0.9 | grass and flowers (and the grass shader's fade distances) |
| cliffs | 0.7 | cliff skin tiles |
| reeds | 0.6 | reeds |
| bushes | 0.6 | bushes and ledge plants |
| props | 0.45 | mossy rocks, rubble, logs, stumps |
| boulders | 0.4 | boulders |
| ferns | 0.4 | ferns |
| mounds | 0.3 | root mounds |

A world declares its categories with `Lod.category(name, importance)`, and registers
nodes with base distances, measured for a 1080p screen at a 72° field of view:

- `Instancer.build(..., lod = "grass")` and `build_tiers(..., lod)` register their
  chunks;
- `Lod.add(category, node, from, to, pad)` registers a single node (cliff tiles);
- `Lod.add_param(category, material, parameter, base)` registers a shader distance that
  scales with the category (grass fade);
- `Lod.add_fade(category, material, from, to)` registers a tier material that dissolves
  per instance (see below).

## What sets the distances

A node is drawn from `base × scale × focal ratio`:

- **Focal ratio**: the screen's focal length in pixels against 1080p at 72°. A taller
  window or a narrower field of view keeps the same on-screen sizes at a greater
  distance.
- **Scale**: one per category. It starts at the quality preset (`--quality=low` 0.6,
  `medium` 0.8, `high` 1.0, `ultra` 1.3) and moves between 0.35 and 1.6 with the budget.

## The budget

With `--auto-lod=on` (the default when riding, off in `--bench`):

1. **Measure.** Every frame, the larger of Godot's measured CPU and GPU render time for
   the viewport. Not the time between frames, which vsync pads to the refresh rate. The
   95th percentile is taken every 0.5 s.
2. **Estimate cost.** Each category's cost is the triangles of its nodes currently
   within range: instances × triangles per instance, read once per mesh. The count is
   done in slices of 300 nodes per frame, so it never causes a hitch.
3. **Over budget** (95th percentile over 85 % of `1000 / --target-fps` ms): the category
   with the highest `cost / importance³` gives up range (scale × 0.85). Importance
   counts cubed, so roadside trees and grass hold on while ferns, mounds and props go,
   unless trees are nearly the whole cost.
4. **Room to spare** (under 60 % of the budget for 4 s): the category with the highest
   `importance / scale` gets range back (scale × 1.08).
5. **Pacing.** At most one change every 1.5 s. A change updates materials at once and
   node ranges 400 per frame.

On the dev box with a 60 fps target it raises trees and grass to 1.6, cliffs to 1.36 and
reeds and bushes to 1.17. With an unreachable 500 fps target it settles at 509 fps.

## Trees: per-instance tiers with a dissolve

Trees have four tiers: full model, light model, far crown and blob. Each tier has its
own materials. Their shaders (`toon_lod`, `foliage`) include `lod_fade.gdshaderinc`:

- each **instance** works out its own distance to the camera (from its origin), so trees
  change tier one by one, not a whole chunk at once;
- outside its tier an instance **collapses to a point** in the vertex shader, so it
  costs no pixels;
- in a band of ±10 % around each boundary, a screen-space **dither** shows a growing
  share of the incoming tier's pixels and exactly the complementary share of the
  outgoing tier's, so there are no holes and no double pixels.

The chunks are only a coarse filter: each tier's chunk range is widened by the chunk's
half-diagonal. Chunk size depends on the tier. Heavy near tiers use small chunks (100 m
full, 150 m light), so little vertex work is wasted on collapsed instances. Far tiers use
big chunks (300 m crowns, 500 m blobs), so there are few draw calls.

Godot's built-in visibility fade (`VISIBILITY_RANGE_FADE_SELF`) was tried first: it cost
22 % of the frame rate. The shader dissolve costs about 14 % and also removes the chunk
popping. `--fade=off` turns the dissolve bands off (instant per-tree switch).

Other categories switch per chunk without a fade. They're small on screen at their
boundaries, and grass fades in its own shader.

## Using it

- **F4** shows each category's scale and the frame cost (95th percentile against the
  budget) under the status line.
- `--bench=60` prints the quality, whether auto was on, and the final scales.
- `--quality=`, `--target-fps=`, `--auto-lod=`, `--fade=` as above.

## Adding a category

1. Declare it in the world's scenery: `Lod.category("name", importance)`.
2. Pass `lod = "name"` to `Instancer.build()` / `build_tiers()`, or call `Lod.add()`.
3. For per-instance tiers, give each tier its own material whose shader includes
   `lod_fade.gdshaderinc` (`lod_keep_vertex()` in vertex, `lod_dither()` in fragment), and
   pass the materials in the tier list.

## Limits

- Cost is counted in triangles. Fill rate (grass overdraw, leaf cards) isn't counted
  per category, though the frame measurement still sees it.
- The frustum is ignored in the cost estimate: things behind the camera count too.
- One shared ground mesh, road and water aren't managed. They're always drawn.
