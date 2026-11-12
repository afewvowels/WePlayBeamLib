-- Ready-made looks. Each call returns fresh tables, so tweak freely:
--
--   local opts = beamlib.presets.proton()
--   opts.source, opts.target = player.character, enemy
--   opts.wander.amount = 2
--   local beam = beamlib.beam.new(opts)

local presets = {}

--- Ghostbusters-style stream: orange wandering beam with a thin blue
--- filament coiling around it.
function presets.proton()
  return {
    path = "wander",
    wander = {waypoints = 5, amount = 1.2, speed = 1, tip = 0.4},
    piece_length = 0.5,
    max_pieces = 24,
    grow_speed = 1.2,   -- shoots out over ~10 ticks on a 12-tile beam
    layers = {
      {width = 0.75, color = {r = 1, g = 0.38, b = 0.1}, intensity = 0.5, sprite = "wp-beamlib-soft"},
      {width = 0.22, color = {r = 1, g = 0.85, b = 0.65}, intensity = 1, sprite = "wp-beamlib-core"},
    },
    helix = {
      strands = 1, radius = 0.22, pitch = 1.4, spin = 2.5, step = 0.24, max_samples = 48,
      layers = {{width = 0.14, color = {r = 0.45, g = 0.65, b = 1}, intensity = 0.9, sprite = "wp-beamlib-core"}},
    },
    tip = {size = 1.0, color = {r = 1, g = 0.6, b = 0.3}, intensity = 0.8},
    light = {intensity = 0.7, scale = 1.5, color = {r = 1, g = 0.55, b = 0.25}},
    sparks = {
      -- a light accent: ~9 alive at a time, one layer each
      rate = 0.5, speed = 0.13, lift = 0.08, gravity = 0.009, life = 18, streak = 3.5, max = 16,
      layers = {
        {width = 0.13, color = {r = 1, g = 0.75, b = 0.4}, intensity = 1.5, sprite = "wp-beamlib-core"},
      },
    },
  }
end

--- Straight core with two depth-shaded strands spiraling around it.
function presets.helix()
  return {
    path = "straight",
    piece_length = 0.5,
    layers = {
      {width = 0.5, color = {r = 0.36, g = 0.79, b = 0.65}, intensity = 0.3, sprite = "wp-beamlib-soft"},
      {width = 0.1, color = {r = 0.88, g = 0.96, b = 0.93}, intensity = 0.9, sprite = "wp-beamlib-core"},
    },
    helix = {
      strands = 2, radius = 0.4, pitch = 1.4, spin = 1.2, step = 0.15,
      layers = {
        {width = 0.35, intensity = 0.45, sprite = "wp-beamlib-soft"},
        {width = 0.1, intensity = 1, sprite = "wp-beamlib-core"},
      },
      strand_colors = {{r = 0.36, g = 0.79, b = 0.65}, {r = 0.69, g = 0.66, b = 0.93}},
    },
    tip = {size = 0.8, color = {r = 0.6, g = 0.95, b = 0.85}, intensity = 0.7},
    light = {intensity = 0.5, scale = 1.2, color = {r = 0.4, g = 0.9, b = 0.8}},
  }
end

--- The Tesla bolt look, drawn with ribbons instead of beam entities
--- (re-rolls every 6 ticks, bowed spans between sharp corners).
--- Set path = "smooth" for the flowing, whip-like version.
function presets.lightning()
  return {
    path = "arcs",
    repath_ticks = 6,
    jagged = {segment_length = 1.6, jitter = 1, max_corners = 6, swing = 0.3, max_swing = 2.5},
    piece_length = 0.3,
    layers = {
      {width = 0.6, color = {r = 0.45, g = 0.6, b = 1}, intensity = 0.55, sprite = "wp-beamlib-soft"},
      {width = 0.12, color = {r = 0.9, g = 0.95, b = 1}, intensity = 1, sprite = "wp-beamlib-core"},
    },
    tip = {size = 0.9, color = {r = 0.7, g = 0.8, b = 1}, intensity = 0.8},
  }
end

return presets
