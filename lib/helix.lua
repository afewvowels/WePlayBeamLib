-- Helix strands that coil around any path (straight, wandering, jagged...).
--
-- Each strand is a sine wave around the path, strands spaced evenly around
-- the circle (2 strands = 180 degrees apart = DNA). The phase slides with
-- time so the coil corkscrews forward. Each point also gets z = cos(phase):
-- +1 means the strand is "in front" of the beam, -1 "behind". The drawing
-- layer uses z to make front parts brighter and thicker, which is what makes
-- a flat top-down helix read as 3D.

local V = require("__WePlayBeamLib__/lib/vec")
local P = require("__WePlayBeamLib__/lib/path")
local PU = require("__WePlayBeamLib__/lib/pulse")
local R = require("__WePlayBeamLib__/lib/ribbon")

local H = {}

--- opts (all optional):
---   strands = 2
---   radius = 0.35        tiles
---   pitch = 1.2          tiles per full turn
---   spin = 1.5           turns per second; negative spins the other way
---   pinch_start = 0.6    radius grows from 0 over this many tiles at the muzzle
---   pinch_end = 0.15     and shrinks to 0 over this many at the tip
---   step = 0.2           sample spacing along the path, tiles
---   max_samples = nil    cap on samples per strand; long beams space them out
---                        instead of adding more (keeps cost flat with length)
---   depth = true         shade by depth
---   phase = 0            turns; offsets this coil so stacked coils don't line up
---   amp = 1              presence 0..1: scales radius and brightness (used to
---                        fade coils in and out, see beam.add_helix)
---   stretch = nil        with max_samples: instead of letting long beams get
---                        jagged, loosen the coil's pitch so each turn keeps at
---                        least this many samples. Cost stays flat with length
---                        and turns stay round; long beams just coil looser.
---   steps = 16           (beam only) depth shading is rounded to 1/steps of
---                        width and brightness; 8 or less saves writes
---   bulge = 1            how much this coil swells when a pulse passes
---                        (multiplies the pulse's radius setting)
---   every = 1            (beam only) redraw on every Nth beam update; 2 halves
---                        the cost of slow, wide coils whose motion is gentle
---   split = nil          (beam only) {front = render layer, back = render layer}:
---                        the parts of the coil behind the beam go on the back
---                        layer, the rest on the front, so it wraps around a
---                        solid core drawn on a layer in between
function H.new(opts)
  opts = opts or {}
  return {
    strands = opts.strands or 2,
    radius = opts.radius or 0.35,
    pitch = opts.pitch or 1.2,
    spin = opts.spin or 1.5,
    pinch_start = opts.pinch_start or 0.6,
    pinch_end = opts.pinch_end or 0.15,
    step = opts.step or 0.2,
    max_samples = opts.max_samples,
    depth = opts.depth ~= false,
    phase = opts.phase or 0,
    amp = opts.amp or 1,
    bulge = opts.bulge or 1,
    stretch = opts.stretch,
    every = opts.every,
  }
end

--- Returns an array of strands; each strand is an array of {x=, y=, z=}.
--- wave (optional): a pulse state (beamlib.pulse); coils bulge where bands pass,
--- and each point gets .bump (0..1) for H.segments.
function H.strands(h, path_points, tick, wave)
  local step, pitch = h.step, h.pitch
  if h.max_samples then
    local over = P.length(path_points) / h.max_samples
    if over > step then
      step = over
      if h.stretch then pitch = math.max(pitch, step * h.stretch) end
    end
  end
  local samples, total = P.resample(path_points, step)
  local t = tick / 60
  local m = #samples
  local out = {}
  for k = 1, h.strands do out[k] = {} end
  for i = 1, m do
    local p = samples[i]
    local prev = samples[math.max(i - 1, 1)]
    local nxt = samples[math.min(i + 1, m)]
    local _, _, nx, ny = V.frame(prev, nxt)
    local env = 1
    if h.pinch_start > 0 then env = math.min(env, p.s / h.pinch_start) end
    if h.pinch_end > 0 then env = math.min(env, (total - p.s) / h.pinch_end) end
    env = V.clamp(env, 0, 1)
    local r = h.radius * env * (h.amp or 1)
    local bump = wave and PU.at(wave, p.s, tick) or 0
    local swell = (wave and wave.surge and wave.surges and wave.surges[1]) and PU.surge_at(wave, p.s, tick) or 0
    if bump > 0 or swell > 0 then
      r = r * (1 + (wave.radius * bump + (swell > 0 and wave.surge.radius * swell or 0)) * (h.bulge or 1))
    end
    for k = 1, h.strands do
      local theta = V.TAU * (p.s / pitch - h.spin * t + (k - 1) / h.strands + (h.phase or 0))
      local off = r * math.sin(theta)
      out[k][i] = {x = p.x + nx * off, y = p.y + ny * off, z = math.cos(theta), bump = bump, swell = swell}
    end
  end
  return out
end

--- Turns one strand into drawable segments with depth shading.
--- Each segment: {a=, b=, w=width multiplier, i=intensity multiplier}.
--- wave (optional): the pulse state given to H.strands; brightens bumps.
function H.segments(h, strand, wave)
  local segs = {}
  for i = 1, #strand - 1 do
    local a, b = strand[i], strand[i + 1]
    local w, k = 1, 1
    if h.depth then
      local f = ((a.z + b.z) / 2 + 1) / 2   -- 0 = fully behind, 1 = fully in front
      w = 0.55 + 0.45 * f
      k = 0.25 + 0.75 * f
    end
    if wave then
      k = k * (1 + wave.helix_intensity * ((a.bump or 0) + (b.bump or 0)) / 2)
      if wave.surge and (a.swell or 0) + (b.swell or 0) > 0 then
        k = k * (1 + wave.surge.helix_intensity * ((a.swell or 0) + (b.swell or 0)) / 2)
      end
    end
    segs[#segs + 1] = {a = a, b = b, w = w, i = k * (h.amp or 1), z = (a.z + b.z) / 2}
  end
  return segs
end

-- Fast path ------------------------------------------------------------------
-- H.strands + H.segments + ribbon.set_segments build thousands of small
-- tables per update. H.draw does the same work straight into the ribbons,
-- reusing scratch tables (module-local, never stored, rebuilt every call),
-- sharing one sin/cos between strands, and measuring the path once per
-- update for all coils (H.track). Same look, same options.

local sin, cos, sqrt, floor, max, min = math.sin, math.cos, math.sqrt, math.floor, math.max, math.min
local TAU = 2 * math.pi
local SX, SY, SS = {}, {}, {}            -- samples along the path
local BUMP, SWELL = {}, {}               -- per sample
local PTS, SEGS = {}, {}                 -- per strand: point tables, segment tables

--- Measures a path once so several helices can share it:
--- returns {x = {...}, y = {...}, s = {...} cumulative length, n = count, total = length}.
function H.track(points)
  local x, y, s = {}, {}, {}
  local total = 0
  for i, p in ipairs(points) do
    if i > 1 then
      local dx, dy = p.x - x[i - 1], p.y - y[i - 1]
      total = total + sqrt(dx * dx + dy * dy)
    end
    x[i], y[i], s[i] = p.x, p.y, total
  end
  return {x = x, y = y, s = s, n = #points, total = total}
end

--- Draws helix h around a track (H.track) straight into its ribbons (one per
--- strand). wave: optional pulse state, as for H.strands.
function H.draw(h, track, tick, wave, ribbons)
  local total, tn = track.total, track.n
  local strands = h.strands
  if total < 1e-6 or tn < 2 then
    for k = 1, strands do R.set_segments(ribbons[k], SEGS, 0) end
    return
  end
  local step, pitch = h.step, h.pitch
  if h.max_samples then
    local over = total / h.max_samples
    if over > step then
      step = over
      if h.stretch then pitch = max(pitch, step * h.stretch) end
    end
  end
  local count = max(1, floor(total / step + 0.5))
  local spacing = total / count
  local m = count + 1

  -- resample evenly along the track
  local tx, ty, ts = track.x, track.y, track.s
  local seg = 1
  for i = 1, m do
    local target = (i - 1) * spacing
    while seg < tn - 1 and ts[seg + 1] < target do seg = seg + 1 end
    local len = ts[seg + 1] - ts[seg]
    local t = 1
    if len > 1e-9 then
      t = (target - ts[seg]) / len
      if t < 0 then t = 0 elseif t > 1 then t = 1 end
    end
    SX[i] = tx[seg] + (tx[seg + 1] - tx[seg]) * t
    SY[i] = ty[seg] + (ty[seg + 1] - ty[seg]) * t
    SS[i] = target
  end

  -- per-strand phase offsets as a rotation, so one sin/cos serves them all
  local amp = h.amp or 1
  local bulge = h.bulge or 1
  local tspin = h.spin * tick / 60
  local phase0 = h.phase or 0
  local surging = wave and wave.surge and wave.surges and wave.surges[1]
  local wr = wave and wave.radius or 0
  local sr = surging and wave.surge.radius or 0
  local ps, pe = h.pinch_start, h.pinch_end
  -- pulse bands inlined (same as PU.at)
  local p_inv, p_off, p_half
  if wave then
    p_inv = 1 / wave.spacing
    p_off = wave.phase - wave.rate * (tick - wave.t0) / 60
    p_half = 2 / wave.band
  end
  for k = 1, strands do
    PTS[k] = PTS[k] or {}
    SEGS[k] = SEGS[k] or {}
  end
  for i = 1, m do
    local ip, inx = i > 1 and i - 1 or 1, i < m and i + 1 or m
    local dx, dy = SX[inx] - SX[ip], SY[inx] - SY[ip]
    local d = sqrt(dx * dx + dy * dy)
    local nx, ny = 0, 1
    if d > 1e-9 then nx, ny = -dy / d, dx / d end
    local s = SS[i]
    local env = 1
    if ps > 0 then env = min(env, s / ps) end
    if pe > 0 then env = min(env, (total - s) / pe) end
    if env < 0 then env = 0 elseif env > 1 then env = 1 end
    local r = h.radius * env * amp
    local bump = 0
    if wave then
      local f = s * p_inv + p_off
      f = f - floor(f)
      local dd = (f < 1 - f and f or 1 - f) * p_half
      if dd < 1 then
        local xx = 1 - dd * dd
        bump = xx * xx
      end
    end
    local swell = surging and PU.surge_at(wave, s, tick) or 0
    if bump > 0 or swell > 0 then r = r * (1 + (wr * bump + sr * swell) * bulge) end
    BUMP[i], SWELL[i] = bump, swell
    local theta = TAU * (s / pitch - tspin + phase0)
    local s0, c0 = sin(theta), cos(theta)
    local x, y = SX[i], SY[i]
    for k = 1, strands do
      local sn, cs = s0, c0
      if k > 1 then
        local a = TAU * (k - 1) / strands
        local sa, ca = sin(a), cos(a)
        sn, cs = s0 * ca + c0 * sa, c0 * ca - s0 * sa
      end
      local pts = PTS[k]
      local p = pts[i]
      if not p then
        p = {}
        pts[i] = p
      end
      local off = r * sn
      p.x, p.y, p.z = x + nx * off, y + ny * off, cs
    end
  end

  -- segments with depth shading, straight into the ribbons
  local hi = wave and wave.helix_intensity or 0
  local shi = surging and wave.surge.helix_intensity or 0
  local depth = h.depth
  for k = 1, strands do
    local pts, segs = PTS[k], SEGS[k]
    for i = 1, m - 1 do
      local a, b = pts[i], pts[i + 1]
      local w, kk = 1, 1
      if depth then
        local f = ((a.z + b.z) / 2 + 1) / 2
        w = 0.55 + 0.45 * f
        kk = 0.25 + 0.75 * f
      end
      if wave then
        kk = kk * (1 + hi * (BUMP[i] + BUMP[i + 1]) / 2)
        if surging then kk = kk * (1 + shi * (SWELL[i] + SWELL[i + 1]) / 2) end
      end
      local sg = segs[i]
      if not sg then
        sg = {}
        segs[i] = sg
      end
      sg.a, sg.b, sg.w, sg.i, sg.z = a, b, w, kk * amp, (a.z + b.z) / 2
    end
    R.set_segments(ribbons[k], segs, m - 1)
  end
end

return H
