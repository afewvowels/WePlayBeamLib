-- Lightning bolts that keep their shape, twitch, branch and change mood.
--
-- A bolt's shape is stored relative to its two ends (corners as fraction
-- along + tiles sideways, one bow per span), so it stretches and turns with
-- them and can be nudged ("twitched") between redraws instead of re-rolled.
-- Branches are dead-end offshoots attached by fraction along the path and an
-- angle off it. Moods decide how often a bolt is redrawn, how fast its sprites
-- flicker and whether it gets a new shape or just twitches.
--
-- Everything here is plain data (numbers, strings, tables), so shapes,
-- branches and mood state can live in storage. Pass `rng` (any function
-- returning [0, 1)) in opts to use your own generator; it is never stored.
--
-- Typical use, with pieces from datalib.make_path_beams / arcs.spawn:
--
--   local bolt = beamlib.bolt
--   local step = bolt.next_step(zap, bolt.MOODS)        -- mood, interval, reroll
--   if step.reroll or not zap.shape then
--     zap.shape = bolt.new_shape(dist, opts)
--     zap.branches = bolt.new_branches(dist, branch_opts)
--   else
--     bolt.twitch(zap.shape, twitch_opts)
--     bolt.twitch_branches(zap.branches, branch_opts, twitch_opts)
--   end
--   local points = bolt.points(a, b, zap.shape, opts)
--   arcs.spawn(surface, "my-bolt-" .. step.speed, points, step.interval)
--   for _, bp in pairs(bolt.branch_paths(points, zap.branches, branch_opts)) do
--     arcs.spawn(surface, "my-branch-" .. step.speed, bp, step.interval)
--   end

local V = require("__WePlayBeamLib__/lib/vec")
local P = require("__WePlayBeamLib__/lib/path")

local B = {}

local function rand(opts) return ((opts and opts.rng) or math.random)() end
local function rand_range(r, opts) return r[1] + rand(opts) * (r[2] - r[1]) end
local function rand_int(lo, hi, opts) return lo + math.floor(rand(opts) * (hi - lo + 1)) end

---------------------------------------------------------------------------------------------------
-- Shapes
---------------------------------------------------------------------------------------------------

--- New bolt shape for a bolt `length` tiles long.
--- opts (all optional):
---   segment_length = 1.6   average distance between corners, tiles
---   jitter = 1             corner count varies by up to this much
---   max_corners = 6
---   swing = 0.3            sideways push, as a fraction of the length
---   max_swing = 2.5        cap on the sideways push, tiles
---   bow = 0.35             max bulge of each span, as a fraction of the span
---   rng = math.random
--- Returns {corners = {{t =, s =}, ...}, bows = {...}, swing =, bow =}.
function B.new_shape(length, opts)
  opts = opts or {}
  local count = math.floor(length / (opts.segment_length or 1.6)) - 1
  local jitter = opts.jitter or 1
  if jitter > 0 then count = count + rand_int(-jitter, jitter, opts) end
  count = V.clamp(count, 0, opts.max_corners or 6)
  local swing = math.min(length * (opts.swing or 0.3), opts.max_swing or 2.5)
  local bow = opts.bow or 0.35
  local corners = {}
  local step = 1 / (count + 1)
  for i = 1, count do
    corners[i] = {
      t = step * i + (rand(opts) - 0.5) * step * 0.6,
      s = (rand(opts) * 2 - 1) * swing,
    }
  end
  local bows = {}
  for i = 1, count + 1 do bows[i] = (rand(opts) * 2 - 1) * bow end
  return {corners = corners, bows = bows, swing = swing, bow = bow}
end

