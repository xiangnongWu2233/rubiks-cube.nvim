-- Rubik's cube state + moves. Pure data — no Neovim API dependencies.
--
-- Per-face indexing convention (head-on view, looking AT the face from outside the cube
-- with the cube held in the Western standard orientation: U=white on top, F=green in front):
--   index layout:  1 2 3
--                  4 5 6
--                  7 8 9
--   - U face viewed from above, with cube's BACK at top of view: U[1]=back-left, U[9]=front-right
--   - D face viewed from below, with cube's FRONT at top of view: D[1]=front-left, D[9]=back-right
--   - F face viewed from front, U-up: F[1]=upper-left, F[9]=lower-right
--   - B face viewed from behind, U-up: B[1]=upper-LEFT-of-view = upper-right-of-cube
--   - L face viewed from left, U-up: L[1]=upper-back of cube, L[3]=upper-front
--   - R face viewed from right, U-up: R[1]=upper-front of cube, R[3]=upper-back

local M = {}

M.SOLVED_COLORS = { U = "W", D = "Y", L = "O", R = "R", F = "G", B = "B" }
M.FACES = { "U", "D", "L", "R", "F", "B" }
M.FACE_TURNS = { "U", "D", "L", "R", "F", "B" }

-- Standard 3×3 row-major rotation permutations.
-- For rotate_cw: new[i] = old[CW[i]]. (new top-left = old bottom-left, etc.)
local CW = { 7, 4, 1, 8, 5, 2, 9, 6, 3 }
local CCW = { 3, 6, 9, 2, 5, 8, 1, 4, 7 }

local function permute(arr, perm)
  return {
    arr[perm[1]],
    arr[perm[2]],
    arr[perm[3]],
    arr[perm[4]],
    arr[perm[5]],
    arr[perm[6]],
    arr[perm[7]],
    arr[perm[8]],
    arr[perm[9]],
  }
end

local function copy9(a)
  return { a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9] }
end

function M.new()
  local s = {}
  for face, c in pairs(M.SOLVED_COLORS) do
    s[face] = { c, c, c, c, c, c, c, c, c }
  end
  return s
end

function M.copy(s)
  local out = {}
  for face, arr in pairs(s) do
    out[face] = copy9(arr)
  end
  return out
end

function M.is_solved(s)
  for face, c in pairs(M.SOLVED_COLORS) do
    local arr = s[face]
    for i = 1, 9 do
      if arr[i] ~= c then
        return false
      end
    end
  end
  return true
end

function M.equal(a, b)
  for _, face in ipairs(M.FACES) do
    local fa, fb = a[face], b[face]
    for i = 1, 9 do
      if fa[i] ~= fb[i] then
        return false
      end
    end
  end
  return true
end

-- Face turn definitions.
-- Each face turn rotates that face's stickers CW (new = permute(old, CW)),
-- and cycles four 3-sticker strips on neighbor faces in the order S1→S2→S3→S4→S1.
-- That is: after the move, S2 holds the OLD S1 values, S3 holds OLD S2, etc.
local FACE_TURNS = {
  U = {
    face = "U",
    strips = {
      { { "F", 1 }, { "F", 2 }, { "F", 3 } },
      { { "L", 1 }, { "L", 2 }, { "L", 3 } },
      { { "B", 1 }, { "B", 2 }, { "B", 3 } },
      { { "R", 1 }, { "R", 2 }, { "R", 3 } },
    },
  },
  D = {
    face = "D",
    strips = {
      { { "F", 7 }, { "F", 8 }, { "F", 9 } },
      { { "R", 7 }, { "R", 8 }, { "R", 9 } },
      { { "B", 7 }, { "B", 8 }, { "B", 9 } },
      { { "L", 7 }, { "L", 8 }, { "L", 9 } },
    },
  },
  R = {
    face = "R",
    strips = {
      { { "U", 3 }, { "U", 6 }, { "U", 9 } },
      { { "B", 7 }, { "B", 4 }, { "B", 1 } },
      { { "D", 3 }, { "D", 6 }, { "D", 9 } },
      { { "F", 3 }, { "F", 6 }, { "F", 9 } },
    },
  },
  L = {
    face = "L",
    strips = {
      { { "U", 1 }, { "U", 4 }, { "U", 7 } },
      { { "F", 1 }, { "F", 4 }, { "F", 7 } },
      { { "D", 1 }, { "D", 4 }, { "D", 7 } },
      { { "B", 9 }, { "B", 6 }, { "B", 3 } },
    },
  },
  F = {
    face = "F",
    strips = {
      { { "U", 9 }, { "U", 8 }, { "U", 7 } },
      { { "R", 7 }, { "R", 4 }, { "R", 1 } },
      { { "D", 1 }, { "D", 2 }, { "D", 3 } },
      { { "L", 3 }, { "L", 6 }, { "L", 9 } },
    },
  },
  B = {
    face = "B",
    strips = {
      { { "U", 1 }, { "U", 2 }, { "U", 3 } },
      { { "L", 7 }, { "L", 4 }, { "L", 1 } },
      { { "D", 9 }, { "D", 8 }, { "D", 7 } },
      { { "R", 3 }, { "R", 6 }, { "R", 9 } },
    },
  },
}

