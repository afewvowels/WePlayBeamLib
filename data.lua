-- Glow sprites used by ribbons. Grayscale on black + additive blending:
-- black adds nothing, and tints color them. 64x64 at scale 0.5 = 1x1 tile,
-- so x_scale / y_scale are simply length / width in tiles.

local function glow_sprite(name, file)
  return {
    type = "sprite",
    name = name,
    filename = "__WePlayBeamLib__/graphics/" .. file,
    width = 64,
    height = 64,
    scale = 0.5,
    blend_mode = "additive",
    draw_as_glow = true,
  }
end

data:extend{
  glow_sprite("wp-beamlib-soft", "soft.png"),  -- wide soft band, for outer glow
  glow_sprite("wp-beamlib-core", "core.png"),  -- tight bright band, for the core
  glow_sprite("wp-beamlib-dot", "dot.png"),    -- round glow, for tips and sparks
}
