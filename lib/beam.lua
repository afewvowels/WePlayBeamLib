-- Beam: one object that ties everything together.
--
--   local beam = beamlib.beam.new{ surface=, source=entity, target=entity, path="wander", ... }
--   -- every tick (or every few ticks):
--   local alive, source_ok, target_ok = beamlib.beam.update(beam, game.tick)
--   -- when done:
--   beamlib.beam.destroy(beam)
--
-- Beams are plain tables of numbers, entity references and render objects,
-- so they can live in storage. Keep the update call in your own on_tick.

local V = require("__WePlayBeamLib__/lib/vec")
local P = require("__WePlayBeamLib__/lib/path")
local W = require("__WePlayBeamLib__/lib/wander")
local H = require("__WePlayBeamLib__/lib/helix")
local R = require("__WePlayBeamLib__/lib/ribbon")
local S = require("__WePlayBeamLib__/lib/sparks")

local DEFAULT_SPARK_LAYERS = {
  {width = 0.13, color = {r = 1, g = 0.75, b = 0.4}, intensity = 1.5, sprite = "wp-beamlib-core"},
}

local B = {}

local function is_entity(x)
  -- Game objects are userdata in Factorio 2.x; plain positions are tables.
  -- Reading object_name is safe on both (nil on a plain table).
  local t = type(x)
  return (t == "userdata" or t == "table") and x.object_name == "LuaEntity"
end

local function make_end(target, offset)
  offset = V.pos(offset or {0, 0})
  local e = {offset = offset}
  if is_entity(target) then
    e.entity = target
  elseif target then
    local p = V.pos(target)
    e.last = {x = p.x + offset.x, y = p.y + offset.y}
    e.fixed = true
  end
  return e
end

-- Current position of an end. Dead entities leave the end where it was last
-- seen (and report false); fixed positions always report true.
local function resolve(e)
  if e.fixed then return e.last, true end
  local ent = e.entity
  if ent and ent.valid then
    local p = ent.position
    e.last = {x = p.x + e.offset.x, y = p.y + e.offset.y}
    return e.last, true
  end
  e.entity = nil
  return e.last, false
end

local function copy_layers(layers, color)
  local out = {}
  for i, l in ipairs(layers or {}) do
    out[i] = {width = l.width, color = color or l.color, intensity = l.intensity, sprite = l.sprite, fade = l.fade}
  end
  return out
end

