-- Impact sparks: little glowing streaks that burst out of a point, arc up,
-- fall back down with gravity and bounce once or twice before fading.
--
-- They're simulated in script (positions + a fake height) and drawn as
-- stretched glow sprites through a ribbon, so they glow like the beam and
-- need no particle prototypes. A spark state is plain numbers only, so it's
-- safe to keep in storage.

local V = require("__WePlayBeamLib__/lib/vec")

local S = {}

--- opts (all optional):
---   rate = 1.2          new sparks per tick (fractions accumulate)
---   burst = 0           extra sparks spawned at once by sparks.burst
---   speed = 0.13        launch speed, tiles per tick
---   speed_jitter = 0.6  speed varies by up to this fraction
---   lift = 0.08         upward launch speed, tiles per tick
---   gravity = 0.009     tiles per tick per tick
---   bounce = 0.35       height speed kept after hitting the ground
---   friction = 0.6      ground speed kept after hitting the ground
---   life = 22           ticks
---   life_jitter = 0.5
---   streak = 3.5        streak length = speed * streak ticks (motion blur)
---   min_streak = 0.1    tiles
---   max = 40            hard cap on live sparks per emitter
function S.new(opts)
  opts = opts or {}
  return {
    rate = opts.rate or 1.2,
    speed = opts.speed or 0.13,
    speed_jitter = opts.speed_jitter or 0.6,
    lift = opts.lift or 0.08,
    gravity = opts.gravity or 0.009,
    bounce = opts.bounce or 0.35,
    friction = opts.friction or 0.6,
    life = opts.life or 22,
    life_jitter = opts.life_jitter or 0.5,
    streak = opts.streak or 3.5,
    min_streak = opts.min_streak or 0.1,
    max = opts.max or 40,
    acc = 0,
    list = {},
  }
end

local function spawn(s, pos)
  if #s.list >= s.max then return end
  local rng = math.random
  local angle = rng() * V.TAU
  local speed = s.speed * (1 - s.speed_jitter * rng())
  local life = s.life * (1 - s.life_jitter * rng())
  s.list[#s.list + 1] = {
    x = pos.x, y = pos.y, z = 0.05,
    vx = math.cos(angle) * speed,
    vy = math.sin(angle) * speed,
    vz = s.lift * (0.4 + 0.6 * rng()),
    age = 0, life = life,
  }
end

--- Spawn n sparks at once (e.g. when a target dies).
function S.burst(s, pos, n)
  for _ = 1, n do spawn(s, pos) end
end

--- Advance dt ticks (default 1). Spawns new sparks at pos if emitting is true.
--- Physics runs every tick even when drawing is less frequent, so sparks
--- fly at the same speed however often you redraw.
--- Returns ribbon segments ({a, b, w, i}) for drawing.
function S.step(s, pos, emitting, dt)
  dt = dt or 1
  if emitting and pos then
    s.acc = s.acc + s.rate * dt
    while s.acc >= 1 do
      spawn(s, pos)
      s.acc = s.acc - 1
    end
  end

  local segs = {}
  local keep = {}
  for _, p in ipairs(s.list) do
    p.age = p.age + dt
    if p.age < p.life then
      for _ = 1, dt do
        p.x, p.y, p.z = p.x + p.vx, p.y + p.vy, p.z + p.vz
        p.vz = p.vz - s.gravity
        if p.z < 0 then
          p.z = 0
          p.vz = -p.vz * s.bounce
          p.vx, p.vy = p.vx * s.friction, p.vy * s.friction
        end
      end
      keep[#keep + 1] = p

      -- On screen, height lifts the spark up (smaller y). The streak trails
      -- behind along the on-screen velocity.
      local sx, sy = p.x, p.y - p.z
      local dvx, dvy = p.vx, p.vy - p.vz
      local sp = math.sqrt(dvx * dvx + dvy * dvy)
      local len = math.max(sp * s.streak, s.min_streak)
      local ux, uy = 1, 0
      if sp > 1e-6 then ux, uy = dvx / sp, dvy / sp end
      local f = 1 - p.age / p.life
      segs[#segs + 1] = {
        a = {x = sx - ux * len, y = sy - uy * len},
        b = {x = sx, y = sy},
        w = 0.6 + 0.4 * f,
        i = math.sqrt(f),
      }
    end
  end
  s.list = keep
  return segs
end

function S.clear(s)
  s.list = {}
  s.acc = 0
end

return S
