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
---   start, ending         optional spark animations
---   width = 0.5
---   render_layer          optional
---   graphics_extra        optional fields merged into graphics_set
--- Returns the four prototypes; also extends data with them.
function D.make_path_beams(def)
  local function variant(suffix, with_start, with_end)
    local graphics_set = {
      beam = {
        head = table.deepcopy(def.head),
        body = table.deepcopy(def.body),
        tail = table.deepcopy(def.tail),
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
    variant("-first", true, false),
    variant("", false, false),
    variant("-last", false, true),
    variant("-single", true, true),
  }
  data:extend(protos)
  return protos
end

return D