--- opts:
---   surface                 defaults to the source entity's surface
---   source, target          LuaEntity or position
---   source_offset, target_offset   e.g. {0, -1.3} to start at the shoulders
---   path = "wander"         "wander" | "straight" | "jagged" | "arcs" | "smooth"
---   wander = {...}          options for wander.new
---   jagged = {...}          options for path.jagged (+ bow for "arcs")
---   repath_ticks = 6        how often jagged/arcs/smooth paths re-roll
---   piece_length = 0.35     tiles per drawn piece
---   max_pieces = nil        cap on pieces per beam; long beams get longer pieces
---                           instead of more (keeps cost flat with length)
---   grow_speed = nil        tiles per tick the beam shoots out from the source when
---                           it starts (nil = appears instantly). Also spreads the
---                           cost of creating its render objects over several ticks.
---                           Sparks start once it reaches the target.
---   layers = {...}          ribbon layers for the main beam ({} = no main beam)
---   helix = {..., layers = {...}, strand_colors = { {r,g,b}, ... } }
---                           strands coiling around the path (optional)
---   tip = {sprite=, size=, color=, intensity=, pulse=}   glow at the tip (optional)
---   light = {intensity=, scale=, color=}                 light at the tip (optional)
---   sparks = {...sparks.new options, layers = {...}}     sparks spraying from the tip (optional)
---   sound = {start=, loop=, stop=, start_ticks=, loop_ticks=, volume=}
---                           sound prototype names played at the shooter (optional):
---                           start once, then loop chunks every loop_ticks
---                           (loop may be a list, played in turn), stop on release.
---                           Sounds can't be stopped once playing, so give loop
---                           chunks soft edges and overlap them a little.
---   kind, render_layer, players, forces                  passed to ribbons
function B.new(opts)
  local surface = opts.surface or (is_entity(opts.source) and opts.source.surface)
  local b = {
    surface = surface,
    src = make_end(opts.source, opts.source_offset),
    dst = make_end(opts.target, opts.target_offset),
    path = opts.path or "wander",
    jagged = {},  -- copied below without rng: functions can't be saved in storage
    repath_ticks = opts.repath_ticks or 6,
    next_repath = 0,
    piece_length = opts.piece_length or 0.35,
    max_pieces = opts.max_pieces,
    grow_speed = opts.grow_speed,
  }
  local ribbon_opts = {
    surface = surface, kind = opts.kind, render_layer = opts.render_layer,
    players = opts.players, forces = opts.forces,
  }
  for k, v in pairs(opts.jagged or {}) do
    if k ~= "rng" then b.jagged[k] = v end
  end
  if b.path == "wander" then b.wander = W.new(opts.wander) end

  ribbon_opts.layers = copy_layers(opts.layers)
  b.ribbon = R.new(ribbon_opts)

  if opts.helix then
    b.helix = H.new(opts.helix)
    b.helix_ribbons = {}
    local colors = opts.helix.strand_colors or {}
    for k = 1, b.helix.strands do
      local c = colors[(k - 1) % math.max(#colors, 1) + 1]
      ribbon_opts.layers = copy_layers(opts.helix.layers, c)
      b.helix_ribbons[k] = R.new(ribbon_opts)
    end
  end

  if opts.sparks then
    b.sparks = S.new(opts.sparks)
    b.sparks_on = true
    ribbon_opts.layers = copy_layers(opts.sparks.layers or DEFAULT_SPARK_LAYERS)
    b.spark_ribbon = R.new(ribbon_opts)
  end

  if opts.tip then
    local t = opts.tip
    b.tip = {
      size = t.size or 0.8, pulse = t.pulse or 0.15,
      sprite = t.sprite or "wp-beamlib-dot",
      color = t.color or {r = 1, g = 1, b = 1}, intensity = t.intensity or 1,
    }
  end
  if opts.light then
    b.light_opts = {
      intensity = opts.light.intensity or 0.6, scale = opts.light.scale or 1.5,
      color = opts.light.color or {r = 1, g = 1, b = 1},
    }
  end
  if opts.sound then
    local s = opts.sound
    local loop = s.loop
    if type(loop) == "string" then loop = {loop} end
    b.sound = {
      start = s.start, loop = loop, stop = s.stop,
      start_ticks = s.start_ticks or 0, loop_ticks = s.loop_ticks or 60,
      volume = math.min(1, math.max(0, s.volume or 1)),
      next = nil, k = 0,
    }
  end
  b.render_layer = opts.render_layer or "air-object"
  b.players, b.forces = opts.players, opts.forces
  return b
end

--- Point the beam somewhere else. The wander keeps its state, so the
--- stream swings over instead of popping.
function B.set_target(b, target, offset)
  b.dst = make_end(target, offset)
  b.next_repath = 0
  if b.released then
    b.released = false
    b.grow_start = nil                          -- shoots out again from the source
    if b.sound then b.sound.stop_at = nil end  -- back on target: no power-down
    B.show(b)
  end
end

--- Wandering beams only: glide to a lane (sideways offset mid-beam, tiles),
--- sway amount and tip radius. nil keeps the current value.
function B.set_lane(b, lane, amount, tip)
  if b.wander then W.set_lane(b.wander, lane, amount, tip) end
end

function B.set_source(b, source, offset)
  b.src = make_end(source, offset)
  b.next_repath = 0
end

-- Re-rolled paths are stored in the beam's own frame (fraction along, tiles
-- sideways) so they stay attached to both ends between re-rolls.
local function piece_length(b, a, t)
  if b.max_pieces then return math.max(b.piece_length, V.dist(a, t) / b.max_pieces) end
  return b.piece_length
end

local function reroll(b, a, t)
  local corners = P.jagged(a, t, b.jagged)
  local pl = piece_length(b, a, t)
  local pts
  if b.path == "arcs" then
    pts = P.arcs(corners, {bow = b.jagged.bow, piece_length = pl})
  elseif b.path == "smooth" then
    pts = P.smooth(corners, pl)
  else
    pts = P.polyline(corners, pl)
  end
  local dx, dy, nx, ny, d = V.frame(a, t)
  local rel = {}
  for i, p in ipairs(pts) do
    local rx, ry = p.x - a.x, p.y - a.y
    rel[i] = {u = d > 1e-9 and (rx * dx + ry * dy) / d or 0, v = rx * nx + ry * ny}
  end
  b.rel = rel
end

local function from_rel(b, a, t)
  local dx, dy, nx, ny, d = V.frame(a, t)
  local pts = {}
  for i, r in ipairs(b.rel) do
    pts[i] = {x = a.x + dx * r.u * d + nx * r.v, y = a.y + dy * r.u * d + ny * r.v}
  end
  return pts
end

--- Builds this tick's drawable path without drawing anything.
function B.path_points(b, a, t, tick)
  if b.path == "wander" then
    return P.smooth(W.points(b.wander, a, t, tick), piece_length(b, a, t))
  elseif b.path == "straight" then
    return P.straight(a, t, piece_length(b, a, t))
  end
  if not b.rel or tick >= b.next_repath then
    reroll(b, a, t)
    b.next_repath = tick + b.repath_ticks
  end
  return from_rel(b, a, t)
end

--- Redraws the beam for this tick. You can call it every tick or less often
--- (e.g. every 2nd tick); time-based motion uses the tick, and sparks catch
--- up on the ticks in between.
--- Returns alive, source_ok, target_ok. alive is false only if an end has
--- never had a position; a dead entity end stays where it was last seen.
function B.update(b, tick)
  local a, a_ok = resolve(b.src)
  local t, t_ok = resolve(b.dst)
  if not (a and t) then return false, a_ok, t_ok end
  local dt = b.last_tick and math.min(math.max(tick - b.last_tick, 1), 10) or 1
  b.last_tick = tick
  if b.released then
    -- stream is off; only let the last sparks finish and the stop sound play
    if b.sparks then R.set_segments(b.spark_ribbon, S.step(b.sparks, nil, false, dt)) end
    local snd = b.sound
    if snd and snd.stop_at and tick >= snd.stop_at then
      b.surface.play_sound{path = snd.stop, position = a, volume_modifier = snd.volume}
      snd.stop_at = nil
    end
    return true, a_ok, t_ok
  end
  if b.hidden then B.show(b) end

  local snd = b.sound
  if snd then
    if not snd.next then
      if snd.start then b.surface.play_sound{path = snd.start, position = a, volume_modifier = snd.volume} end
      snd.next = tick + snd.start_ticks
    end
    if snd.loop and #snd.loop > 0 and tick >= snd.next then
      snd.k = snd.k % #snd.loop + 1
      b.surface.play_sound{path = snd.loop[snd.k], position = a, volume_modifier = snd.volume}
      snd.next = tick + snd.loop_ticks
    end
  end

  local pts = B.path_points(b, a, t, tick)
  local grown = true
  if b.grow_speed then
    b.grow_start = b.grow_start or tick
    local reach = (tick - b.grow_start + 1) * b.grow_speed
    if not b.grown then
      pts, grown = P.truncate(pts, reach)
      b.grown = grown or nil
    end
  end
  R.set_path(b.ribbon, pts)

  if b.helix then
    local strands = H.strands(b.helix, pts, tick)
    for k, strand in ipairs(strands) do
      R.set_segments(b.helix_ribbons[k], H.segments(b.helix, strand))
    end
  end

  local tip_pos = pts[#pts]
  if b.tip then
    local tp = b.tip
    local s = tp.size * (1 + tp.pulse * math.sin(tick * 0.8))
    local c = tp.color
    local k = tp.intensity
    local col = {r = (c.r or c[1]) * k, g = (c.g or c[2]) * k, b = (c.b or c[3]) * k, a = k}
    if not (tp.obj and tp.obj.valid) then
      tp.obj = rendering.draw_sprite{
        surface = b.surface, sprite = tp.sprite, target = tip_pos,
        render_layer = b.render_layer, tint = col,
        players = b.players, forces = b.forces,
      }
    end
    tp.obj.target = tip_pos
    tp.obj.x_scale = s
    tp.obj.y_scale = s  -- (color never changes after creation, so it isn't rewritten)
  end
  if b.light_opts then
    local lo = b.light_opts
    if not (b.light and b.light.valid) then
      b.light = rendering.draw_light{
        surface = b.surface, sprite = "utility/light_medium", target = tip_pos,
        intensity = lo.intensity, scale = lo.scale, color = lo.color,
        players = b.players, forces = b.forces,
      }
    end
    b.light.target = tip_pos
  end
  if b.sparks then
    -- Sparks only spray while the target is alive; live ones finish their arc.
    R.set_segments(b.spark_ribbon, S.step(b.sparks, tip_pos, t_ok and b.sparks_on and grown, dt))
  end
  return true, a_ok, t_ok
end

--- Turn the tip sparks on or off (existing sparks finish falling).
function B.set_sparks(b, on)
  b.sparks_on = on and true or false
end

--- Throw n extra sparks from the tip right now, e.g. when a target dies.
function B.spark_burst(b, n)
  if b.sparks and b.dst.last then S.burst(b.sparks, b.dst.last, n or 12) end
end

--- Hides everything without destroying it (cheap to show again next update).
function B.hide(b)
  R.hide(b.ribbon)
  for _, r in pairs(b.helix_ribbons or {}) do R.hide(r) end
  if b.spark_ribbon then
    R.hide(b.spark_ribbon)
    S.clear(b.sparks)
  end
  if b.tip and b.tip.obj and b.tip.obj.valid then b.tip.obj.visible = false end
  if b.light and b.light.valid then b.light.visible = false end
  b.hidden = true
end

--- Lets go: the stream, strands, tip and light disappear, but sparks already
--- in the air keep falling. set_target brings the stream back.
function B.release(b)
  R.hide(b.ribbon)
  for _, r in pairs(b.helix_ribbons or {}) do R.hide(r) end
  if b.tip and b.tip.obj and b.tip.obj.valid then b.tip.obj.visible = false end
  if b.light and b.light.valid then b.light.visible = false end
  local snd = b.sound
  if snd and snd.next then
    -- The stop sound takes the next loop chunk's slot, so it overlaps the
    -- outgoing chunk exactly like loop chunks overlap each other.
    if snd.stop then snd.stop_at = snd.next end
    snd.next = nil
  end
  b.released = true
  b.grow_start, b.grown = nil, nil
end

--- True once a released beam has nothing left to draw (safe to destroy).
function B.is_idle(b)
  return b.released and not (b.sparks and #b.sparks.list > 0)
    and not (b.sound and b.sound.stop_at)
end

function B.show(b)
  if b.tip and b.tip.obj and b.tip.obj.valid then b.tip.obj.visible = true end
  if b.light and b.light.valid then b.light.visible = true end
  b.hidden = false
end

function B.destroy(b)
  R.destroy(b.ribbon)
  for _, r in pairs(b.helix_ribbons or {}) do R.destroy(r) end
  if b.spark_ribbon then R.destroy(b.spark_ribbon) end
  if b.tip and b.tip.obj then b.tip.obj.destroy() end
  if b.light then b.light.destroy() end
  b.tip, b.light = nil, nil
end

return B