local function apply_face_turn_cw(s, def)
  s[def.face] = permute(s[def.face], CW)
  local strips = def.strips
  -- Save old strip 4 values (which will become new strip 1)
  local s1, s2, s3, s4 = strips[1], strips[2], strips[3], strips[4]
  local tmp = { s[s4[1][1]][s4[1][2]], s[s4[2][1]][s4[2][2]], s[s4[3][1]][s4[3][2]] }
  -- new S4 = old S3, new S3 = old S2, new S2 = old S1, new S1 = old S4
  for i = 1, 3 do
    s[s4[i][1]][s4[i][2]] = s[s3[i][1]][s3[i][2]]
    s[s3[i][1]][s3[i][2]] = s[s2[i][1]][s2[i][2]]
    s[s2[i][1]][s2[i][2]] = s[s1[i][1]][s1[i][2]]
    s[s1[i][1]][s1[i][2]] = tmp[i]
  end
end

-- Cube rotations.
-- y = whole-cube rotation around +y axis (CW from above), same direction as U turn.
-- x = whole-cube rotation around +x axis (CW from right), same direction as R turn.
-- z = whole-cube rotation around +z axis (CW from front), same direction as F turn.

local function apply_y(s)
  local U = permute(s.U, CW)
  local D = permute(s.D, CCW)
  local F = s.R
  local R = s.B
  local B = s.L
  local L = s.F
  s.U, s.D, s.F, s.R, s.B, s.L = U, D, F, R, B, L
end

local function reverse9(a)
  return { a[9], a[8], a[7], a[6], a[5], a[4], a[3], a[2], a[1] }
end

local function apply_x(s)
  local R = permute(s.R, CW)
  local L = permute(s.L, CCW)
  local U = s.F
  local F = s.D
  local D = reverse9(s.B)
  local B = reverse9(s.U)
  s.U, s.D, s.F, s.B, s.R, s.L = U, D, F, B, R, L
end

local function apply_z(s)
  -- Standard z (CW around F-axis, same direction as F-CW): face cycle U→R→D→L→U.
  local F = permute(s.F, CW)
  local B = permute(s.B, CCW)
  local U = permute(s.L, CW)
  local R = permute(s.U, CW)
  local D = permute(s.R, CW)
  local L = permute(s.D, CW)
  s.U, s.D, s.F, s.B, s.R, s.L = U, D, F, B, R, L
end

local FACE_TURN_FN = {}
for name, def in pairs(FACE_TURNS) do
  FACE_TURN_FN[name] = function(s)
    apply_face_turn_cw(s, def)
  end
end

local ROTATION_FN = { x = apply_x, y = apply_y, z = apply_z }

function M.apply(state, move)
  -- move is e.g. "U", "U'", "y", "y'"
  local base = move:gsub("'", "")
  local count = (move:find("'")) and 3 or 1
  local fn = FACE_TURN_FN[base] or ROTATION_FN[base]
  if not fn then
    error("unknown move: " .. tostring(move))
  end
  for _ = 1, count do
    fn(state)
  end
  return state
end

function M.reset(state)
  for face, c in pairs(M.SOLVED_COLORS) do
    local arr = state[face]
    for i = 1, 9 do
      arr[i] = c
    end
  end
  return state
end

function M.scramble(state, n, seed)
  n = n or 20
  if seed ~= nil then
    math.randomseed(seed)
  end
  local moves = {}
  for i = 1, n do
    local face = M.FACE_TURNS[math.random(1, 6)]
    local dir = math.random(1, 2) == 1 and "" or "'"
    local mv = face .. dir
    moves[i] = mv
    M.apply(state, mv)
  end
  return state, moves
end

return M
