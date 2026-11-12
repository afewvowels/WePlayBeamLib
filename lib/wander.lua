-- The wandering (proton pack) path.
--
-- Waypoints never re-roll. Each one sways sideways on its own pair of slow
-- sine waves with random speeds and phases, so they drift out of sync and
-- the smoothed curve through them meanders like a hose under pressure.
-- The sway is zero at the muzzle, biggest mid-beam, and the tip circles
-- around the target instead of locking dead on.
--
-- A wander state is plain numbers only, so it is safe to keep in storage.

local V = require("__WePlayBeamLib__/lib/vec")

local W = {}

local TAU = V.TAU

local function wave(rng)
  return {
    f1 = 0.6 + rng() * 0.9,  -- main sway speed
    f2 = 1.3 + rng() * 1.4,  -- faster secondary sway
    p1 = rng() * TAU,
    p2 = rng() * TAU,
    g = 0.5 + rng(),         -- lengthwise drift speed
    q = rng() * TAU,
  }
end

--- opts (all optional):
---   waypoints = 5     how many swaying points between muzzle and tip
---   amount = 1.2      max sideways sway mid-beam, tiles
---   max_ratio = 0.18  sway is also capped at this fraction of the beam length,
---                     so short beams don't turn into squiggles
---   speed = 1         sway speed multiplier (at 1, the main sway takes about 4-10 s)
---   tip = 0.4         radius the tip circles around the target, tiles
---   along = 0.2       how far waypoints drift lengthwise, as a fraction of their spacing
---   lane = 0          sideways offset of the whole curve mid-beam, tiles (0 at both ends).
---                     Give several streams different lanes and a small amount so they
---                     fan out and never cross.
---   lane_length = 8   lanes reach full width on beams at least this long; shorter beams
---                     get proportionally narrower lanes
---   ease = 0.06       how quickly lane / amount / tip glide to new values (per update)
---   rng = math.random
function W.new(opts)
  opts = opts or {}
  local rng = opts.rng or math.random
  local s = {
    waypoints = opts.waypoints or 5,
    amount = opts.amount or 1.2,
    max_ratio = opts.max_ratio or 0.18,
    speed = opts.speed or 1,
    tip = opts.tip or 0.4,
    along = opts.along or 0.2,
    lane = opts.lane or 0,
    lane_length = opts.lane_length or 8,
    ease = opts.ease or 0.06,
    waves = {},
    tip_wave = wave(rng),
  }
  s.lane_goal, s.amount_goal, s.tip_goal = s.lane, s.amount, s.tip
  for i = 1, s.waypoints do s.waves[i] = wave(rng) end
  return s
end

--- Where the tip is this tick (b plus its little orbit).
function W.tip(s, b, tick)
  local t = tick / 60 * s.speed
  local w = s.tip_wave
  return {
    x = b.x + s.tip * math.sin(t * w.f1 + w.p1),
    y = b.y + s.tip * math.sin(t * w.f2 * 0.8 + w.p2),
  }
end

--- Glide to a new lane / sway amount / tip radius (nil keeps the current goal).
function W.set_lane(s, lane, amount, tip)
  if lane then s.lane_goal = lane end
  if amount then s.amount_goal = amount end
  if tip then s.tip_goal = tip end
end

local function glide(s)
  local e = s.ease or 0.06
  if s.lane_goal then s.lane = (s.lane or 0) + (s.lane_goal - (s.lane or 0)) * e end
  if s.amount_goal then s.amount = s.amount + (s.amount_goal - s.amount) * e end
  if s.tip_goal then s.tip = s.tip + (s.tip_goal - s.tip) * e end
end

--- Control points for this tick: a, waypoints..., tip.
--- Feed them to path.smooth to get drawable pieces.
function W.points(s, a, b, tick)
  glide(s)
  local tip = W.tip(s, b, tick)
  local dx, dy, nx, ny, d = V.frame(a, tip)
  local pts = {a}
  if d < 1e-6 then
    pts[2] = tip
    return pts
  end
  local t = tick / 60 * s.speed
  local n = s.waypoints
  local amp = math.min(s.amount, d * s.max_ratio)
  local lane = (s.lane or 0) * math.min(1, d / (s.lane_length or 8))
  local spacing = d / (n + 1)
  for i = 1, n do
    local w = s.waves[i]
    local u = i / (n + 1)
    local env = math.sin(math.pi * u)
    local lat = lane * env + amp * env * (0.65 * math.sin(t * w.f1 + w.p1) + 0.35 * math.sin(t * w.f2 + w.p2))
    local lon = u * d + s.along * spacing * math.sin(t * w.g + w.q)
    pts[#pts + 1] = {x = a.x + dx * lon + nx * lat, y = a.y + dy * lon + ny * lat}
  end
  pts[#pts + 1] = tip
  return pts
end

return W
