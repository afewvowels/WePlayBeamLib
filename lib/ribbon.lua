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
-- Solid pieces have no end fade; they overlap by this fraction to close the
-- tiny gaps on bends.
R.SOLID_OVERLAP = 0.06

-- Flip to -1 if sprite pieces turn the wrong way in-game.
R.ORIENTATION_SIGN = 1

local function rgb(c)
  if c.r then return c.r, c.g, c.b end
  return c[1], c[2], c[3]
end

--- opts:
---   surface               required
---   layers = { {width=tiles, color={r,g,b}, intensity=1, sprite="wp-beamlib-soft"}, ... }
---                                   each layer may also have: side = "front" | "back"
---                                   (draw only segments on that side of the beam, by
---                                   their z; hidden pieces skip their updates),
---                                   render_layer (overrides the ribbon's), opaque,
---                                   fade, own_color (keep the layer's color even
---                                   when segments carry their own .c)
---   kind = "sprite" | "line"
---   render_layer = "air-object"     (sprites only)
---   additive_lines = true           (lines only) zero-alpha colors, which the
---                                   premultiplied pipeline should treat as additive
---   players, forces                 optional visibility filters
---   split = {front = layer, back = layer}   (sprites only) segments carrying z
---                                   (helix depth, -1 behind the beam .. +1 in
---                                   front) go on the front or back render layer,
---                                   so coils wrap around a solid core
---   steps = 16                      width and brightness are rounded to 1/steps
---                                   before deciding whether to write them; fewer
---                                   steps = fewer writes for constantly shaded
---                                   ribbons (helix depth shading)
function R.new(opts)
  local r = {
    surface = opts.surface,
    kind = opts.kind or "sprite",
    render_layer = opts.render_layer or "air-object",
    additive_lines = opts.additive_lines ~= false,
    players = opts.players,
    forces = opts.forces,
    steps = opts.steps,
    split = opts.split,
    layers = {},
    shown = 0,
  }
  for i, l in ipairs(opts.layers or {}) do
    r.layers[i] = {
      width = l.width or 0.3,
      color = l.color or {r = 1, g = 1, b = 1},
      intensity = l.intensity or 1,
      sprite = l.sprite or "wp-beamlib-soft",
      fade = l.fade or (l.sprite == "wp-beamlib-solid" and R.SOLID_OVERLAP) or R.SPRITE_FADE,
      opaque = l.opaque ~= nil and l.opaque or l.sprite == "wp-beamlib-solid",
      side = l.side,                   -- "front" / "back": only draw segments on that side (z)
      render_layer = l.render_layer,   -- overrides the ribbon's render layer for this layer
      own_color = l.own_color,         -- ignore per-segment colors (.c)
      objects = {},
    }
  end
  return r
end

-- Per-segment colors: a segment's .c replaces the layer color (unless the
-- layer has own_color). Returns nil when the layer color applies.
local function seg_color(layer, seg)
  if layer.own_color then return nil end
  return seg.c
end

-- Colors are compared at 6 bits per channel, so tiny shifts cost no write.
local function color_key(c)
  if not c then return -1 end
  local cr, cg, cb = rgb(c)
  return math.floor(cr * 63 + 0.5) * 4096 + math.floor(cg * 63 + 0.5) * 64 + math.floor(cb * 63 + 0.5)
end

local function tint(r, layer, k, c)
  local cr, cg, cb = rgb(c or layer.color)
  k = k * layer.intensity
  if layer.opaque then
    -- solid layers stay fully opaque; brightness only scales the color
    -- (below 1 darkens it, which reads as shade)
    return {r = math.min(1, cr * k), g = math.min(1, cg * k), b = math.min(1, cb * k), a = 1}
  end
  local a = k
  if r.kind == "line" and r.additive_lines then a = 0 end
  return {r = cr * k, g = cg * k, b = cb * k, a = a}
end

local function create(r, layer, seg)
  if r.kind == "line" then
    return rendering.draw_line{
      surface = r.surface, from = seg.a, to = seg.b,
      width = layer.width * 32, color = tint(r, layer, seg.i or 1, seg_color(layer, seg)),
      players = r.players, forces = r.forces,
    }
  end
  local rl = layer.render_layer or r.render_layer
  if r.split and not layer.render_layer then rl = (seg.z or 1) >= 0 and r.split.front or r.split.back end
  return rendering.draw_sprite{
    surface = r.surface, sprite = layer.sprite, target = seg.a,
    render_layer = rl, tint = tint(r, layer, seg.i or 1, seg_color(layer, seg)),
    players = r.players, forces = r.forces,
  }
end

