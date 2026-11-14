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
local PU = require("__WePlayBeamLib__/lib/pulse")

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
    out[i] = {
      width = l.width, color = color or l.color, intensity = l.intensity, sprite = l.sprite, fade = l.fade,
      opaque = l.opaque, side = l.side, render_layer = l.render_layer,
    }
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
---   helices = { {...}, ... }  extra coils on top of `helix`, same option format
---                           (see beam.add_helix to add and remove them live)
---   pulses = {...}          pulse.new options: bright bands travelling down the
---                           beam (see beam.set_pulses). With a sound, the
---                           pulse clock starts with the first loop chunk, so
---                           pulses can be timed to the hum.
---   core = {width=1, intensity=1}   starting multipliers for the main beam
---                           (see beam.set_core)
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
      ribbon_opts.steps = opts.helix.steps
      ribbon_opts.split = opts.helix.split
      b.helix_ribbons[k] = R.new(ribbon_opts)
    end
    ribbon_opts.steps, ribbon_opts.split = nil, nil
  end

  -- kept so coils added later can make ribbons of their own
  b.ribbon_base = {
    surface = surface, kind = opts.kind, render_layer = opts.render_layer,
    players = opts.players, forces = opts.forces,
  }
  b.helices, b.next_helix_id = {}, 1
  for _, hopts in ipairs(opts.helices or {}) do B.add_helix(b, hopts) end
  if opts.pulses then b.pulses = PU.new(opts.pulses) end
  local core = opts.core or {}
  b.core = {
    w = core.width or 1, i = core.intensity or 1,
    goal_w = core.width or 1, goal_i = core.intensity or 1, ease = 0,
  }

  if opts.sparks then
    b.sparks = S.new(opts.sparks)
    b.sparks_on = true
    ribbon_opts.layers = copy_layers(opts.sparks.layers or DEFAULT_SPARK_LAYERS)
    b.spark_ribbon = R.new(ribbon_opts)
  end

  if opts.tip then
    local t = opts.tip
    b.tip = {
      size = t.size or 0.8, pulse = t.pulse or 0.15, pulse_rate = t.pulse_rate or 0.8,
      flash = t.flash or 0.6,
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

-- Beams saved by library versions before 0.7.0 don't have these fields.
local function upgrade(b)
  if b.core then return end
  b.ribbon_base = b.ribbon_base or {
    surface = b.surface, kind = b.ribbon and b.ribbon.kind, render_layer = b.render_layer,
    players = b.players, forces = b.forces,
  }
  b.helices, b.next_helix_id = b.helices or {}, b.next_helix_id or 1
  b.core = {w = 1, i = 1, goal_w = 1, goal_i = 1, ease = 0}
end

local function make_ribbons(b, hopts, h)
  local ribbons = {}
  local colors = hopts.strand_colors or {}
  for k = 1, h.strands do
    local c = colors[(k - 1) % math.max(#colors, 1) + 1]
    local ro = {}
    for key, v in pairs(b.ribbon_base) do ro[key] = v end
    ro.layers = copy_layers(hopts.layers, c)
    ro.steps = hopts.steps
    ro.split = hopts.split
    ribbons[k] = R.new(ro)
  end
  return ribbons
end

--- Adds an extra coil around the beam (same options as `helix`, plus layers
--- and strand_colors). With fade_ticks it unwinds out of the core instead of
--- popping in: radius and brightness grow from 0 over that many ticks.
--- Returns an id for beam.remove_helix.
function B.add_helix(b, hopts, fade_ticks)
  upgrade(b)
  local h = H.new(hopts)
  local fade = fade_ticks or 0
  local id = b.next_helix_id
  b.next_helix_id = id + 1
  b.helices[#b.helices + 1] = {
    id = id, h = h, ribbons = make_ribbons(b, hopts, h),
    amp = fade > 0 and 0 or 1, goal = 1, fade = fade,
  }
  return id
end

--- Removes a coil added with add_helix. With fade_ticks it winds back into
--- the core first. Unknown ids are ignored.
function B.remove_helix(b, id, fade_ticks)
  upgrade(b)
  for i, c in ipairs(b.helices) do
    if c.id == id then
      c.goal, c.fade = 0, fade_ticks or 0
      if c.fade <= 0 or b.released then
        for _, r in pairs(c.ribbons) do R.destroy(r) end
        table.remove(b.helices, i)
      end
      return
    end
  end
end

--- Number of extra coils that are on or fading in (not ones fading out).
function B.helix_count(b)
  upgrade(b)
  local n = 0
  for _, c in ipairs(b.helices) do
    if c.goal > 0 then n = n + 1 end
  end
  return n
end

--- Width and brightness multipliers for the main beam (and its tip size and
--- light). With ease_ticks the beam glides there instead of jumping.
function B.set_core(b, width, intensity, ease_ticks)
  upgrade(b)
  local c = b.core
  c.goal_w, c.goal_i = width or c.goal_w, intensity or c.goal_i
  c.ease = ease_ticks or 0
  if c.ease <= 0 then c.w, c.i = c.goal_w, c.goal_i end
end

--- Mutes or unmutes the beam's sound. A muted beam keeps its sound clock
--- (and pulse timing) running silently, so unmuting picks up with the next
--- loop chunk in rhythm; a beam that never started plays its start sound.
--- Releasing a muted beam plays no stop sound.
function B.set_muted(b, muted)
  b.muted = muted and true or nil
end

--- True once the beam has grown all the way to its target (always true
--- without grow_speed). A released beam that comes back grows again, so it
--- is false until it arrives. Use it to hold damage until the beam visibly
--- lands.
function B.reached(b)
  return not b.grow_speed or b.grown == true
end

--- Big irregular surge beads (see beamlib.pulse, surge config): turns them
--- on, changes the given fields, or stops new launches (nil); beads already
--- travelling finish their run. Needs the beam's pulses (made if missing,
--- with the regular bands switched off).
function B.set_surges(b, config, tick)
  if not b.pulses then
    if not config then return end
    b.pulses = PU.new({width = 0, intensity = 0, radius = 0, helix_intensity = 0})
  end
  PU.set_surges(b.pulses, config, tick)
end

--- Launches one surge bead right now (size nil = random).
function B.launch_surge(b, tick, size)
  if not b.pulses then B.set_surges(b, {}, tick); PU.set_surges(b.pulses, nil) end
  PU.launch(b.pulses, tick, size)
end

--- Takes over another beam's sound clock (and pulse timing), e.g. when a
--- hum moves from a beam that let go to one that's still firing: the next
--- loop chunk plays exactly where the other beam's would have, with no
--- start sound. Works on a released `from` too.
function B.sync_sound(b, from)
  local s, f = b.sound, from.sound
  if s and f then
    local nxt = f.next or f.resume
    if nxt then
      s.next, s.k = nxt, f.k
      s.stop_at = nil
    end
  end
  if b.pulses and from.pulses then b.pulses.t0 = from.pulses.t0 end
end

--- Turns pulses on (or changes them: only the given fields change) or off
--- (opts = nil). The pulse clock keeps running, so bands don't jump.
function B.set_pulses(b, opts)
  if not opts then
    b.pulses = nil
    return
  end
  if not b.pulses then b.pulses = PU.new({}) end
  for k, v in pairs(opts) do
    if k ~= "t0" then b.pulses[k] = v end
  end
end

local function glide(v, goal, dt, ease)
  if v == goal then return v end
  if ease <= 0 then return goal end
  local nv = v + (goal - v) * math.min(1, dt * 3 / ease)
  if math.abs(goal - nv) < 0.01 then return goal end
  return nv
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
  upgrade(b)
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
      if snd.start and not b.muted then
        b.surface.play_sound{path = snd.start, position = a, volume_modifier = snd.volume}
      end
      snd.next = tick + snd.start_ticks
      if b.pulses then b.pulses.t0 = snd.next end  -- pulses keep time with the loop
    end
    if snd.loop and #snd.loop > 0 and tick >= snd.next then
      snd.k = snd.k % #snd.loop + 1
      if not b.muted then
        b.surface.play_sound{path = snd.loop[snd.k], position = a, volume_modifier = snd.volume}
      end
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
  local core = b.core
  core.w = glide(core.w, core.goal_w, dt, core.ease)
  core.i = glide(core.i, core.goal_i, dt, core.ease)
  local draw = pts
  local coil_path = pts   -- the path the helices coil around (surges bend it)
  local pu = b.pulses
  b.tip_surge = 0
  if pu then
    -- copies: the path's points are shared with the ends and the tip
    local dist, total = {0}, 0
    for k = 2, #pts do
      total = total + V.dist(pts[k - 1], pts[k])
      dist[k] = total
    end
    local surging = pu.surge or (pu.surges and pu.surges[1])
    if surging then
      local landed = PU.step_surges(pu, tick, total)
      if landed > 0 then B.spark_burst(b, 8 * landed) end
      local sc0 = pu.surge
      if sc0 and sc0.sounds and pu.surges then
        -- surge swells: each bead may get one, timed so the swell's peak
        -- lands with the bead; at most one every sound_gap ticks
        for _, sg in ipairs(pu.surges) do
          if sg.snd == nil then
            sg.snd = false
            local left = sg.t + total / sg.speed * 60 - tick   -- ticks until it lands
            if tick >= (pu.next_swell or 0) and left > 0 then
              local fits = {}
              for _, s in ipairs(sc0.sounds) do
                if (s.peak or 0) <= left + 2 then fits[#fits + 1] = s end
              end
              if fits[1] then
                local pick = fits[math.floor(sg.phase * #fits) + 1]
                sg.snd, sg.snd_at = pick.path, tick + math.max(0, left - (pick.peak or 0))
                pu.next_swell = tick + (sc0.sound_gap or 60)
              end
            end
          end
          if sg.snd and sg.snd_at and tick >= sg.snd_at then
            if not b.muted then
              b.surface.play_sound{path = sg.snd, position = a, volume_modifier = sc0.sound_volume or 1}
            end
            sg.snd_at = nil
          end
        end
      end
    end
    local sc = pu.surge
    draw, coil_path = {}, surging and {} or pts
    for k, p in ipairs(pts) do
      local s = dist[k]
      local bump = PU.at(pu, s, tick)
      local w = 1 + pu.width * bump
      local i = 1 + pu.intensity * bump
      local x, y = p.x, p.y
      if surging then
        local swell, bend = PU.surge_at(pu, s, tick)
        if swell > 0 then
          w = w + sc.width * swell
          i = i + sc.intensity * swell
          -- bend sideways, easing to nothing at the muzzle and the tip
          local ends = math.max(0, math.min(1, s / 1.5, (total - s) / 1))
          if bend ~= 0 and ends > 0 then
            local _, _, nx, ny = V.frame(pts[math.max(k - 1, 1)], pts[math.min(k + 1, #pts)])
            x, y = x + nx * bend * ends, y + ny * bend * ends
          end
        end
        coil_path[k] = {x = x, y = y}
      end
      draw[k] = {x = x, y = y, w = core.w * w, i = core.i * i}
    end
    b.tip_bump = PU.at(pu, total, tick)
    if surging then b.tip_surge = PU.surge_at(pu, total + 0.6, tick) end  -- flare as a bead arrives
  elseif core.w ~= 1 or core.i ~= 1 then
    draw = {}
    for k, p in ipairs(pts) do draw[k] = {x = p.x, y = p.y, w = core.w, i = core.i} end
  end
  R.set_path(b.ribbon, draw)

  local track = (b.helix or b.helices[1]) and H.track(coil_path)   -- measured once for every coil
  if b.helix then H.draw(b.helix, track, tick, pu, b.helix_ribbons) end

  for idx = #b.helices, 1, -1 do
    local c = b.helices[idx]
    if c.amp ~= c.goal then
      local step = c.fade > 0 and dt / c.fade or 1
      if c.amp < c.goal then c.amp = math.min(c.goal, c.amp + step)
      else c.amp = math.max(c.goal, c.amp - step) end
    end
    if c.goal <= 0 and c.amp <= 0 then
      for _, r in pairs(c.ribbons) do R.destroy(r) end
      table.remove(b.helices, idx)
    else
      c.h.amp = c.amp * c.amp * (3 - 2 * c.amp)  -- smoothstep: eases in and out
      local every = c.h.every or 1
      c.skip = ((c.skip or 0) + 1) % every
      if c.skip == 0 or c.amp ~= c.goal then H.draw(c.h, track, tick, pu, c.ribbons) end
    end
  end

  local tip_pos = pts[#pts]
  if b.tip then
    local tp = b.tip
    local s = tp.size * core.w * (1 + tp.pulse * math.sin(tick * (tp.pulse_rate or 0.8)))
    if pu then s = s * (1 + (tp.flash or 0.6) * (b.tip_bump or 0)) end  -- flares as each band lands
    if b.tip_surge > 0 then s = s * (1 + pu.surge.flash * b.tip_surge) end  -- and bigger for a surge
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
      b.light_i = nil
      b.light = rendering.draw_light{
        surface = b.surface, sprite = "utility/light_medium", target = tip_pos,
        intensity = lo.intensity, scale = lo.scale, color = lo.color,
        players = b.players, forces = b.forces,
      }
    end
    b.light.target = tip_pos
    local li = math.floor(lo.intensity * core.i * 16 + 0.5) / 16
    if b.light_i ~= li then
      b.light.intensity = li
      b.light_i = li
    end
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
  for _, c in ipairs(b.helices or {}) do
    for _, r in pairs(c.ribbons) do R.hide(r) end
  end
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
  if b.pulses and b.pulses.surges then b.pulses.surges = {} end  -- beads in flight vanish with the beam
  R.hide(b.ribbon)
  for _, r in pairs(b.helix_ribbons or {}) do R.hide(r) end
  for idx = #(b.helices or {}), 1, -1 do
    local c = b.helices[idx]
    for _, r in pairs(c.ribbons) do
      if c.goal <= 0 then R.destroy(r) else R.hide(r) end
    end
    if c.goal <= 0 then table.remove(b.helices, idx) end
  end
  if b.tip and b.tip.obj and b.tip.obj.valid then b.tip.obj.visible = false end
  if b.light and b.light.valid then b.light.visible = false end
  local snd = b.sound
  if snd and snd.next then
    -- The stop sound takes the next loop chunk's slot, so it overlaps the
    -- outgoing chunk exactly like loop chunks overlap each other.
    if snd.stop and not b.muted then snd.stop_at = snd.next end
    snd.resume = snd.next  -- for beam.sync_sound
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
  for _, c in ipairs(b.helices or {}) do
    for _, r in pairs(c.ribbons) do R.destroy(r) end
  end
  b.helices = {}
  if b.spark_ribbon then R.destroy(b.spark_ribbon) end
  if b.tip and b.tip.obj then b.tip.obj.destroy() end
  if b.light then b.light.destroy() end
  b.tip, b.light = nil, nil
end

return B
