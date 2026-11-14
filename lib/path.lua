-- Path building. Every function takes and returns arrays of {x=, y=} points.
--
-- Two kinds of point lists show up here:
--   corners / control points: the few points a path is shaped around
--   pieces: the many points that get drawn, spaced about piece_length apart

local V = require("__WePlayBeamLib__/lib/vec")

local P = {}

local function rand(rng) return (rng or math.random)() end

--- Total length of a polyline.
function P.length(points)
  local total = 0
  for i = 1, #points - 1 do total = total + V.dist(points[i], points[i + 1]) end
  return total
end

local function pieces_for(len, piece_length)
  return math.max(1, math.floor(len / piece_length + 0.5))
end

--- Straight line from a to b cut into pieces about piece_length long.
function P.straight(a, b, piece_length)
  local n = pieces_for(V.dist(a, b), piece_length or 1)
  local out = {a}
  for k = 1, n do out[#out + 1] = V.lerp(a, b, k / n) end
  return out
end

--- Tesla-style jagged corners: a, corner, corner, ..., b.
--- opts (all optional):
---   segment_length = 1.6   average distance between corners, tiles
---   jitter = 1             corner count varies by up to this much
---   max_corners = 6
---   swing = 0.3            sideways push, as a fraction of the distance
---   max_swing = 2.5        cap on the sideways push, tiles
---   rng = math.random      any function returning [0, 1)
function P.jagged(a, b, opts)
  opts = opts or {}
  local rng = opts.rng or math.random
  local d = V.dist(a, b)
  local corners = math.floor(d / (opts.segment_length or 1.6)) - 1
  local jitter = opts.jitter or 1
  if jitter > 0 then corners = corners + math.floor(rng() * (2 * jitter + 1)) - jitter end
  corners = V.clamp(corners, 0, opts.max_corners or 6)

  local points = {a}
  if corners > 0 and d > 1e-6 then
    local _, _, nx, ny = V.frame(a, b)
    local swing = math.min(d * (opts.swing or 0.3), opts.max_swing or 2.5)
    local step = 1 / (corners + 1)
    for i = 1, corners do
      local t = step * i + (rng() - 0.5) * step * 0.6
      local s = (rng() * 2 - 1) * swing
      points[#points + 1] = {
        x = a.x + (b.x - a.x) * t + nx * s,
        y = a.y + (b.y - a.y) * t + ny * s,
      }
    end
  end
  points[#points + 1] = b
  return points
end

--- Straight lines between corners, cut into pieces.
function P.polyline(corners, piece_length)
  local out = {corners[1]}
  for i = 1, #corners - 1 do
    local seg = P.straight(corners[i], corners[i + 1], piece_length)
    for k = 2, #seg do out[#out + 1] = seg[k] end
  end
  return out
end

--- Tesla "arc" style: each span between corners bows out to a random side
--- (quadratic Bezier). Corners stay sharp kinks.
---   bow = 0.35            bulge as a fraction of the span length
---   bows = nil            optional fixed bow per span (fractions of the span
---                         length, signed); replaces the random bow, so a shape
---                         can be kept and nudged between redraws
---   piece_length = 1
---   rng = math.random
function P.arcs(corners, opts)
  opts = opts or {}
  local rng = opts.rng or math.random
  local bow_amount = opts.bow or 0.35
  local piece_length = opts.piece_length or 1
  local out = {corners[1]}
  for i = 1, #corners - 1 do
    local p, q = corners[i], corners[i + 1]
    local len = V.dist(p, q)
    local n = pieces_for(len, piece_length)
    if n == 1 or len < 1e-6 then
      out[#out + 1] = q
    else
      local bow
      if opts.bows then
        bow = (opts.bows[i] or 0) * len
      else
        bow = (rng() * 2 - 1) * bow_amount * len
      end
      local cx = (p.x + q.x) / 2 - (q.y - p.y) / len * bow
      local cy = (p.y + q.y) / 2 + (q.x - p.x) / len * bow
      for k = 1, n do
        local t = k / n
        local u = 1 - t
        out[#out + 1] = {
          x = u * u * p.x + 2 * u * t * cx + t * t * q.x,
          y = u * u * p.y + 2 * u * t * cy + t * t * q.y,
        }
      end
    end
  end
  return out
end

--- Smooth Catmull-Rom spline through every control point. This is the
--- "smooth" look from the Tesla, and what the wandering beam is drawn with.
function P.smooth(points, piece_length)
  piece_length = piece_length or 0.4
  local n = #points
  if n < 3 then return P.polyline(points, piece_length) end
  local out = {points[1]}
  for i = 1, n - 1 do
    local p0 = points[math.max(i - 1, 1)]
    local p1 = points[i]
    local p2 = points[i + 1]
    local p3 = points[math.min(i + 2, n)]
    local steps = pieces_for(V.dist(p1, p2), piece_length)
    for k = 1, steps do
      local t = k / steps
      local t2, t3 = t * t, t * t * t
      local function f(a, b, c, d)
        return 0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (3 * b - a - 3 * c + d) * t3)
      end
      out[#out + 1] = {x = f(p0.x, p1.x, p2.x, p3.x), y = f(p0.y, p1.y, p2.y, p3.y)}
    end
  end
  return out
end

--- Point and direction at fraction u (0 to 1) of the way along a polyline,
--- measured by length. Returns point, direction in radians, total length.
function P.point_along(points, u)
  local total = P.length(points)
  local want = total * V.clamp(u, 0, 1)
  for i = 1, #points - 1 do
    local p, q = points[i], points[i + 1]
    local len = V.dist(p, q)
    if want <= len or i == #points - 1 then
      local t = len > 1e-9 and V.clamp(want / len, 0, 1) or 0
      return V.lerp(p, q, t), V.angle(q.x - p.x, q.y - p.y), total
    end
    want = want - len
  end
  return {x = points[1].x, y = points[1].y}, 0, total
end

--- The first `dist` tiles of a polyline (the end point is interpolated).
--- Returns the points and whether the whole path fit (dist >= length).
function P.truncate(points, dist)
  local out = {points[1]}
  local walked = 0
  for i = 1, #points - 1 do
    local a, b = points[i], points[i + 1]
    local len = V.dist(a, b)
    if walked + len >= dist then
      local t = len > 1e-9 and (dist - walked) / len or 1
      out[#out + 1] = V.lerp(a, b, t)
      return out, i == #points - 1 and t >= 1
    end
    out[#out + 1] = b
    walked = walked + len
  end
  return out, true
end

--- Even spacing along a polyline. Each returned point also has .s, its
--- distance along the path from the start. Returns points, total_length.
function P.resample(points, step)
  local out = {{x = points[1].x, y = points[1].y, s = 0}}
  local total = P.length(points)
  if total < 1e-6 then
    out[2] = {x = points[#points].x, y = points[#points].y, s = 0}
    return out, 0
  end
  local count = math.max(1, math.floor(total / step + 0.5))
  local spacing = total / count
  local seg, seg_start = 1, 0
  local seg_len = V.dist(points[1], points[2])
  for k = 1, count do
    local target = k * spacing
    while seg < #points - 1 and seg_start + seg_len < target do
      seg_start = seg_start + seg_len
      seg = seg + 1
      seg_len = V.dist(points[seg], points[seg + 1])
    end
    local t = seg_len > 1e-9 and V.clamp((target - seg_start) / seg_len, 0, 1) or 1
    local p = V.lerp(points[seg], points[seg + 1], t)
    p.s = target
    out[#out + 1] = p
  end
  return out, total
end

return P
