# WePlay: Beam Library (`WePlayBeamLib`)

Shared beam effects for WePlay weapons. The library has no runtime state of its own: each weapon mod `require`s it and runs the beams inside its own scripts and storage. The only thing the library does on its own is the `/beamlib-demo` preview command.

## Quick start

`info.json` of the weapon mod:

```json
"dependencies": ["base >= 2.0", "WePlayBeamLib >= 0.17.0"]
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
| `helices` | none | list of extra coils, same format as `helix` (see `beam.add_helix`) |
| `pulses` | none | `pulse.new` options: bright bands travelling down the beam (see below) |
| `core` | `{width = 1, intensity = 1}` | starting multipliers for the main beam (see `beam.set_core`) |
| `tip` | none | `{sprite, size, color, intensity, pulse, pulse_rate, flash}` glow at the tip; `pulse_rate` 0.8 radians per tick, `flash` 0.6 = how much it flares when a pulse lands |
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
- `beam.add_helix(b, opts, fade_ticks)` adds an extra coil (same options as `helix`) and returns its id. With `fade_ticks` it unwinds out of the core: radius and brightness grow from 0 with a smoothstep ease. Coils sit on top of the beam's own `helix`, so a beam can carry any number of them, each with its own radius, pitch, spin, phase and colors.
- `beam.remove_helix(b, id, fade_ticks)` winds a coil back into the core and destroys it; `beam.helix_count(b)` counts coils that aren't on their way out.
- `beam.reached(b)` is true once the beam has grown all the way to its target (always true without `grow_speed`; false again while a released beam grows back). Use it to hold damage until the beam visibly lands.
- `beam.set_surges(b, config, tick)` turns on big, irregular surge beads (see `beamlib.pulse` for the config), changes the given fields, or stops new launches with `nil` (beads in flight finish their run). They ride on the beam's pulse state, which is made with the regular bands off if the beam has none. `beam.launch_surge(b, tick, size)` fires one right now. Each bead swells the main beam, bends it sideways (the helix coils follow the bent path and balloon out by their `bulge`), and lands with a tip flare and a spark burst. Releasing the beam clears beads in flight.
- `beam.set_muted(b, muted)` silences the beam's sound but keeps its sound clock (and pulse timing) running, so unmuting picks up with the next loop chunk in rhythm. A beam that never started plays its start sound when unmuted; a muted beam plays no stop sound on release. Use it to hand one hum between several beams.
- `beam.sync_sound(b, from)` takes over another beam's sound clock and pulse timing (also from a released beam): the next loop chunk plays exactly where `from`'s would have, with no start sound. Mute `from` before releasing it and the hum moves over seamlessly.
- `beam.set_pulses(b, opts)` turns pulses on, changes the given fields, or turns them off with `nil`. The pulse clock keeps running, so bands don't jump. When the beam has a sound, the clock starts with the first loop chunk, so a `rate` that matches the loop's rhythm keeps pulses in time with the hum.
- `beam.set_core(b, width, intensity, ease_ticks)` scales the main beam's width and brightness (and the tip size and light), gliding there over about `ease_ticks`. Handy for a beam that gets stronger as more equipment joins in.
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
| `arcs(corners, opts)` | each span bows out (quadratic Bezier): `bow` 0.35, `piece_length` 1, `rng`, and optional `bows` (one fixed signed bow per span, as a fraction of its length, replacing the random bow so a shape can be kept and nudged) |
| `smooth(points, piece_length)` | Catmull-Rom spline through every point |
| `resample(points, step)` | even spacing; each point gets `.s`, distance from the start. Returns `points, total_length` |
| `length(points)` | total length |
| `truncate(points, dist)` | the first `dist` tiles of a path; returns `points, whole_path_fit` |
| `point_along(points, u)` | point and direction (radians) at fraction `u` of the way along a path, by length; returns `point, angle, total_length` |

### `beamlib.wander`: the proton-pack meander

`wander.new(opts)` makes the state: `waypoints` 5, `amount` 1.2 (max sideways sway in tiles), `max_ratio` 0.18 (sway is also capped at this fraction of the beam length), `speed` 1, `tip` 0.4 (radius the tip circles the target), `along` 0.2 (lengthwise drift as a fraction of waypoint spacing), `lane` 0 (sideways offset of the whole curve mid-beam, tiles, zero at both ends), `lane_length` 8 (lanes reach full width on beams at least this long), `ease` 0.06, `rng`.

`wander.set_lane(state, lane, amount, tip)` glides to a new lane, sway amount and tip radius (nil keeps the current value). To fan several streams out without crossing, give them evenly spaced lanes and keep 2 × amount below the lane spacing.

`wander.points(state, a, b, tick)` gives the control points for that tick. Feed them to `path.smooth`. Waypoints never re-roll; each sways on its own pair of sine waves, zero at the muzzle and biggest mid-beam.

`wander.tip(state, b, tick)` is just the tip position, e.g. for splash damage where the tip lands.

### `beamlib.helix`: coiling strands

`helix.new(opts)`: `strands` 2, `radius` 0.35, `pitch` 1.2 (tiles per turn), `spin` 1.5 (turns per second; negative reverses), `pinch_start` 0.6 and `pinch_end` 0.15 (radius tapers to 0 over these lengths), `step` 0.2, `max_samples` none (cap on samples per strand; long beams space them out instead), `depth` true, `phase` 0 (turns; offsets a coil so stacked ones don't line up), `amp` 1 (presence 0 to 1: scales radius and brightness), `bulge` 1 (how much it swells when a pulse passes), `stretch` none (with `max_samples`: loosen the pitch so each turn keeps at least this many samples, so long beams coil looser instead of getting jagged and cost stays flat), and for beams `every` 1 (redraw on every Nth update) and `steps` 16 (rounding of depth shading; fewer = fewer writes).

`helix.track(points)` measures a path once and `helix.draw(h, track, tick, wave, ribbons)` draws a helix straight into its ribbons (one per strand), reusing scratch tables: this is what beams use, and it's 3 to 4 times cheaper than the functions below, which are kept for custom drawing.

`helix.strands(h, path_points, tick)` coils around any path and returns one array of `{x, y, z}` per strand, where `z` = +1 in front of the beam and -1 behind. `helix.segments(h, strand)` turns a strand into ribbon segments with depth shading: in front means brighter and thicker.

### `beamlib.pulse`: travelling bands

`pulse.new(opts)`: `rate` 2 (pulses per second leaving the source), `spacing` 3 (tiles between pulses; speed = rate × spacing), `band` 0.3 (band length as a fraction of spacing), `width` 0.6 and `intensity` 0.8 (main beam boost at a band's center), `radius` 0.35 (helix bulge; each helix scales it by its own `bulge`), `helix_intensity` 0.6, `phase` 0.

**Surges** ride on a pulse state. Config, all optional: `min_gap` 25 and `max_gap` 80 (ticks between launches), `speed` 9 (tiles per second), `length` 2.6 (tiles), `width` 1.6 and `intensity` 1.2 (main beam boost at a bead's center), `radius` 0.9 (helix boost, times each helix's `bulge`), `helix_intensity` 0.8, `wobble` 0.35 (tiles of sideways bend), `wavelength` 2.2 (tiles per S-curve), `size_min` 0.6 and `size_max` 1.2 (random size per bead), `flash` 1.2 (tip flare on landing), and for beams `sounds` (a list of `{path = sound name, peak = ticks to the sound's loudest point}`: each bead picks one whose peak fits its travel time and starts it so the peak lands with the bead), `sound_gap` 60 (at most one swell per this many ticks) and `sound_volume` 1. Each bead gets a random size, bend direction and phase from a Park-Miller generator kept in the state, so it's deterministic and storage-safe. `pulse.set_surges(p, config, tick)`, `pulse.launch(p, tick, size)`, `pulse.step_surges(p, tick, length)` (launches due beads, drops finished ones, returns how many landed) and `pulse.surge_at(p, s, tick)` (returns swell and sideways bend) are there for custom drawing.

`pulse.at(p, s, tick)` is 0 to 1: how much of a band sits `s` tiles from the source. `helix.strands` and `helix.segments` take the pulse state as an optional last argument.

### `beamlib.sparks`: impact sparks

`sparks.new(opts)`: `rate` 1.2 (sparks per tick), `speed` 0.13, `speed_jitter` 0.6, `lift` 0.08 (upward launch), `gravity` 0.009, `bounce` 0.35, `friction` 0.6, `life` 22 ticks, `life_jitter` 0.5, `streak` 3.5 (motion-blur length in ticks of travel), `min_streak` 0.1, `max` 40.

`sparks.step(s, pos, emitting)` advances one tick and returns ribbon segments; `sparks.burst(s, pos, n)`; `sparks.clear(s)`. Sparks have a fake height: they fly up, fall with gravity and bounce on the ground, drawn as glowing streaks along their on-screen motion.

### `beamlib.ribbon`: drawing

A pool of render objects updated in place every tick.

`ribbon.new{surface, layers, kind, render_layer, additive_lines, players, forces, steps, split}`. Layers can also take `side = "front"` or `"back"` (draw only segments on that side of the beam, by their `z`; hidden pieces skip their updates) and their own `render_layer`: a coil with a solid front layer above the beam and a glow back layer below it crosses over in crisp color while the far half glows behind. `split = {front = render layer, back = render layer}` sends segments with `z` ≥ 0 to the front layer and the rest to the back (helix segments carry `z`); give the same `split` as a helix option and the beam passes it on, so coils wrap around a solid core on a layer in between. Each layer is `{width = tiles, color = {r,g,b}, intensity = 1, sprite = "wp-beamlib-soft"}`.

- `ribbon.set_path(r, points)`: points may carry `.w` and `.i` width and intensity multipliers, and `.c` color (each segment takes its first point's color).
- `ribbon.set_segments(r, segs, count)`: `{a=, b=, w=, i=, c=}` each; `c` (optional) replaces the layer color for that piece, unless the layer has `own_color = true`; `count` (optional) uses only the first `count` segments, for reused lists.
- `ribbon.hide(r)` and `ribbon.destroy(r)`.

`kind = "sprite"` (default) uses the library's glow sprites with additive blending, so overlapping layers simply add light and draw order doesn't matter. Each sprite fades over its first and last 20%, and neighboring pieces overlap by exactly that much, so joins crossfade without bright beads. `kind = "line"` uses plain rendering lines: cheaper, untextured.

Performance: each piece is one render object per layer. Position, orientation and length are written only when they change (to 1/256 tile and 1/4096 turn), and so are width and brightness (rounded to 1/`steps`), visibility is tracked in script, and validity is checked once per layer. Cost scales with pieces × layers, so `piece_length`, `max_pieces`, `max_samples` and the number of layers are the main levers. Width and brightness are rounded to 1/16 before comparing, so tiny changes cost nothing.

Tuning constants: `ribbon.ORIENTATION_SIGN` (set to -1 if sprite pieces turn the wrong way) and `ribbon.SPRITE_FADE` (must match the PNGs).

### `beamlib.arcs`: Tesla-style beam entity pieces

`arcs.spawn(surface, prefix, points, duration, max_length)` creates one short-lived visual beam entity per piece, using the prototypes from `datalib.make_path_beams`. Best for paths that re-roll every few ticks. `max_length` is optional and passed to `create_entity`.

### `beamlib.bolt`: lightning that keeps its shape, twitches, branches and changes mood

The Tesla lightning engine. A bolt's shape is stored relative to its two ends (corners as fraction along + tiles sideways, one bow per span), so it stretches and turns with them and can be nudged between redraws instead of re-rolled. Everything is plain data, so shapes, branches and mood state can live in `storage`. Every function takes an optional `rng` in its options (never stored).

```lua
local bolt, arcs = beamlib.bolt, beamlib.arcs
local step = bolt.next_step(zap, bolt.MOODS)          -- {mood, speed, interval, reroll}
if step.reroll or not zap.shape then
  zap.shape = bolt.new_shape(dist, shape_opts)
  zap.branches = bolt.new_branches(dist, branch_opts)
else
  bolt.twitch(zap.shape, twitch_opts)
  bolt.twitch_branches(zap.branches, branch_opts, twitch_opts)
end
local points = bolt.points(a, b, zap.shape, {style = "arc", piece_length = 1})
arcs.spawn(surface, "my-bolt-" .. step.speed, points, step.interval)
for _, bp in pairs(bolt.branch_paths(points, zap.branches, {piece_length = 1})) do
  arcs.spawn(surface, "my-branch-" .. step.speed, bp, step.interval)
end
```

| Function | Does |
|---|---|
| `new_shape(length, opts)` | new shape: `segment_length` 1.6, `jitter` 1, `max_corners` 6, `swing` 0.3, `max_swing` 2.5, `bow` 0.35 |
| `twitch(shape, opts)` | nudges corners (`along` 0.04 fraction, `side` 0.3 tiles) and bows (`bow` 0.1), kept within the shape's swing and bow |
| `corner_points(a, b, shape)` | the corners placed between a and b |
| `points(a, b, shape, opts)` | drawable points: `style` `"arc"` (bowed spans, sharp corners), `"smooth"` or `"straight"`; `piece_length` 1 |
| `new_branches(length, opts)` | dead-end branches: `per_tile` 0.3, `max` 5, `length` {1, 3.5}, `angle` {0.35, 1.25} radians, `sub_chance` 0.35, `sub_scale` 0.55, `segment_length` 1.2, `swing` 0.35 |
| `new_branch(opts, depth)` | one branch (depth 1 = off another branch) |
| `twitch_branches(branches, branch_opts, twitch_opts)` | nudges angles (`twitch_opts.angle` 0.2), lengths (±10%) and shapes; replaces one with `branch_opts.swap_chance` 0.3 |
| `branch_paths(parent_points, branches, opts)` | point lists for every branch and sub-branch, each starting on its parent |
| `MOODS` | defaults: frantic (2–4 ticks, 90% new shape, `"fast"`), normal (4–8, 65%, `"normal"`), calm (8–16, 15%, `"slow"`); each also has `weight` and `stay` |
| `pick_mood(moods, opts)` | a mood name by weight |
| `next_step(state, moods, opts)` | keeps or changes `state.mood` (by its `stay` chance) and returns `{mood, speed, interval, reroll}` |

Pair it with `datalib.make_path_beam_variants` so `speed` (and any tint) picks the prototype: every piece of one redraw shares one speed.

## Data stage

```lua
local beamdata = require("__WePlayBeamLib__/datalib")
```

- `beamdata.make_path_beams{name, head, body, tail, tail_last, start, ending, width, render_layer, graphics_extra}` creates `<name>-first`, `<name>`, `<name>-last` and `<name>-single` visual-only beams. Start sparks appear only on first and single, ending sparks only on last and single. `tail_last` (optional) replaces the tail on last and single, e.g. a tip that fades out for a dead-end branch.
- `beamdata.make_path_beam_variants{...same..., tints = {name = color}, speeds = {name = animation_speed}}` makes those four for every tint and speed, named `<name>-<tint>-<speed>` (then `-first` / `-last` / `-single`); with only one of the two, `<name>-<tint>` or `<name>-<speed>`. Tint and speed are set on every animation (head, body variations, tail, tail_last, start, ending), all from the same sprite sheets, so tints cost no extra VRAM.
- `beamdata.invisible_beam_graphics()` returns a `graphics_set` that draws nothing, for damage beams whose visuals come from the library.

Sprites provided: `wp-beamlib-soft` (wide soft band), `wp-beamlib-core` (tight bright band), `wp-beamlib-dot` (round glow), all additive; and `wp-beamlib-solid` (opaque band with soft edges, normal blending). Ribbon layers using the solid sprite are drawn fully opaque (brightness scales the color, so below 1 it shades darker) and overlap by `ribbon.SOLID_OVERLAP` (0.06); the sprite's ends are feathered so two overlapping ends stack to exactly one piece's opacity (no knobs at the joints). Each is 1×1 tile, so `x_scale`/`y_scale` are length/width in tiles.

## Compatibility rule

Only add to the library; don't change what existing functions do or return. Weapon mods should depend on a minimum library version (`WePlayBeamLib >= 0.1.0`).