--- Nudges a shape in place instead of re-rolling it.
--- opts (all optional):
---   along = 0.04   corner movement along the bolt (fraction)
---   side = 0.3     corner movement sideways (tiles), kept within the shape's swing
---   bow = 0.1      bow change (fraction), kept within the shape's bow
---   rng
function B.twitch(shape, opts)
  opts = opts or {}
  local along, side, dbow = opts.along or 0.04, opts.side or 0.3, opts.bow or 0.1
  for _, c in pairs(shape.corners) do
    c.t = V.clamp(c.t + (rand(opts) * 2 - 1) * along, 0.05, 0.95)
    c.s = V.clamp(c.s + (rand(opts) * 2 - 1) * side, -shape.swing, shape.swing)
  end
  table.sort(shape.corners, function(x, y) return x.t < y.t end)
  for i, b in pairs(shape.bows) do
    shape.bows[i] = V.clamp(b + (rand(opts) * 2 - 1) * dbow, -shape.bow, shape.bow)
  end
end

--- The shape's corners placed between a and b: a, corner, ..., b.
function B.corner_points(a, b, shape)
  local _, _, nx, ny, d = V.frame(a, b)
  local points = {a}
  if d > 1e-9 then
    for _, c in ipairs(shape.corners) do
      points[#points + 1] = {
        x = a.x + (b.x - a.x) * c.t + nx * c.s,
        y = a.y + (b.y - a.y) * c.t + ny * c.s,
      }
    end
  end
  points[#points + 1] = b
  return points
end

--- Drawable points for a shape between a and b.
--- opts (all optional):
---   style = "arc"          "arc" (bowed spans, sharp corners), "smooth"
---                          (Catmull-Rom through the corners) or "straight"
---   piece_length = 1       tiles per drawn piece
function B.points(a, b, shape, opts)
  opts = opts or {}
  local corners = B.corner_points(a, b, shape)
  local style, pl = opts.style or "arc", opts.piece_length or 1
  if style == "arc" then return P.arcs(corners, {bows = shape.bows, piece_length = pl}) end
  if style == "smooth" then return P.smooth(corners, pl) end
  return P.polyline(corners, pl)
end

---------------------------------------------------------------------------------------------------
-- Branches
---------------------------------------------------------------------------------------------------

--- Branch options (all optional):
---   per_tile = 0.3            average branches per tile of bolt
---   max = 5                   cap per bolt
---   length = {1, 3.5}         tiles
---   angle = {0.35, 1.25}      radians away from the bolt's direction, either side
---   sub_chance = 0.35         chance a branch grows one smaller branch
---   sub_scale = 0.55          the smaller branch's length, as a fraction
---   segment_length = 1.2      average distance between corners on a branch
---   swing = 0.35              branch corner swing, fraction of branch length
---   bow, jitter, max_corners  as for new_shape
---   swap_chance = 0.3         twitch_branches: chance one branch is replaced
---   rng

local function branch_shape_opts(opts)
  return {
    segment_length = opts.segment_length or 1.2,
    swing = opts.swing or 0.35,
    max_swing = opts.max_swing,
    bow = opts.bow,
    jitter = opts.jitter,
    max_corners = opts.max_corners,
    rng = opts.rng,
  }
end

--- One branch. depth 0 = off the bolt, 1 = off another branch.
function B.new_branch(opts, depth)
  opts = opts or {}
  depth = depth or 0
  local length = rand_range(opts.length or {1, 3.5}, opts) * (depth > 0 and (opts.sub_scale or 0.55) or 1)
  local side = rand(opts) < 0.5 and -1 or 1
  local branch = {
    u = depth > 0 and rand_range({0.3, 0.8}, opts) or rand_range({0.1, 0.9}, opts),
    angle = side * rand_range(opts.angle or {0.35, 1.25}, opts),
    length = length,
    shape = B.new_shape(length, branch_shape_opts(opts)),
  }
  if depth == 0 and rand(opts) < (opts.sub_chance or 0.35) then
    branch.child = B.new_branch(opts, 1)
  end
  return branch
end

--- A fresh set of branches for a bolt `length` tiles long.
function B.new_branches(length, opts)
  opts = opts or {}
  local per_tile = opts.per_tile or 0.3
  local count = math.min(opts.max or 5, math.floor(length * per_tile + rand(opts)))
  local list = {}
  for i = 1, count do list[i] = B.new_branch(opts, 0) end
  return list
end

local function twitch_branch(branch, twitch_opts)
  branch.angle = branch.angle + (rand(twitch_opts) * 2 - 1) * ((twitch_opts and twitch_opts.angle) or 0.2)
  branch.length = branch.length * (0.9 + rand(twitch_opts) * 0.2)
  B.twitch(branch.shape, twitch_opts)
  if branch.child then twitch_branch(branch.child, twitch_opts) end
end

--- Nudges every branch (angle by twitch_opts.angle = 0.2 radians, length by
--- ±10%, shape by B.twitch) and, with branch_opts.swap_chance, replaces one.
function B.twitch_branches(branches, branch_opts, twitch_opts)
  branch_opts = branch_opts or {}
  for _, branch in pairs(branches) do twitch_branch(branch, twitch_opts) end
  if #branches > 0 and rand(branch_opts) < (branch_opts.swap_chance or 0.3) then
    branches[rand_int(1, #branches, branch_opts)] = B.new_branch(branch_opts, 0)
  end
end

--- Drawable point lists for every branch (and sub-branch) off a drawn bolt.
--- Returns a list of point lists, each starting on its parent path.
--- opts: style, piece_length as for B.points.
function B.branch_paths(parent_points, branches, opts, out)
  out = out or {}
  for _, branch in pairs(branches or {}) do
    local start, dir = P.point_along(parent_points, branch.u)
    local angle = dir + branch.angle
    local finish = {
      x = start.x + math.cos(angle) * branch.length,
      y = start.y + math.sin(angle) * branch.length,
    }
    local points = B.points(start, finish, branch.shape, opts)
    out[#out + 1] = points
    if branch.child then B.branch_paths(points, {branch.child}, opts, out) end
  end
  return out
end

---------------------------------------------------------------------------------------------------
-- Moods
---------------------------------------------------------------------------------------------------

--- Default moods. Per mood:
---   interval = {min, max}   ticks until the next redraw
---   reroll                  chance of a brand-new shape (otherwise twitch)
---   speed                   a name for the sprite flicker speed, e.g. a
---                           prototype suffix from make_path_beam_variants
---   weight                  how likely the mood is picked
---   stay                    chance of keeping the mood at each redraw
B.MOODS = {
  frantic = {interval = {2, 4},  reroll = 0.9,  speed = "fast",   weight = 3, stay = 0.6},
  normal  = {interval = {4, 8},  reroll = 0.65, speed = "normal", weight = 4, stay = 0.6},
  calm    = {interval = {8, 16}, reroll = 0.15, speed = "slow",   weight = 3, stay = 0.5},
}

--- Picks a mood name by weight.
function B.pick_mood(moods, opts)
  moods = moods or B.MOODS
  local names = {}
  for name in pairs(moods) do names[#names + 1] = name end
  table.sort(names) -- stable order, so the same rng gives the same pick everywhere
  local total = 0
  for _, name in ipairs(names) do total = total + moods[name].weight end
  local r = rand(opts) * total
  for _, name in ipairs(names) do
    r = r - moods[name].weight
    if r <= 0 then return name end
  end
  return names[#names]
end

--- Decides how the next redraw behaves and remembers the mood in `state`
--- (any table you store, e.g. the bolt itself, as state.mood).
--- Returns {mood =, speed =, interval =, reroll =}.
function B.next_step(state, moods, opts)
  moods = moods or B.MOODS
  if not state.mood or not moods[state.mood] or rand(opts) > moods[state.mood].stay then
    state.mood = B.pick_mood(moods, opts)
  end
  local m = moods[state.mood]
  return {
    mood = state.mood,
    speed = m.speed,
    interval = rand_int(m.interval[1], m.interval[2], opts),
    reroll = rand(opts) < m.reroll,
  }
end

return B
