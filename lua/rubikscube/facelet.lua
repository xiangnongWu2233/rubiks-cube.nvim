-- Serialize a cube state to the 54-character facelet string expected by
-- Herbert Kociemba's two-phase solver (used by the `kociemba` CLI).
--
-- Format: nine facelets per face concatenated in URFDLB order. Each facelet
-- character is the letter of the face whose center holds that color in the
-- solved cube — so a solved cube becomes "U"*9 .. "R"*9 .. "F"*9 .. "D"*9 ..
-- "L"*9 .. "B"*9.
--
-- The plugin's internal indexing convention (see lua/rubikscube/cube.lua header)
-- matches kociemba's facelet layout, so within each face we just iterate 1..9.

local cube = require("rubikscube.cube")

local M = {}

-- Inverse of cube.SOLVED_COLORS: color letter → face letter.
-- Built once at module load — cube.SOLVED_COLORS is effectively immutable.
local COLOR_TO_FACE = {}
for face, color in pairs(cube.SOLVED_COLORS) do
  COLOR_TO_FACE[color] = face
end

-- kociemba's expected face order.
local FACE_ORDER = { "U", "R", "F", "D", "L", "B" }

function M.to_string(state)
  local parts = {}
  for _, face in ipairs(FACE_ORDER) do
    local arr = state[face]
    for i = 1, 9 do
      local color = arr[i]
      local letter = COLOR_TO_FACE[color]
      if not letter then
        error("facelet: unknown color " .. tostring(color) .. " at " .. face .. "[" .. i .. "]")
      end
      parts[#parts + 1] = letter
    end
  end
  return table.concat(parts)
end

return M
