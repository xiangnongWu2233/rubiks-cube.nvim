local T = require("test_helper")
local cube = require("rubikscube.cube")

-- ============ Task 2: solved state ============

T.test("solved cube: every sticker matches its center color", function()
  local s = cube.new()
  for _, face in ipairs(cube.FACES) do
    for i = 1, 9 do
      T.eq(s[face][i], cube.SOLVED_COLORS[face], face .. "[" .. i .. "]")
    end
  end
end)

T.test("solved cube centers: Western standard", function()
  local s = cube.new()
  T.eq(s.U[5], "W", "U center")
  T.eq(s.D[5], "Y", "D center")
  T.eq(s.F[5], "G", "F center")
  T.eq(s.B[5], "B", "B center")
  T.eq(s.L[5], "O", "L center")
  T.eq(s.R[5], "R", "R center")
end)

T.test("is_solved: true on fresh cube, false after one sticker change", function()
  local s = cube.new()
  T.truthy(cube.is_solved(s))
  s.U[1] = "Y"
  T.falsy(cube.is_solved(s))
end)

T.test("copy yields independent state", function()
  local s = cube.new()
  local c = cube.copy(s)
  c.U[1] = "X"
  T.eq(s.U[1], "W")
  T.eq(c.U[1], "X")
end)

T.test("equal: identifies identical states", function()
  T.truthy(cube.equal(cube.new(), cube.new()))
  local s = cube.new()
  s.U[1] = "X"
  T.falsy(cube.equal(s, cube.new()))
end)

-- ============ Task 3: face turns ============

-- Helper: applies a sequence of moves to a fresh cube
local function play(moves)
  local s = cube.new()
  for _, m in ipairs(moves) do
    cube.apply(s, m)
  end
  return s
end

-- The canonical post-U-turn state (derived in design):
-- After U: F-top row gets what was on R-top, R-top gets B-top, B-top gets L-top, L-top gets F-top.
-- (F→L→B→R→F cycle of top rows; so new F = old R, new R = old B, new B = old L, new L = old F.)
T.test("U: top rows cycle F→L→B→R→F (new F-top = old R-top etc)", function()
  local s = play({ "U" })
  T.eq(s.F[1], "R")
  T.eq(s.F[2], "R")
  T.eq(s.F[3], "R")
  T.eq(s.R[1], "B")
  T.eq(s.R[2], "B")
  T.eq(s.R[3], "B")
  T.eq(s.B[1], "O")
  T.eq(s.B[2], "O")
  T.eq(s.B[3], "O")
  T.eq(s.L[1], "G")
  T.eq(s.L[2], "G")
  T.eq(s.L[3], "G")
  -- U face itself: rotated CW in place — still all white
  for i = 1, 9 do
    T.eq(s.U[i], "W", "U[" .. i .. "]")
  end
  -- Bottom rows unchanged
  T.eq(s.F[7], "G")
  T.eq(s.F[8], "G")
  T.eq(s.F[9], "G")
end)

T.test("D: bottom rows cycle F→R→B→L→F", function()
  local s = play({ "D" })
  T.eq(s.F[7], "O")
  T.eq(s.F[8], "O")
  T.eq(s.F[9], "O")
  T.eq(s.R[7], "G")
  T.eq(s.R[8], "G")
  T.eq(s.R[9], "G")
  T.eq(s.B[7], "R")
  T.eq(s.B[8], "R")
  T.eq(s.B[9], "R")
  T.eq(s.L[7], "B")
  T.eq(s.L[8], "B")
  T.eq(s.L[9], "B")
  for i = 1, 9 do
    T.eq(s.D[i], "Y", "D[" .. i .. "]")
  end
end)

T.test("R: U-right gets old F-right, F-right gets old D-right, etc.", function()
  -- R cycle (per design): U[3,6,9] → B[7,4,1] → D[3,6,9] → F[3,6,9] → U[3,6,9]
  -- After R: new F[3,6,9] = old D[3,6,9] = Y,Y,Y
  --          new U[3,6,9] = old F[3,6,9] = G,G,G
  --          new B[7,4,1] = old U[3,6,9] = W,W,W
  --          new D[3,6,9] = old B[7,4,1] = B,B,B
  local s = play({ "R" })
  T.eq(s.U[3], "G")
  T.eq(s.U[6], "G")
  T.eq(s.U[9], "G")
  T.eq(s.F[3], "Y")
  T.eq(s.F[6], "Y")
  T.eq(s.F[9], "Y")
  T.eq(s.D[3], "B")
  T.eq(s.D[6], "B")
  T.eq(s.D[9], "B")
  T.eq(s.B[7], "W")
  T.eq(s.B[4], "W")
  T.eq(s.B[1], "W")
  for i = 1, 9 do
    T.eq(s.R[i], "R")
  end
end)

