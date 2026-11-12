-- Small 2D vector helpers. Positions are always {x = ..., y = ...} tables.

local V = {}

V.TAU = 2 * math.pi

--- Accepts {x=, y=} or {1, 2} and returns {x=, y=}.
function V.pos(p)
  if p.x then return p end
  return {x = p[1], y = p[2]}
end

function V.add(a, b) return {x = a.x + b.x, y = a.y + b.y} end
function V.sub(a, b) return {x = a.x - b.x, y = a.y - b.y} end

function V.dist(a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  return math.sqrt(dx * dx + dy * dy)
end

function V.lerp(a, b, t)
  return {x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t}
end

--- Unit direction from a to b, plus the left-hand normal. Falls back to east.
function V.frame(a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 1e-9 then return 1, 0, 0, 1, 0 end
  dx, dy = dx / d, dy / d
  return dx, dy, -dy, dx, d
end

--- Factorio RealOrientation for a direction vector: 0 = north, 0.25 = east,
--- clockwise. A sprite drawn pointing east is turned to face (dx, dy).
function V.orientation(dx, dy)
  local o = math.atan2(dy, dx) / V.TAU
  if o < 0 then o = o + 1 end
  return o
end

function V.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

return V
