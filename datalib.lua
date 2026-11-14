-- WePlay: Beam Library, data stage helpers.
--
-- In your mod's data.lua:
--   local beamdata = require("__WePlayBeamLib__/datalib")

local D = {}

local EMPTY = {
  filename = "__core__/graphics/empty.png",
  width = 1, height = 1, frame_count = 1,
}

--- Graphics for a beam that does damage but draws nothing (the visuals come
--- from a ribbon or from make_path_beams pieces instead).
function D.invisible_beam_graphics()
  return {
    beam = {
      head = table.deepcopy(EMPTY),
      tail = table.deepcopy(EMPTY),
      body = {table.deepcopy(EMPTY)},
    },
  }
end

--- Tesla-style visual beam pieces for beamlib.arcs.spawn. Creates four
--- prototypes so sparks only show at the real ends of a path:
---   <name>-first   start spark only      (first piece)
---   <name>         no sparks             (middle pieces)
---   <name>-last    ending spark only     (last piece)
---   <name>-single  both                  (path that is one piece)
--- def:
---   name                  required
---   head, body, tail      required beam animations
---   tail_last             optional tail for -last and -single instead of tail,
---                         e.g. a tip that fades out for a dead-end branch
---   start, ending         optional spark animations
---   width = 0.5
---   render_layer          optional
---   graphics_extra        optional fields merged into graphics_set
--- Returns the four prototypes; also extends data with them.
function D.make_path_beams(def)
  local function variant(suffix, with_start, with_end, last)
    local tail = (last and def.tail_last) or def.tail
    local graphics_set = {
      beam = {
        head = table.deepcopy(def.head),
        body = table.deepcopy(def.body),
        tail = table.deepcopy(tail),
        start = with_start and table.deepcopy(def.start) or nil,
        ending = with_end and table.deepcopy(def.ending) or nil,
        render_layer = def.render_layer,
      },
    }
    for k, v in pairs(def.graphics_extra or {}) do graphics_set[k] = table.deepcopy(v) end
    return {
      type = "beam",
      name = def.name .. suffix,
      flags = {"not-on-map"},
      hidden = true,
      width = def.width or 0.5,
      damage_interval = 1000000,
      graphics_set = graphics_set,
    }
  end
  local protos = {
    variant("-first", true, false, false),
    variant("", false, false, false),
    variant("-last", false, true, true),
    variant("-single", true, true, true),
  }
  data:extend(protos)
  return protos
end

local ANIMATION_KEYS = {"head", "tail", "tail_last", "start", "ending"}

local function each_animation(def, fn)
  for _, key in pairs(ANIMATION_KEYS) do
    if def[key] then fn(def[key]) end
  end
  if def.body then
    -- body is a single animation or a list of variations
    if def.body.filename or def.body.layers then fn(def.body) else
      for _, anim in pairs(def.body) do fn(anim) end
    end
  end
end

--- Tinted and/or speed variants of make_path_beams, all from the same sprite
--- sheets (tints are applied when drawing, so they cost no extra VRAM).
--- def: as make_path_beams, plus
---   tints = {name = color, ...}         optional; sets tint on every animation
---   speeds = {name = animation_speed}   optional; sets animation_speed on every animation
--- Names: <name>-<tint>-<speed> (then -first / -last / -single as usual);
--- with only tints or only speeds, <name>-<tint> or <name>-<speed>.
--- Returns all prototypes; also extends data with them.
function D.make_path_beam_variants(def)
  local tints = def.tints or {[""] = false}
  local speeds = def.speeds or {[""] = false}
  local all = {}
  for tint_name, tint in pairs(tints) do
    for speed_name, speed in pairs(speeds) do
      local v = table.deepcopy(def)
      v.tints, v.speeds = nil, nil
      local name = def.name
      if tint_name ~= "" then name = name .. "-" .. tint_name end
      if speed_name ~= "" then name = name .. "-" .. speed_name end
      v.name = name
      each_animation(v, function(anim)
        if tint then anim.tint = table.deepcopy(tint) end
        if speed then anim.animation_speed = speed end
      end)
      for _, p in pairs(D.make_path_beams(v)) do all[#all + 1] = p end
    end
  end
  return all
end

return D