T.test("L: U[1,4,7]→F[1,4,7]→D[1,4,7]→B[9,6,3]→U[1,4,7]", function()
  local s = play({ "L" })
  -- new F[1,4,7] = old U[1,4,7] = W,W,W
  -- new D[1,4,7] = old F[1,4,7] = G,G,G
  -- new B[9,6,3] = old D[1,4,7] = Y,Y,Y
  -- new U[1,4,7] = old B[9,6,3] = B,B,B
  T.eq(s.F[1], "W")
  T.eq(s.F[4], "W")
  T.eq(s.F[7], "W")
  T.eq(s.D[1], "G")
  T.eq(s.D[4], "G")
  T.eq(s.D[7], "G")
  T.eq(s.B[9], "Y")
  T.eq(s.B[6], "Y")
  T.eq(s.B[3], "Y")
  T.eq(s.U[1], "B")
  T.eq(s.U[4], "B")
  T.eq(s.U[7], "B")
  for i = 1, 9 do
    T.eq(s.L[i], "O")
  end
end)

T.test("F: U[9,8,7]→R[7,4,1]→D[1,2,3]→L[3,6,9]→U[9,8,7]", function()
  local s = play({ "F" })
  -- new R[7,4,1] = old U[9,8,7] = W,W,W
  -- new D[1,2,3] = old R[7,4,1] = R,R,R
  -- new L[3,6,9] = old D[1,2,3] = Y,Y,Y
  -- new U[9,8,7] = old L[3,6,9] = O,O,O
  T.eq(s.R[7], "W")
  T.eq(s.R[4], "W")
  T.eq(s.R[1], "W")
  T.eq(s.D[1], "R")
  T.eq(s.D[2], "R")
  T.eq(s.D[3], "R")
  T.eq(s.L[3], "Y")
  T.eq(s.L[6], "Y")
  T.eq(s.L[9], "Y")
  T.eq(s.U[9], "O")
  T.eq(s.U[8], "O")
  T.eq(s.U[7], "O")
  for i = 1, 9 do
    T.eq(s.F[i], "G")
  end
end)

T.test("B: U[1,2,3]→L[7,4,1]→D[9,8,7]→R[3,6,9]→U[1,2,3]", function()
  local s = play({ "B" })
  -- new L[7,4,1] = old U[1,2,3] = W,W,W
  -- new D[9,8,7] = old L[7,4,1] = O,O,O
  -- new R[3,6,9] = old D[9,8,7] = Y,Y,Y
  -- new U[1,2,3] = old R[3,6,9] = R,R,R
  T.eq(s.L[7], "W")
  T.eq(s.L[4], "W")
  T.eq(s.L[1], "W")
  T.eq(s.D[9], "O")
  T.eq(s.D[8], "O")
  T.eq(s.D[7], "O")
  T.eq(s.R[3], "Y")
  T.eq(s.R[6], "Y")
  T.eq(s.R[9], "Y")
  T.eq(s.U[1], "R")
  T.eq(s.U[2], "R")
  T.eq(s.U[3], "R")
  for i = 1, 9 do
    T.eq(s.B[i], "B")
  end
end)

-- 4x identity for every face turn
for _, face in ipairs({ "U", "D", "L", "R", "F", "B" }) do
  T.test(face .. " applied 4 times returns to solved", function()
    local s = play({ face, face, face, face })
    T.truthy(cube.is_solved(s), "after " .. face .. "^4")
  end)
  T.test(face .. " then " .. face .. "' returns to solved", function()
    local s = play({ face, face .. "'" })
    T.truthy(cube.is_solved(s))
  end)
  T.test(face .. " applied 3 times equals " .. face .. "'", function()
    local s1 = play({ face, face, face })
    local s2 = play({ face .. "'" })
    T.truthy(cube.equal(s1, s2))
  end)
end

-- ============ Task 4: cube rotations x/y/z ============

