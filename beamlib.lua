-- WePlay: Beam Library, runtime entry point.
--
-- In your mod's control.lua:
--   local beamlib = require("__WePlayBeamLib__/beamlib")
--
-- Everything runs inside your own mod: your beams, your storage, your
-- on_tick. The library has no runtime state of its own.

return {
  version = "0.6.1",
  vec = require("__WePlayBeamLib__/lib/vec"),
  path = require("__WePlayBeamLib__/lib/path"),
  wander = require("__WePlayBeamLib__/lib/wander"),
  helix = require("__WePlayBeamLib__/lib/helix"),
  sparks = require("__WePlayBeamLib__/lib/sparks"),
  ribbon = require("__WePlayBeamLib__/lib/ribbon"),
  arcs = require("__WePlayBeamLib__/lib/arcs"),
  beam = require("__WePlayBeamLib__/lib/beam"),
  presets = require("__WePlayBeamLib__/lib/presets"),
}
