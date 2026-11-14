-- Tesla-style drawing: one short-lived visual beam entity per path piece.
--
-- Use datalib.make_path_beams in data.lua to create the four prototypes
-- (<name>-first, <name>, <name>-last, <name>-single), so start sparks only
-- appear at the shooter and ending sparks only at the target.
--
-- Best for paths that re-roll every few ticks (lightning). For paths that
-- move every tick, use a ribbon instead.

local A = {}

local function piece_name(prefix, k, n)
  if n == 1 then return prefix .. "-single" end
  if k == 1 then return prefix .. "-first" end
  if k == n then return prefix .. "-last" end
  return prefix
end

--- Spawns pieces along points. They vanish on their own after `duration` ticks.
---   surface, prefix: the name given to make_path_beams
---   points: from any path function
---   duration: ticks, e.g. the re-roll interval so the next set replaces this one
---   max_length: optional, passed to create_entity (pieces vanish if their ends
---               get further apart than this)
function A.spawn(surface, prefix, points, duration, max_length)
  local n = #points - 1
  for k = 1, n do
    surface.create_entity{
      name = piece_name(prefix, k, n),
      position = points[k],
      source_position = points[k],
      target_position = points[k + 1],
      duration = duration,
      max_length = max_length,
    }
  end
end

return A
