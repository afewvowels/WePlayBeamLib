# WePlay: Beam Library (`WePlayBeamLib`)

Shared beam effects for WePlay weapons. The library has no runtime state of its own: each weapon mod `require`s it and runs the beams inside its own scripts and storage. The only thing the library does on its own is the `/beamlib-demo` preview command.

## Quick start

`info.json` of the weapon mod:

```json
"dependencies": ["base >= 2.0", "WePlayBeamLib >= 0.6.1"]
```

`control.lua`:

```lua
local beamlib = require("__WePlayBeamLib__/beamlib")

-- start a beam
local opts = beamlib.presets.proton()
opts.source, opts.source_offset = player.character, {0, -1.3}
opts.target = enemy
storage.beams[id] = beamlib.beam.new(opts)

-- in on_tick
local alive, source_ok, target_ok = beamlib.beam.update(beam, game.tick)

-- switch targets without the stream popping
beamlib.beam.set_target(beam, new_enemy)

-- done
beamlib.beam.destroy(beam)
```

Beams are plain tables (numbers, entity references, render objects), so they can be stored in `storage`. Never put functions in beam options.

## Preview command

| Command | Shows |
|---|---|
| `/beamlib-demo proton` | wandering stream with a blue filament coiled around it |
| `/beamlib-demo wander` | wandering stream only |
| `/beamlib-demo helix` | straight core with two spiraling, depth-shaded strands |
| `/beamlib-demo lightning` | Tesla-style jagged path, re-rolled every 6 ticks |
| `/beamlib-demo off` | removes it |

The beam goes from your shoulders to whatever you hover over when you run the command, or to a spot 10 tiles to your right.

## Modules

### `beamlib.beam`: the all-in-one object

`beam.new(opts)`:

| Option | Default | Meaning |
|---|---|---|
| `surface` | source's surface | |
| `source`, `target` | | LuaEntity or position |
| `source_offset`, `target_offset` | `{0, 0}` | added to the entity position |
| `path` | `"wander"` | `"wander"`, `"straight"`, `"jagged"`, `"arcs"`, `"smooth"` |
| `wander` | | options for `wander.new` |
| `jagged` | | options for `path.jagged`, plus `bow` for `"arcs"` |
| `repath_ticks` | 6 | how often jagged, arcs and smooth paths re-roll |
| `piece_length` | 0.35 | tiles per drawn piece |
| `max_pieces` | none | cap on pieces; long beams get longer pieces instead of more (cost stays flat with length) |
| `grow_speed` | none | tiles per tick the beam shoots out from the source when it starts (or comes back after a release); spreads render object creation over several ticks; sparks start once it reaches the target |
| `layers` | | ribbon layers for the main beam; `{}` = no main beam |
| `helix` | none | `helix.new` options plus `layers` and `strand_colors` |
| `tip` | none | `{sprite, size, color, intensity, pulse}` glow at the tip |
| `light` | none | `{intensity, scale, color}` light at the tip |
| `sparks` | none | `sparks.new` options plus `layers`: sparks spraying from the tip |
| `sound` | none | `{start, loop, stop, start_ticks, loop_ticks, volume}`: sound prototype names played at the shooter (see below) |
| `kind`, `render_layer`, `players`, `forces` | | passed to ribbons |

- `beam.update(b, tick)` redraws and returns `alive, source_ok, target_ok`. A dead entity end stays where it was last seen; `alive` is false only if an end never had a position. Call it every tick for the smoothest motion, or every 2nd tick to halve the cost: motion is time-based, and sparks run their physics for the skipped ticks so they don't slow down.
- `beam.set_lane(b, lane, amount, tip)`: wandering beams only, see `wander.set_lane`.
- `beam.set_target(b, target, offset)` and `beam.set_source(...)` change ends; the wander keeps its state.
- `beam.set_sparks(b, on)` turns tip sparks on or off; live sparks finish falling. Sparks also stop by themselves while the target entity is dead.
- `beam.spark_burst(b, n)` throws n extra sparks right now, e.g. when a target dies.
- `beam.release(b)` lets go: the stream, strands, tip and light disappear, but sparks already in the air finish falling. `beam.set_target` brings it back. `beam.is_idle(b)` is true once a released beam has nothing left to draw, so it's safe to destroy.
- `beam.hide(b)` hides without destroying; the next `update` shows it again.
- `beam.destroy(b)`

**Sound.** Factorio can't stop a sound once it's playing, so a continuous hum is made of short loop chunks with soft fade-in/out edges, retriggered every `loop_ticks` so neighbors overlap by the fade length. `start` plays when the beam first draws (or comes back after a release), the first loop chunk follows `start_ticks` later, and `stop` plays after `beam.release`, in the slot where the next loop chunk would have started, so it overlaps the outgoing chunk like the chunks overlap each other. Give `stop` the same soft fade-in as the loop chunks. `loop` may be a list of names, played in turn so the hum doesn't sound robotic. `volume` is 0 to 1.

Re-rolled paths (jagged, arcs, smooth) are stored relative to the two ends, so they stay attached while the shooter or target moves between re-rolls.

### `beamlib.presets`

`proton()`, `helix()`, `lightning()` each return fresh option tables for `beam.new`. Tweak them freely.

### `beamlib.path`: path shapes

All take and return arrays of `{x=, y=}`.