T.test("y rotation: centers permute F→L→B→R→F (face labels follow)", function()
  -- y = CW from above. After y, the face that USED to be at R is now labeled F.
  -- So new F[5] = old R[5] = "R" (red).
  local s = cube.new()
  cube.apply(s, "y")
  T.eq(s.U[5], "W")
  T.eq(s.D[5], "Y")
  T.eq(s.F[5], "R")
  T.eq(s.R[5], "B")
  T.eq(s.B[5], "O")
  T.eq(s.L[5], "G")
end)

T.test("x rotation: face cycle U→B→D→F→U", function()
  -- x = CW around R-axis. After x, F goes up: new U = old F.
  local s = cube.new()
  cube.apply(s, "x")
  T.eq(s.U[5], "G") -- old F
  T.eq(s.F[5], "Y") -- old D
  T.eq(s.D[5], "B") -- old B
  T.eq(s.B[5], "W") -- old U
  T.eq(s.R[5], "R")
  T.eq(s.L[5], "O")
end)

T.test("z rotation: face cycle U→R→D→L→U", function()
  -- z = CW around F-axis (same direction as F-CW). Under z, the L-face moves
  -- up into the U-slot, so new U = old L.
  local s = cube.new()
  cube.apply(s, "z")
  T.eq(s.U[5], "O") -- old L
  T.eq(s.R[5], "W") -- old U
  T.eq(s.D[5], "R") -- old R
  T.eq(s.L[5], "Y") -- old D
  T.eq(s.F[5], "G")
  T.eq(s.B[5], "B")
end)

T.test("y4, x4, z4 each return to solved", function()
  for _, r in ipairs({ "x", "y", "z" }) do
    local s = cube.new()
    for _ = 1, 4 do
      cube.apply(s, r)
    end
    T.truthy(cube.is_solved(s), r .. "^4")
  end
end)

T.test("y y' is identity after scramble", function()
  local s = cube.new()
  cube.apply(s, "R")
  cube.apply(s, "U")
  cube.apply(s, "F'")
  local before = cube.copy(s)
  cube.apply(s, "y")
  cube.apply(s, "y'")
  T.truthy(cube.equal(s, before))
end)

T.test("x x' is identity after scramble", function()
  local s = cube.new()
  cube.apply(s, "R")
  cube.apply(s, "U")
  cube.apply(s, "F'")
  local before = cube.copy(s)
  cube.apply(s, "x")
  cube.apply(s, "x'")
  T.truthy(cube.equal(s, before))
end)

T.test("z z' is identity after scramble", function()
  local s = cube.new()
  cube.apply(s, "R")
  cube.apply(s, "U")
  cube.apply(s, "F'")
  local before = cube.copy(s)
  cube.apply(s, "z")
  cube.apply(s, "z'")
  T.truthy(cube.equal(s, before))
end)

-- Sune algorithm sanity: (R U R' U R U2 R')^3 should solve a Sune-permuted state.
T.test("Sune algorithm has order 6", function()
  -- Sune algorithm: R U R' U R U U R'
  local function sune(s)
    cube.apply(s, "R")
    cube.apply(s, "U")
    cube.apply(s, "R'")
    cube.apply(s, "U")
    cube.apply(s, "R")
    cube.apply(s, "U")
    cube.apply(s, "U")
    cube.apply(s, "R'")
  end
  local s = cube.new()
  for _ = 1, 6 do
    sune(s)
  end
  T.truthy(cube.is_solved(s), "Sune^6 should solve")
end)

T.test("conjugation: y R y' equals B", function()
  -- y conjugates a face turn by mapping its axis under y'. y' sends +x to -z,
  -- so y R y' acts on the B-layer in the same rotational sense as R.
  -- Trace: UBR --y--> UFR --R--> UBR --y'--> UBL, which is exactly B-CW.
  local a = cube.new()
  cube.apply(a, "y")
  cube.apply(a, "R")
  cube.apply(a, "y'")
  local b = cube.new()
  cube.apply(b, "B")
  T.truthy(cube.equal(a, b), "y R y' should equal B")
end)

T.test("conjugation: x R x' equals R (x preserves R-axis)", function()
  local a = cube.new()
  cube.apply(a, "x")
  cube.apply(a, "R")
  cube.apply(a, "x'")
  local b = cube.new()
  cube.apply(b, "R")
  T.truthy(cube.equal(a, b))
end)

