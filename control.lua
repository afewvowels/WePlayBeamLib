-- The library itself only adds a preview command. Other mods require
-- beamlib.lua directly and run everything inside their own scripts.
--
--   /beamlib-demo proton      wandering stream with a coiled filament
--   /beamlib-demo wander      wandering stream only
--   /beamlib-demo helix       straight core with two spiraling strands
--   /beamlib-demo lightning   Tesla-style jagged smooth path
--   /beamlib-demo off
--
-- The beam goes from your shoulders to whatever you're hovering over when
-- you run the command, or to a spot 10 tiles to your right if nothing.

local beamlib = require("__WePlayBeamLib__/beamlib")
local presets = beamlib.presets

local MODES = {
  proton = presets.proton,
  helix = presets.helix,
  lightning = presets.lightning,
  wander = function()
    local o = presets.proton()
    o.helix = nil
    return o
  end,
}

local on_tick

local function sync()
  if storage.demos and next(storage.demos) then
    script.on_event(defines.events.on_tick, on_tick)
  else
    script.on_event(defines.events.on_tick, nil)
  end
end

on_tick = function(event)
  for index, beam in pairs(storage.demos) do
    local alive, source_ok = beamlib.beam.update(beam, event.tick)
    if not (alive and source_ok) then
      beamlib.beam.destroy(beam)
      storage.demos[index] = nil
    end
  end
  if not next(storage.demos) then sync() end
end

commands.add_command("beamlib-demo",
  "<proton|wander|helix|lightning|off> - preview a beam from you to the entity under your cursor.",
  function(cmd)
    local player = cmd.player_index and game.get_player(cmd.player_index)
    if not player then return end
    local mode = (cmd.parameter or "proton"):lower():gsub("%s+", "")
    if mode == "" then mode = "proton" end

    local old = storage.demos[player.index]
    if old then
      beamlib.beam.destroy(old)
      storage.demos[player.index] = nil
    end
    if mode == "off" then
      sync()
      return
    end

    local make = MODES[mode]
    if not make then
      player.print("Unknown beam '" .. mode .. "'. Try proton, wander, helix, lightning or off.")
      sync()
      return
    end
    local character = player.character
    if not (character and character.valid) then
      player.print("The demo needs a character to shoot from.")
      sync()
      return
    end

    local opts = make()
    opts.surface = character.surface
    opts.source = character
    opts.source_offset = {0, -1.3}
    local selected = player.selected
    if selected and selected.valid and selected.surface == character.surface and selected ~= character then
      opts.target = selected
    else
      local p = character.position
      opts.target = {x = p.x + 10, y = p.y}
    end
    storage.demos[player.index] = beamlib.beam.new(opts)
    sync()
  end
)

script.on_init(function()
  storage.demos = {}
end)

script.on_configuration_changed(function()
  storage.demos = storage.demos or {}
  sync()
end)

script.on_load(sync)