-- Writing a render object property is an API call, so only values that
-- actually changed are written. Positions change every tick; width and
-- brightness usually don't (the main stream never changes them).
local function place(r, layer, obj, seg, k)
  local a, b = seg.a, seg.b
  -- rounded (to 1/16 by default, r.steps) so tiny changes (depth shading,
  -- fading sparks) don't each cost a write
  local q = r.steps or 16
  local w = math.floor((seg.w or 1) * q + 0.5) / q
  local i = math.floor((seg.i or 1) * q + 0.5) / q
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
    -- position, angle and length are cached too (to 1/256 tile, 1/4096
    -- turn and 1/256 tile): on straight beams angle and length rarely
    -- change, and nothing changes while shooter and target stand still
    local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
    local cache = layer.last_p
    local c = cache[k]
    if not c then
      c = {}
      cache[k] = c
    end
    local qx, qy = math.floor(mx * 256 + 0.5), math.floor(my * 256 + 0.5)
    if c[1] ~= qx or c[2] ~= qy then
      obj.target = {x = mx, y = my}
      c[1], c[2] = qx, qy
    end
    local o = V.orientation(dx, R.ORIENTATION_SIGN * dy)
    local qo = math.floor(o * 4096 + 0.5)
    if c[3] ~= qo then
      obj.orientation = o
      c[3] = qo
    end
    local ql = math.floor(len * 256 + 0.5)
    if c[4] ~= ql then
      obj.x_scale = len / (1 - layer.fade)
      c[4] = ql
    end
    local split = not layer.render_layer and r.split
    if split then
      local front = (seg.z or 1) >= 0
      if c[5] ~= front then
        if c[5] ~= nil then obj.render_layer = front and split.front or split.back end
        c[5] = front
      end
    end
    if last_w[k] ~= w then
      obj.y_scale = layer.width * w
      last_w[k] = w
    end
  end
  local c = seg_color(layer, seg)
  local last_c = layer.last_c
  local ck = c and color_key(c) or -1
  if last_i[k] ~= i or last_c[k] ~= ck then
    obj.color = tint(r, layer, i, c)
    last_i[k] = i
    last_c[k] = ck
  end
end

--- Draw a list of segments: { {a=, b=, w=width mult, i=intensity mult, c=color}, ... }
--- c (optional) replaces the layer color for that segment, e.g. for gradients.
--- count (optional): use only the first count segments (for reused lists).
function R.set_segments(r, segs, count)
  local n = count or #segs
  for _, layer in ipairs(r.layers) do
    local shown = r.shown
    local objs = layer.objects
    layer.last_w = layer.last_w or {}
    layer.last_i = layer.last_i or {}
    layer.last_p = layer.last_p or {}
    layer.last_c = layer.last_c or {}
    -- One validity check per layer instead of one per object: our objects
    -- only go invalid all together (e.g. their surface was deleted).
    if objs[1] and not objs[1].valid then
      objs = {}
      layer.objects, layer.last_w, layer.last_i, layer.last_p, layer.vis = objs, {}, {}, {}, nil
      layer.last_c = {}
      shown = 0
    end
    local last_w, last_i = layer.last_w, layer.last_i
    local side = layer.side
    if side then
      -- Side layers draw only the segments on their side of the beam (by z)
      -- and track each piece's visibility themselves; hidden pieces skip
      -- their position updates.
      local front = side == "front"
      local vis = layer.vis or {}
      layer.vis = vis
      for k = 1, n do
        local seg = segs[k]
        local want = ((seg.z or 1) >= 0) == front
        local obj = objs[k]
        if not obj then
          obj = create(r, layer, seg)
          objs[k] = obj
          last_w[k] = nil
          layer.last_p[k] = {}
          last_i[k] = seg.i or 1
          vis[k] = true
        end
        if vis[k] ~= want then
          obj.visible = want
          vis[k] = want
        end
        if want then place(r, layer, obj, seg, k) end
      end
      for k = n + 1, #objs do
        if vis[k] then
          objs[k].visible = false
          vis[k] = false
        end
      end
    else
      for k = 1, n do
        local obj = objs[k]
        if not obj then
          obj = create(r, layer, segs[k])
          objs[k] = obj
          last_w[k] = nil
          layer.last_p[k] = {}
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
  end
  r.shown = n
end

--- Draw a path. Points may carry .w and .i (width / intensity multipliers)
--- and .c (color; each segment takes its first point's color).
function R.set_path(r, points)
  local segs = {}
  for k = 1, #points - 1 do
    local a, b = points[k], points[k + 1]
    segs[k] = {
      a = a, b = b,
      w = ((a.w or 1) + (b.w or 1)) / 2,
      i = ((a.i or 1) + (b.i or 1)) / 2,
      c = a.c,
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
    layer.objects, layer.last_w, layer.last_i, layer.last_p, layer.vis = {}, {}, {}, {}, nil
    layer.last_c = {}
  end
  r.shown = 0
end

return R
