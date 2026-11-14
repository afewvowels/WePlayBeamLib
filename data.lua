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

-- Solid band: white with soft alpha edges and normal blending, so it covers
-- what's behind it instead of adding light. Tint gives the color; ribbons
-- draw it fully opaque. Neighboring pieces overlap by 6% (ribbon.SOLID_OVERLAP);
-- the ends are feathered so two overlapping ends stack to exactly one piece's
-- opacity, which leaves no knobs at the joints.
local solid = glow_sprite("wp-beamlib-solid", "solid.png")
solid.blend_mode = "normal"

data:extend{
  solid,                                       -- opaque band, for solid cores and coils
  glow_sprite("wp-beamlib-soft", "soft.png"),  -- wide soft band, for outer glow
  glow_sprite("wp-beamlib-core", "core.png"),  -- tight bright band, for the core
  glow_sprite("wp-beamlib-dot", "dot.png"),    -- round glow, for tips and sparks
}