| Function | Result |
|---|---|
| `straight(a, b, piece_length)` | straight line cut into pieces |
| `jagged(a, b, opts)` | Tesla corners: `segment_length` 1.6, `jitter` 1, `max_corners` 6, `swing` 0.3, `max_swing` 2.5, `rng` |
| `polyline(corners, piece_length)` | straight lines between corners |
| `arcs(corners, opts)` | each span bows out (quadratic Bezier): `bow` 0.35, `piece_length` 1, `rng` |
| `smooth(points, piece_length)` | Catmull-Rom spline through every point |
| `resample(points, step)` | even spacing; each point gets `.s`, distance from the start. Returns `points, total_length` |
| `length(points)` | total length |
| `truncate(points, dist)` | the first `dist` tiles of a path; returns `points, whole_path_fit` |

### `beamlib.wander`: the proton-pack meander

`wander.new(opts)` makes the state: `waypoints` 5, `amount` 1.2 (max sideways sway in tiles), `max_ratio` 0.18 (sway is also capped at this fraction of the beam length), `speed` 1, `tip` 0.4 (radius the tip circles the target), `along` 0.2 (lengthwise drift as a fraction of waypoint spacing), `lane` 0 (sideways offset of the whole curve mid-beam, tiles, zero at both ends), `lane_length` 8 (lanes reach full width on beams at least this long), `ease` 0.06, `rng`.

`wander.set_lane(state, lane, amount, tip)` glides to a new lane, sway amount and tip radius (nil keeps the current value). To fan several streams out without crossing, give them evenly spaced lanes and keep 2 × amount below the lane spacing.

`wander.points(state, a, b, tick)` gives the control points for that tick. Feed them to `path.smooth`. Waypoints never re-roll; each sways on its own pair of sine waves, zero at the muzzle and biggest mid-beam.

`wander.tip(state, b, tick)` is just the tip position, e.g. for splash damage where the tip lands.

### `beamlib.helix`: coiling strands

`helix.new(opts)`: `strands` 2, `radius` 0.35, `pitch` 1.2 (tiles per turn), `spin` 1.5 (turns per second; negative reverses), `pinch_start` 0.6 and `pinch_end` 0.15 (radius tapers to 0 over these lengths), `step` 0.2, `max_samples` none (cap on samples per strand; long beams space them out instead), `depth` true.

`helix.strands(h, path_points, tick)` coils around any path and returns one array of `{x, y, z}` per strand, where `z` = +1 in front of the beam and -1 behind. `helix.segments(h, strand)` turns a strand into ribbon segments with depth shading: in front means brighter and thicker.

### `beamlib.sparks`: impact sparks

`sparks.new(opts)`: `rate` 1.2 (sparks per tick), `speed` 0.13, `speed_jitter` 0.6, `lift` 0.08 (upward launch), `gravity` 0.009, `bounce` 0.35, `friction` 0.6, `life` 22 ticks, `life_jitter` 0.5, `streak` 3.5 (motion-blur length in ticks of travel), `min_streak` 0.1, `max` 40.

`sparks.step(s, pos, emitting)` advances one tick and returns ribbon segments; `sparks.burst(s, pos, n)`; `sparks.clear(s)`. Sparks have a fake height: they fly up, fall with gravity and bounce on the ground, drawn as glowing streaks along their on-screen motion.

### `beamlib.ribbon`: drawing

A pool of render objects updated in place every tick.

`ribbon.new{surface, layers, kind, render_layer, additive_lines, players, forces}`. Each layer is `{width = tiles, color = {r,g,b}, intensity = 1, sprite = "wp-beamlib-soft"}`.

- `ribbon.set_path(r, points)`: points may carry `.w` and `.i` width and intensity multipliers.
- `ribbon.set_segments(r, segs)`: `{a=, b=, w=, i=}` each.
- `ribbon.hide(r)` and `ribbon.destroy(r)`.

`kind = "sprite"` (default) uses the library's glow sprites with additive blending, so overlapping layers simply add light and draw order doesn't matter. Each sprite fades over its first and last 20%, and neighboring pieces overlap by exactly that much, so joins crossfade without bright beads. `kind = "line"` uses plain rendering lines: cheaper, untextured.

Performance: each piece is one render object per layer. Every update writes its position, orientation and length; width and brightness are only written when they change, visibility is tracked in script, and validity is checked once per layer. Cost scales with pieces × layers, so `piece_length`, `max_pieces`, `max_samples` and the number of layers are the main levers. Width and brightness are rounded to 1/16 before comparing, so tiny changes cost nothing.

Tuning constants: `ribbon.ORIENTATION_SIGN` (set to -1 if sprite pieces turn the wrong way) and `ribbon.SPRITE_FADE` (must match the PNGs).

### `beamlib.arcs`: Tesla-style beam entity pieces

`arcs.spawn(surface, prefix, points, duration)` creates one short-lived visual beam entity per piece, using the prototypes from `datalib.make_path_beams`. Best for paths that re-roll every few ticks.

## Data stage

```lua
local beamdata = require("__WePlayBeamLib__/datalib")
```

- `beamdata.make_path_beams{name, head, body, tail, start, ending, width, render_layer, graphics_extra}` creates `<name>-first`, `<name>`, `<name>-last` and `<name>-single` visual-only beams. Start sparks appear only on first and single, ending sparks only on last and single.
- `beamdata.invisible_beam_graphics()` returns a `graphics_set` that draws nothing, for damage beams whose visuals come from the library.

Sprites provided: `wp-beamlib-soft` (wide soft band), `wp-beamlib-core` (tight bright band), `wp-beamlib-dot` (round glow). Each is 1×1 tile, so `x_scale`/`y_scale` are length/width in tiles.

## Compatibility rule

Only add to the library; don't change what existing functions do or return. Weapon mods should depend on a minimum library version (`WePlayBeamLib >= 0.1.0`).
