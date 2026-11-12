-- Ribbon: a pool of render objects that draws a path or a list of segments,
-- updated in place every tick instead of destroyed and recreated.
--
-- A ribbon has one or more layers (e.g. a wide dim glow + a thin bright core).
-- Each layer draws every segment with one render object.
--
-- kind = "sprite" (default): stretched glow sprites from data.lua. They use
--   additive blending, so overlapping layers just add light and draw order
--   doesn't matter. Each sprite fades in and out at its ends, and pieces
--   overlap exactly by that fade, so the joins crossfade instead of
--   showing bright beads.
-- kind = "line": plain rendering lines. Cheaper and simpler, no texture.
--
-- A ribbon holds LuaRenderObjects, which can be kept in storage.

local V = require("__WePlayBeamLib__/lib/vec")

local R = {}

-- Fraction of the glow sprites' length used by each end fade (must match
-- the PNGs made for data.lua).
R.SPRITE_FADE = 0.2

-- Flip to -1 if sprite pieces turn the wrong way in-game.
R.ORIENTATION_SIGN = 1

local function rgb(c)
  if c.r then return c.r, c.g, c.b end
  return c[1], c[2], c[3]
end

--- opts:
---   surface               required
---   layers = { {width=tiles, color={r,g,b}, intensity=1, sprite="wp-beamlib-soft"}, ... }
---   kind = "sprite" | "line"
---   render_layer = "air-object"     (sprites only)
---   additive_lines = true           (lines only) zero-alpha colors, which the
---                                   premultiplied pipeline should treat as additive
---   players, forces                 optional visibility filters
function R.new(opts)
  local r = {
    surface = opts.surface,
    kind = opts.kind or "sprite",
    render_layer = opts.render_layer or "air-object",
    additive_lines = opts.additive_lines ~= false,
    players = opts.players,
    forces = opts.forces,
    layers = {},
    shown = 0,
  }
  for i, l in ipairs(opts.layers or {}) do
    r.layers[i] = {
      width = l.width or 0.3,
      color = l.color or {r = 1, g = 1, b = 1},
      intensity = l.intensity or 1,
      sprite = l.sprite or "wp-beamlib-soft",
      fade = l.fade or R.SPRITE_FADE,
      objects = {},
    }
  end
  return r
end

local function tint(r, layer, k)
  local cr, cg, cb = rgb(layer.color)
  k = k * layer.intensity
  local a = k
  if r.kind == "line" and r.additive_lines then a = 0 end
  return {r = cr * k, g = cg * k, b = cb * k, a = a}
end

local function create(r, layer, seg)
  if r.kind == "line" then
    return rendering.draw_line{
      surface = r.surface, from = seg.a, to = seg.b,
      width = layer.width * 32, color = tint(r, layer, seg.i or 1),
      players = r.players, forces = r.forces,
    }
  end
  return rendering.draw_sprite{
    surface = r.surface, sprite = layer.sprite, target = seg.a,
    render_layer = r.render_layer, tint = tint(r, layer, seg.i or 1),
    players = r.players, forces = r.forces,
  }
end

-- Writing a render object property is an API call, so only values that
-- actually changed are written. Positions change every tick; width and
-- brightness usually don't (the main stream never changes them).
local function place(r, layer, obj, seg, k)
  local a, b = seg.a, seg.b
  -- rounded to 1/16 so tiny changes (depth shading, fading sparks) don't
  -- each cost a write
  local w = math.floor((seg.w or 1) * 16 + 0.5) / 16
  local i = math.floor((seg.i or 1) * 16 + 0.5) / 16
  local last_w, last_i = layer.last_w, layer.last_i
  if r.kind == "line" then
    obj.from = {x = a.x, y = a.y}
    obj.to = {x = b.x, y = b.y}
    if last_w[k] ~= w then
      obj.width = layer.width * 32 * w
      last_w[k] = w
    end
  else
    local dx, dy = b.x - a.x, b.y - a.y
    local len = math.sqrt(dx * dx + dy * dy)
    obj.target = {x = (a.x + b.x) / 2, y = (a.y + b.y) / 2}
    obj.orientation = V.orientation(dx, R.ORIENTATION_SIGN * dy)
    obj.x_scale = len / (1 - layer.fade)
    if last_w[k] ~= w then
      obj.y_scale = layer.width * w
      last_w[k] = w
    end
  end
  if last_i[k] ~= i then
    obj.color = tint(r, layer, i)
    last_i[k] = i
  end
end

--- Draw a list of segments: { {a=, b=, w=width mult, i=intensity mult}, ... }
function R.set_segments(r, segs)
  local n = #segs
  for _, layer in ipairs(r.layers) do
    local shown = r.shown
    local objs = layer.objects
    layer.last_w = layer.last_w or {}
    layer.last_i = layer.last_i or {}
    -- One validity check per layer instead of one per object: our objects
    -- only go invalid all together (e.g. their surface was deleted).
    if objs[1] and not objs[1].valid then
      objs = {}
      layer.objects, layer.last_w, layer.last_i = objs, {}, {}
      shown = 0
    end
    local last_w, last_i = layer.last_w, layer.last_i
    for k = 1, n do
      local obj = objs[k]
      if not obj then
        obj = create(r, layer, segs[k])
        objs[k] = obj
        last_w[k] = nil
        last_i[k] = segs[k].i or 1  -- created with this tint already
      elseif k > shown then
        obj.visible = true  -- was hidden; visibility is tracked here, not read back
      end
      place(r, layer, obj, segs[k], k)
    end
    for k = n + 1, math.min(shown, #objs) do
      objs[k].visible = false
    end
  end
  r.shown = n
end

--- Draw a path. Points may carry .w and .i (width / intensity multipliers).
function R.set_path(r, points)
  local segs = {}
  for k = 1, #points - 1 do
    local a, b = points[k], points[k + 1]
    segs[k] = {
      a = a, b = b,
      w = ((a.w or 1) + (b.w or 1)) / 2,
      i = ((a.i or 1) + (b.i or 1)) / 2,
    }
  end
  R.set_segments(r, segs)
end

function R.hide(r)
  R.set_segments(r, {})
end

function R.destroy(r)
  for _, layer in ipairs(r.layers) do
    for _, obj in pairs(layer.objects) do obj.destroy() end
    layer.objects, layer.last_w, layer.last_i = {}, {}, {}
  end
  r.shown = 0
end

return R
