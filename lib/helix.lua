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
  }
end

--- Returns an array of strands; each strand is an array of {x=, y=, z=}.
function H.strands(h, path_points, tick)
  local step = h.step
  if h.max_samples then step = math.max(step, P.length(path_points) / h.max_samples) end
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
    local r = h.radius * env
    for k = 1, h.strands do
      local theta = V.TAU * (p.s / h.pitch - h.spin * t + (k - 1) / h.strands)
      local off = r * math.sin(theta)
      out[k][i] = {x = p.x + nx * off, y = p.y + ny * off, z = math.cos(theta)}
    end
  end
  return out
end

--- Turns one strand into drawable segments with depth shading.
--- Each segment: {a=, b=, w=width multiplier, i=intensity multiplier}.
function H.segments(h, strand)
  local segs = {}
  for i = 1, #strand - 1 do
    local a, b = strand[i], strand[i + 1]
    local w, k = 1, 1
    if h.depth then
      local f = ((a.z + b.z) / 2 + 1) / 2   -- 0 = fully behind, 1 = fully in front
      w = 0.55 + 0.45 * f
      k = 0.25 + 0.75 * f
    end
    segs[#segs + 1] = {a = a, b = b, w = w, i = k}
  end
  return segs
end

return H