-- ============ Task 5: scramble + reset ============

T.test("reset on scrambled cube yields solved state", function()
  local s = cube.new()
  cube.scramble(s, 30, 42)
  T.falsy(cube.is_solved(s))
  cube.reset(s)
  T.truthy(cube.is_solved(s))
end)

T.test("scramble with same seed is reproducible", function()
  local a = cube.new()
  cube.scramble(a, 20, 7)
  local b = cube.new()
  cube.scramble(b, 20, 7)
  T.truthy(cube.equal(a, b))
end)

T.test("scramble with different seeds differs", function()
  local a = cube.new()
  cube.scramble(a, 20, 1)
  local b = cube.new()
  cube.scramble(b, 20, 2)
  T.falsy(cube.equal(a, b))
end)

T.test("scramble produces unsolved state", function()
  local s = cube.new()
  cube.scramble(s, 20, 13)
  T.falsy(cube.is_solved(s))
end)

T.test("scramble returns move list of correct length", function()
  local s = cube.new()
  local _, moves = cube.scramble(s, 17, 99)
  T.eq(#moves, 17)
end)

-- ============ Task 6: combined controls — cubie validity ============
--
-- A "valid" cube state has each cubie appear exactly once: 12 edges with distinct
-- {color, color} pairs and 8 corners with distinct {color, color, color} triples.
-- Single moves preserve cubie validity, so any composition must too. These tests
-- caught a bug where F and B's strip cycles disagreed with their face rotation
-- direction — single moves looked fine, but any composition silently corrupted
-- the state.

local EDGES = {
  UF = { { "U", 8 }, { "F", 2 } },
  UR = { { "U", 6 }, { "R", 2 } },
  UB = { { "U", 2 }, { "B", 2 } },
  UL = { { "U", 4 }, { "L", 2 } },
  FR = { { "F", 6 }, { "R", 4 } },
  FL = { { "F", 4 }, { "L", 6 } },
  BR = { { "B", 4 }, { "R", 6 } },
  BL = { { "B", 6 }, { "L", 4 } },
  DF = { { "D", 2 }, { "F", 8 } },
  DR = { { "D", 6 }, { "R", 8 } },
  DB = { { "D", 8 }, { "B", 8 } },
  DL = { { "D", 4 }, { "L", 8 } },
}
local CORNERS = {
  UFR = { { "U", 9 }, { "F", 3 }, { "R", 1 } },
  UFL = { { "U", 7 }, { "F", 1 }, { "L", 3 } },
  UBR = { { "U", 3 }, { "B", 1 }, { "R", 3 } },
  UBL = { { "U", 1 }, { "B", 3 }, { "L", 1 } },
  DFR = { { "D", 3 }, { "F", 9 }, { "R", 7 } },
  DFL = { { "D", 1 }, { "F", 7 }, { "L", 9 } },
  DBR = { { "D", 9 }, { "B", 7 }, { "R", 9 } },
  DBL = { { "D", 7 }, { "B", 9 }, { "L", 7 } },
}

local function color_key(s, stkrs)
  local cs = {}
  for _, p in ipairs(stkrs) do
    cs[#cs + 1] = s[p[1]][p[2]]
  end
  table.sort(cs)
  return table.concat(cs)
end

-- Returns (true) for a valid state, or (false, description) on the first duplicate.
local function is_valid_cube(s)
  local seen = {}
  for name, stkrs in pairs(EDGES) do
    local k = color_key(s, stkrs)
    if seen[k] then
      return false, "edge " .. name .. " duplicates " .. seen[k] .. " (" .. k .. ")"
    end
    seen[k] = name
  end
  seen = {}
  for name, stkrs in pairs(CORNERS) do
    local k = color_key(s, stkrs)
    if seen[k] then
      return false, "corner " .. name .. " duplicates " .. seen[k] .. " (" .. k .. ")"
    end
    seen[k] = name
  end
  return true
end

local FACE_MOVES = { "U", "D", "L", "R", "F", "B", "U'", "D'", "L'", "R'", "F'", "B'" }

T.test("validity helper: solved cube is valid", function()
  T.truthy(is_valid_cube(cube.new()))
end)

T.test("validity helper: a hand-corrupted cube is detected", function()
  local s = cube.new()
  s.F[2] = "O" -- UF edge becomes {W, O}, colliding with UL ({W, O})
  local ok, err = is_valid_cube(s)
  T.falsy(ok)
  T.truthy(
    err and (err:find("UF") or err:find("UL")),
    "should name the duplicate, got: " .. tostring(err)
  )
end)

T.test("every single face turn from solved keeps the cube valid", function()
  for _, m in ipairs(FACE_MOVES) do
    local s = cube.new()
    cube.apply(s, m)
    local ok, err = is_valid_cube(s)
    T.truthy(ok, "after " .. m .. ": " .. (err or ""))
  end
end)

T.test("every 2-move composition from solved keeps the cube valid", function()
  -- 12 × 12 = 144 pairs. A directional bug in any face turn shows up here.
  for _, m1 in ipairs(FACE_MOVES) do
    for _, m2 in ipairs(FACE_MOVES) do
      local s = cube.new()
      cube.apply(s, m1)
      cube.apply(s, m2)
      local ok, err = is_valid_cube(s)
      T.truthy(ok, m1 .. " " .. m2 .. ": " .. (err or ""))
    end
  end
end)

T.test("scrambles of various seeds and lengths stay valid", function()
  for seed = 1, 20 do
    for _, n in ipairs({ 5, 10, 20, 50 }) do
      local s = cube.new()
      cube.scramble(s, n, seed)
      local ok, err = is_valid_cube(s)
      T.truthy(ok, "seed=" .. seed .. " n=" .. n .. ": " .. (err or ""))
    end
  end
end)

T.test("rotation then face turn stays valid", function()
  for _, rot in ipairs({ "x", "y", "z", "x'", "y'", "z'" }) do
    for _, m in ipairs(FACE_MOVES) do
      local s = cube.new()
      cube.apply(s, rot)
      cube.apply(s, m)
      local ok, err = is_valid_cube(s)
      T.truthy(ok, rot .. " " .. m .. ": " .. (err or ""))
    end
  end
end)

-- ============ Task 6: combined controls — algorithm identities ============

T.test("sexy move (R U R' U')^6 = identity", function()
  local s = cube.new()
  for _ = 1, 6 do
    cube.apply(s, "R")
    cube.apply(s, "U")
    cube.apply(s, "R'")
    cube.apply(s, "U'")
  end
  T.truthy(cube.is_solved(s))
end)

T.test("T-perm applied twice from solved returns to solved (self-inverse)", function()
  -- T-perm: R U R' U' R' F R2 U' R' U' R U R' F'
  local function tperm(s)
    local moves = {
      "R",
      "U",
      "R'",
      "U'",
      "R'",
      "F",
      "R",
      "R",
      "U'",
      "R'",
      "U'",
      "R",
      "U",
      "R'",
      "F'",
    }
    for _, m in ipairs(moves) do
      cube.apply(s, m)
    end
  end
  local s = cube.new()
  tperm(s)
  tperm(s)
  T.truthy(cube.is_solved(s), "T-perm * T-perm should solve")
end)

T.test("scramble + reversed inverse returns to solved", function()
  local INV = {
    U = "U'",
    D = "D'",
    L = "L'",
    R = "R'",
    F = "F'",
    B = "B'",
    ["U'"] = "U",
    ["D'"] = "D",
    ["L'"] = "L",
    ["R'"] = "R",
    ["F'"] = "F",
    ["B'"] = "B",
  }
  for seed = 1, 10 do
    local s = cube.new()
    local _, moves = cube.scramble(s, 20, seed)
    for i = #moves, 1, -1 do
      cube.apply(s, INV[moves[i]])
    end
    T.truthy(cube.is_solved(s), "seed=" .. seed .. " not solved after inverse")
  end
end)

-- ============ Task 6: combined controls — conjugation identities ============
--
-- Rotating the cube, performing a face turn, then un-rotating must produce the
-- same effect as some single face turn. These hold only when y/x/z and the face
-- turns are all in the standard Singmaster direction.

local function eq_after(a, b)
  local sa = cube.new()
  for _, m in ipairs(a) do
    cube.apply(sa, m)
  end
  local sb = cube.new()
  for _, m in ipairs(b) do
    cube.apply(sb, m)
  end
  return cube.equal(sa, sb)
end

T.test("conjugation: x F x' = D", function()
  T.truthy(eq_after({ "x", "F", "x'" }, { "D" }))
end)

T.test("conjugation: z U z' = L", function()
  T.truthy(eq_after({ "z", "U", "z'" }, { "L" }))
end)

T.test("conjugation: y F y' = R", function()
  T.truthy(eq_after({ "y", "F", "y'" }, { "R" }))
end)

T.test("invariance: x R x' = R (x preserves the R-axis)", function()
  T.truthy(eq_after({ "x", "R", "x'" }, { "R" }))
end)

T.test("invariance: y U y' = U (y preserves the U-axis)", function()
  T.truthy(eq_after({ "y", "U", "y'" }, { "U" }))
end)

T.test("invariance: z F z' = F (z preserves the F-axis)", function()
  T.truthy(eq_after({ "z", "F", "z'" }, { "F" }))
end)

-- ============ Task 7: invariants and group properties ============

local function snapshot_state(s)
  local out = {}
  for _, f in ipairs(cube.FACES) do
    for i = 1, 9 do
      out[#out + 1] = s[f][i]
    end
  end
  return table.concat(out)
end

T.test("color count: each of W/Y/O/R/G/B appears exactly 9 times after any scramble", function()
  for seed = 1, 10 do
    local s = cube.new()
    cube.scramble(s, 30, seed)
    local counts = { W = 0, Y = 0, O = 0, R = 0, G = 0, B = 0 }
    for _, face in ipairs(cube.FACES) do
      for i = 1, 9 do
        counts[s[face][i]] = (counts[s[face][i]] or 0) + 1
      end
    end
    for c, n in pairs(counts) do
      T.eq(n, 9, "seed=" .. seed .. " color " .. c .. " count")
    end
  end
end)

T.test("face turns preserve centers", function()
  for _, m in ipairs({ "U", "D", "L", "R", "F", "B", "U'", "D'", "L'", "R'", "F'", "B'" }) do
    local s = cube.new()
    cube.apply(s, m)
    T.eq(s.U[5], "W")
    T.eq(s.D[5], "Y")
    T.eq(s.F[5], "G")
    T.eq(s.B[5], "B")
    T.eq(s.L[5], "O")
    T.eq(s.R[5], "R")
  end
end)

T.test("composed face turns preserve centers across any scramble", function()
  for seed = 1, 10 do
    local s = cube.new()
    cube.scramble(s, 20, seed)
    T.eq(s.U[5], "W")
    T.eq(s.D[5], "Y")
    T.eq(s.F[5], "G")
    T.eq(s.B[5], "B")
    T.eq(s.L[5], "O")
    T.eq(s.R[5], "R")
  end
end)

T.test("whole-cube rotations DO move centers", function()
  for _, r in ipairs({ "x", "y", "z" }) do
    local s = cube.new()
    cube.apply(s, r)
    local moved = (s.U[5] ~= "W") or (s.F[5] ~= "G") or (s.R[5] ~= "R")
    T.truthy(moved, r .. " should permute centers")
  end
end)

T.test("each face turn leaves the opposite face untouched", function()
  local OPP = { U = "D", D = "U", L = "R", R = "L", F = "B", B = "F" }
  for face, opp in pairs(OPP) do
    for _, suffix in ipairs({ "", "'" }) do
      local s = cube.new()
      cube.apply(s, face .. suffix)
      for i = 1, 9 do
        T.eq(
          s[opp][i],
          cube.SOLVED_COLORS[opp],
          "after " .. face .. suffix .. ", " .. opp .. "[" .. i .. "]"
        )
      end
    end
  end
end)

T.test("12 single face turns from solved produce 12 distinct states", function()
  local moves = { "U", "D", "L", "R", "F", "B", "U'", "D'", "L'", "R'", "F'", "B'" }
  local seen = {}
  for _, m in ipairs(moves) do
    local s = cube.new()
    cube.apply(s, m)
    local key = snapshot_state(s)
    T.falsy(seen[key], m .. " produces same state as " .. tostring(seen[key]))
    seen[key] = m
  end
end)

T.test("U + U is different from U; U + U + U equals U'", function()
  local a = cube.new()
  cube.apply(a, "U")
  cube.apply(a, "U")
  local b = cube.new()
  cube.apply(b, "U")
  T.falsy(cube.equal(a, b), "U^2 should not equal U")

  local c = cube.new()
  cube.apply(c, "U")
  cube.apply(c, "U")
  cube.apply(c, "U")
  local d = cube.new()
  cube.apply(d, "U'")
  T.truthy(cube.equal(c, d), "U^3 should equal U'")
end)

T.test("cube.equal is reflexive and symmetric", function()
  local s1 = cube.new()
  cube.scramble(s1, 15, 11)
  local s2 = cube.copy(s1)
  T.truthy(cube.equal(s1, s1), "reflexive")
  T.truthy(cube.equal(s1, s2), "equal to its copy")
  T.truthy(cube.equal(s2, s1), "symmetric")
end)

T.test("cube.apply errors on unknown move tokens", function()
  T.falsy(pcall(cube.apply, cube.new(), "Q"))
  T.falsy(pcall(cube.apply, cube.new(), "U2"))
  T.falsy(pcall(cube.apply, cube.new(), ""))
  T.falsy(pcall(cube.apply, cube.new(), "u")) -- lowercase is a key, not a move name
end)

T.test("cube.copy is fully independent (deep copy)", function()
  local s = cube.new()
  cube.scramble(s, 10, 3)
  local c = cube.copy(s)
  cube.apply(s, "U")
  cube.apply(s, "R")
  -- After mutating s, c must be unchanged.
  local fresh = cube.new()
  cube.scramble(fresh, 10, 3)
  T.truthy(cube.equal(c, fresh), "copy unchanged by mutation of source")
end)

-- ============ Task 7: algorithm orders ============

T.test("commutator [F, R] = F R F' R' has order 6", function()
  local s = cube.new()
  for _ = 1, 6 do
    cube.apply(s, "F")
    cube.apply(s, "R")
    cube.apply(s, "F'")
    cube.apply(s, "R'")
  end
  T.truthy(cube.is_solved(s), "[F, R]^6 should solve")
end)

T.test("commutator [F, R] does NOT solve in fewer than 6 applications", function()
  for n = 1, 5 do
    local s = cube.new()
    for _ = 1, n do
      cube.apply(s, "F")
      cube.apply(s, "R")
      cube.apply(s, "F'")
      cube.apply(s, "R'")
    end
    T.falsy(cube.is_solved(s), "[F, R]^" .. n .. " should NOT be identity")
  end
end)

T.test("(R U) has order 105 — (R U)^105 = identity", function()
  local s = cube.new()
  for _ = 1, 105 do
    cube.apply(s, "R")
    cube.apply(s, "U")
  end
  T.truthy(cube.is_solved(s))
end)

T.test("(R U) does NOT solve before 105 iterations (sample 1..104)", function()
  -- Spot-check a few intermediate counts — if any one lands on solved, the
  -- order would have to be a proper divisor of 105 (= 3 × 5 × 7).
  local s = cube.new()
  for n = 1, 104 do
    cube.apply(s, "R")
    cube.apply(s, "U")
    T.falsy(cube.is_solved(s), "(R U)^" .. n .. " should not be solved")
  end
end)

T.test("U-perm (R U' R U R U R U' R' U' R2) has order 3", function()
  local function uperm(s)
    for _, m in ipairs({ "R", "U'", "R", "U", "R", "U", "R", "U'", "R'", "U'", "R", "R" }) do
      cube.apply(s, m)
    end
  end
  local s = cube.new()
  uperm(s)
  uperm(s)
  uperm(s)
  T.truthy(cube.is_solved(s), "U-perm^3 should solve")
end)

T.test("U-perm applied once leaves a valid (but unsolved) state", function()
  local s = cube.new()
  for _, m in ipairs({ "R", "U'", "R", "U", "R", "U", "R", "U'", "R'", "U'", "R", "R" }) do
    cube.apply(s, m)
  end
  T.falsy(cube.is_solved(s), "U-perm should not solve solved cube")
  -- Centers must still be in place (U-perm is a PLL — only top-layer edges permute).
  T.eq(s.U[5], "W")
  T.eq(s.D[5], "Y")
  T.eq(s.F[5], "G")
end)

-- ============ Task 7: property tests — random sequences ============

T.test("random sequence + reversed inverse returns to solved (50 seeds, length 30)", function()
  local INV = {
    U = "U'",
    D = "D'",
    L = "L'",
    R = "R'",
    F = "F'",
    B = "B'",
    ["U'"] = "U",
    ["D'"] = "D",
    ["L'"] = "L",
    ["R'"] = "R",
    ["F'"] = "F",
    ["B'"] = "B",
  }
  local MOVES = { "U", "D", "L", "R", "F", "B", "U'", "D'", "L'", "R'", "F'", "B'" }
  for seed = 1, 50 do
    math.randomseed(seed * 37 + 1)
    local s = cube.new()
    local applied = {}
    for _ = 1, 30 do
      local m = MOVES[math.random(#MOVES)]
      applied[#applied + 1] = m
      cube.apply(s, m)
    end
    for i = #applied, 1, -1 do
      cube.apply(s, INV[applied[i]])
    end
    T.truthy(cube.is_solved(s), "seed=" .. seed)
  end
end)

T.test("rotation followed by its inverse is identity from any scrambled state", function()
  for seed = 1, 5 do
    for _, r in ipairs({ "x", "y", "z" }) do
      local s = cube.new()
      cube.scramble(s, 15, seed)
      local before = cube.copy(s)
      cube.apply(s, r)
      cube.apply(s, r .. "'")
      T.truthy(cube.equal(s, before), "seed=" .. seed .. " " .. r .. " " .. r .. "'")
    end
  end
end)

T.test("face turn then its inverse is identity from any scrambled state", function()
  for seed = 1, 5 do
    for _, m in ipairs({ "U", "D", "L", "R", "F", "B" }) do
      local s = cube.new()
      cube.scramble(s, 15, seed)
      local before = cube.copy(s)
      cube.apply(s, m)
      cube.apply(s, m .. "'")
      T.truthy(cube.equal(s, before), "seed=" .. seed .. " " .. m .. " " .. m .. "'")
    end
  end
end)

T.test("every 3-move composition from solved keeps the cube valid (1728 paths)", function()
  -- 12 × 12 × 12 = 1728. If any face turn has a directional bug under triple
  -- composition, this catches it.
  for _, m1 in ipairs(FACE_MOVES) do
    for _, m2 in ipairs(FACE_MOVES) do
      for _, m3 in ipairs(FACE_MOVES) do
        local s = cube.new()
        cube.apply(s, m1)
        cube.apply(s, m2)
        cube.apply(s, m3)
        local ok, err = is_valid_cube(s)
        T.truthy(ok, m1 .. " " .. m2 .. " " .. m3 .. ": " .. (err or ""))
      end
    end
  end
end)

T.test("each face turn has order 4 (X^4 = identity from any scrambled state)", function()
  for seed = 1, 5 do
    for _, m in ipairs({ "U", "D", "L", "R", "F", "B", "U'", "D'", "L'", "R'", "F'", "B'" }) do
      local s = cube.new()
      cube.scramble(s, 10, seed)
      local before = cube.copy(s)
      for _ = 1, 4 do
        cube.apply(s, m)
      end
      T.truthy(cube.equal(s, before), "seed=" .. seed .. " " .. m .. "^4")
    end
  end
end)

T.test("each whole-cube rotation has order 4 from any scrambled state", function()
  for seed = 1, 5 do
    for _, r in ipairs({ "x", "y", "z", "x'", "y'", "z'" }) do
      local s = cube.new()
      cube.scramble(s, 10, seed)
      local before = cube.copy(s)
      for _ = 1, 4 do
        cube.apply(s, r)
      end
      T.truthy(cube.equal(s, before), "seed=" .. seed .. " " .. r .. "^4")
    end
  end
end)

T.test("scramble with same seed is reproducible (cube.scramble determinism)", function()
  for seed = 1, 5 do
    local a = cube.new()
    local _, ma = cube.scramble(a, 25, seed)
    local b = cube.new()
    local _, mb = cube.scramble(b, 25, seed)
    T.truthy(cube.equal(a, b), "seed=" .. seed .. " states match")
    T.eq(#ma, #mb, "seed=" .. seed .. " move-list length matches")
    for i = 1, #ma do
      T.eq(ma[i], mb[i], "seed=" .. seed .. " move[" .. i .. "]")
    end
  end
end)

T.test("apply returns the state for fluent chaining", function()
  local s = cube.new()
  local r = cube.apply(s, "U")
  T.truthy(r == s, "apply returns same state ref")
end)

T.test("reset returns to solved from any scrambled state", function()
  for seed = 1, 5 do
    local s = cube.new()
    cube.scramble(s, 20, seed)
    T.falsy(cube.is_solved(s))
    cube.reset(s)
    T.truthy(cube.is_solved(s))
  end
end)
