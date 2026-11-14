-- Pulses: bright bands that travel along a beam from the source to the
-- target, like energy being pumped down it. The main beam gets wider and
-- brighter where a band passes, and helix coils bulge out and brighten.
--
-- A pulse state is plain numbers, so it's safe to keep in storage.

local PU = {}

--- opts (all optional):
---   rate = 2            pulses per second leaving the source
---   spacing = 3         tiles between pulses (so speed = rate * spacing)
---   band = 0.3          length of a band, as a fraction of spacing
---   width = 0.6         main beam width boost at a band's center (0.6 = +60%)
---   intensity = 0.8     main beam brightness boost
---   radius = 0.35       helix radius bulge
---   helix_intensity = 0.6   helix brightness boost
---   phase = 0           fraction of a pulse period; shifts when bands leave
function PU.new(opts)
  opts = opts or {}
  return {
    rate = opts.rate or 2,
    spacing = opts.spacing or 3,
    band = opts.band or 0.3,
    width = opts.width or 0.6,
    intensity = opts.intensity or 0.8,
    radius = opts.radius or 0.35,
    helix_intensity = opts.helix_intensity or 0.6,
    phase = opts.phase or 0,
    t0 = 0,   -- tick the pulse clock counts from (beam sets it to the sound's loop start)
  }
end

--- 0..1: how much of a band sits at distance s (tiles from the source) on tick.
function PU.at(p, s, tick)
  local f = s / p.spacing - p.rate * (tick - p.t0) / 60 + p.phase
  f = f - math.floor(f)
  local d = math.min(f, 1 - f) * 2 / p.band   -- 0 at a band's center, 1 at its edge
  if d >= 1 then return 0 end
  local x = 1 - d * d
  return x * x
end

-- Surges -------------------------------------------------------------------
-- Big, irregular beads that ride the same pulse state: each one swells the
-- beam as it travels, bends it sideways in a travelling S-curve, makes helix
-- coils balloon out, and lands on the target with a flare. They're launched
-- at random gaps with random sizes, so the beam looks unstable and alive.
--
-- surge config (all optional):
--   min_gap = 25, max_gap = 80   ticks between launches
--   speed = 9                    tiles per second
--   length = 2.6                 tiles, the bead's full length
--   width = 1.6                  main beam width boost at a bead's center
--   intensity = 1.2              main beam brightness boost
--   radius = 0.9                 helix radius boost (times each helix's bulge)
--   helix_intensity = 0.8        helix brightness boost
--   wobble = 0.35                tiles of sideways bend at full size
--   wavelength = 2.2             tiles per S-curve of the bend
--   size_min = 0.6, size_max = 1.2   random size of each bead
--   flash = 1.2                  how much the tip flares when a bead lands
--   sounds = nil                 swells for beads (beam only): a list of
--                                {path = sound name, peak = ticks from the
--                                sound's start to its loudest point}. Each bead
--                                picks one whose peak fits its travel time, and
--                                it's started so the peak lands with the bead.
--   sound_gap = 60               at most one swell per this many ticks
--   sound_volume = 1

local SURGE_DEFAULTS = {
  min_gap = 25, max_gap = 80, speed = 9, length = 2.6,
  width = 1.6, intensity = 1.2, radius = 0.9, helix_intensity = 0.8,
  wobble = 0.35, wavelength = 2.2, size_min = 0.6, size_max = 1.2, flash = 1.2,
}

-- Park-Miller: plain numbers, exact in doubles, so it's deterministic and
-- safe in storage.
local function rand(p)
  p.seed = (p.seed * 16807) % 2147483647
  return p.seed / 2147483647
end

--- Turns surges on with a config (fields above; only the given ones change
--- if surges are already on) or off (nil). Turning them off stops new
--- launches; beads already travelling finish their run.
function PU.set_surges(p, config, tick)
  if not config then
    if p.surge then p.surge.off = true end  -- keep the config: travelling beads still need it
    return
  end
  local first = not p.surge or p.surge.off
  p.surge = p.surge or {}
  p.surge.off = nil
  for k, v in pairs(SURGE_DEFAULTS) do
    if p.surge[k] == nil then p.surge[k] = v end
  end
  for k, v in pairs(config) do p.surge[k] = v end
  p.surges = p.surges or {}
  p.seed = p.seed or ((tick or 0) * 7919 + 1) % 2147483646 + 1
  if first then p.next_surge = (tick or 0) + 1 end
end

--- Launches a bead right now (size 0..2ish; nil = random).
function PU.launch(p, tick, size)
  local c = p.surge or SURGE_DEFAULTS
  p.surges = p.surges or {}
  p.seed = p.seed or (tick * 7919 + 1) % 2147483646 + 1
  p.surges[#p.surges + 1] = {
    t = tick,
    size = size or (c.size_min + (c.size_max - c.size_min) * rand(p)),
    dir = rand(p) < 0.5 and -1 or 1,
    phase = rand(p),
    speed = c.speed, length = c.length,
  }
end

--- Launches beads when they're due and drops ones that have passed the end.
--- length = the beam's current length. Returns the number of beads that
--- reached the target this step (for a spark burst or a sound).
function PU.step_surges(p, tick, length)
  local landed = 0
  local c = p.surge
  if c and not c.off and tick >= (p.next_surge or 0) then
    PU.launch(p, tick)
    p.next_surge = tick + c.min_gap + math.floor((c.max_gap - c.min_gap) * rand(p) + 0.5)
  end
  local list = p.surges
  if not list then return 0 end
  for i = #list, 1, -1 do
    local sg = list[i]
    local center = sg.speed * (tick - sg.t) / 60
    if not sg.landed and center >= length then
      sg.landed = true
      landed = landed + 1
    end
    if center - sg.length / 2 > length then table.remove(list, i) end
  end
  return landed
end

--- Swell (0..~2, already scaled by bead size) and sideways bend (tiles) at
--- distance s on tick.
function PU.surge_at(p, s, tick)
  local list = p.surges
  if not list or #list == 0 then return 0, 0 end
  local c = p.surge or SURGE_DEFAULTS
  local swell, bend = 0, 0
  for i = 1, #list do
    local sg = list[i]
    local center = sg.speed * (tick - sg.t) / 60
    local x = (s - center) / (sg.length / 2)
    if x > -1 and x < 1 then
      local e = (1 - x * x)
      e = e * e * sg.size
      swell = swell + e
      bend = bend + sg.dir * c.wobble * e * math.sin(6.283185307 * ((s - center) / c.wavelength + sg.phase))
    end
  end
  return swell, bend
end

return PU
