local T = require("test_helper")
local cube = require("rubikscube.cube")
local facelet = require("rubikscube.facelet")
local moves = require("rubikscube.moves")

-- ============ facelet.to_string ============

T.test("facelet: solved cube renders as 9 of each face letter in URFDLB order", function()
  local s = cube.new()
  local got = facelet.to_string(s)
  local expected = string.rep("U", 9)
    .. string.rep("R", 9)
    .. string.rep("F", 9)
    .. string.rep("D", 9)
    .. string.rep("L", 9)
    .. string.rep("B", 9)
  T.eq(got, expected)
end)

T.test("facelet: output length is always 54", function()
  for seed = 1, 10 do
    local s = cube.new()
    cube.scramble(s, 25, seed)
    T.eq(#facelet.to_string(s), 54, "seed=" .. seed)
  end
end)

T.test("facelet: every char is one of UDLRFB", function()
  for seed = 1, 5 do
    local s = cube.new()
    cube.scramble(s, 20, seed)
    local str = facelet.to_string(s)
    for i = 1, #str do
      local ch = str:sub(i, i)
      T.truthy(ch:match("[UDLRFB]"), "seed=" .. seed .. " char[" .. i .. "]=" .. ch)
    end
  end
end)

T.test("facelet: each face letter appears exactly 9 times after any scramble", function()
  for seed = 1, 10 do
    local s = cube.new()
    cube.scramble(s, 30, seed)
    local str = facelet.to_string(s)
    local counts = { U = 0, D = 0, L = 0, R = 0, F = 0, B = 0 }
    for i = 1, #str do
      local ch = str:sub(i, i)
      counts[ch] = (counts[ch] or 0) + 1
    end
    for face, n in pairs(counts) do
      T.eq(n, 9, "seed=" .. seed .. " face=" .. face)
    end
  end
end)

T.test("facelet: centers (positions 5,14,23,32,41,50) are always URFDLB", function()
  -- Center stickers never move under face turns; they should always be U R F D L B
  -- in their respective face slots regardless of the scramble.
  for seed = 1, 5 do
    local s = cube.new()
    cube.scramble(s, 20, seed)
    local str = facelet.to_string(s)
    T.eq(str:sub(5, 5), "U", "U center")
    T.eq(str:sub(14, 14), "R", "R center")
    T.eq(str:sub(23, 23), "F", "F center")
    T.eq(str:sub(32, 32), "D", "D center")
    T.eq(str:sub(41, 41), "L", "L center")
    T.eq(str:sub(50, 50), "B", "B center")
  end
end)

T.test("facelet: same state ⇒ same string (determinism)", function()
  local a = cube.new()
  local b = cube.new()
  cube.scramble(a, 20, 42)
  cube.scramble(b, 20, 42)
  T.eq(facelet.to_string(a), facelet.to_string(b))
end)

T.test("facelet: a single U turn changes the string in expected slots", function()
  -- After a U turn, the top rows of F/R/B/L rotate: F-top gets R-top's colors etc.
  -- Concretely, positions 19-21 (F-top), 10-12 (R-top), 46-48 (B-top), 37-39 (L-top)
  -- in the URFDLB layout should change while the U face itself (1-9) stays as Us.
  local s = cube.new()
  cube.apply(s, "U")
  local str = facelet.to_string(s)
  T.eq(str:sub(1, 9), string.rep("U", 9), "U face still all U")
  -- F top row received R's top row colors → "R" face letters.
  T.eq(str:sub(19, 21), "RRR")
  -- R top row received B's top row colors.
  T.eq(str:sub(10, 12), "BBB")
  -- L top row received F's top row colors.
  T.eq(str:sub(37, 39), "FFF")
  -- B top row received L's top row colors.
  T.eq(str:sub(46, 48), "LLL")
end)

-- ============ moves.parse ============

T.test("moves.parse: empty string yields empty list", function()
  local m = moves.parse("")
  T.eq(#m, 0)
end)

T.test("moves.parse: single CW face turn", function()
  local m = moves.parse("R")
  T.same(m, { "R" })
end)

T.test("moves.parse: prime token", function()
  local m = moves.parse("R'")
  T.same(m, { "R'" })
end)

T.test("moves.parse: 2-suffix expands to two CW moves", function()
  local m = moves.parse("R2")
  T.same(m, { "R", "R" })
end)

T.test("moves.parse: 2' suffix expands to two prime moves", function()
  local m = moves.parse("R2'")
  T.same(m, { "R'", "R'" })
end)

T.test("moves.parse: whitespace-separated mixed sequence", function()
  local m = moves.parse("R U R' U2 F2 B'")
  T.same(m, { "R", "U", "R'", "U", "U", "F", "F", "B'" })
end)

T.test("moves.parse: collapses extra whitespace", function()
  local m = moves.parse("  R   U  R'  ")
  T.same(m, { "R", "U", "R'" })
end)

T.test("moves.parse: rejects unknown face letter", function()
  local m, err = moves.parse("X")
  T.falsy(m)
  T.truthy(err)
end)

T.test("moves.parse: rejects unsupported suffix", function()
  local m, err = moves.parse("R3")
  T.falsy(m)
  T.truthy(err)
end)

T.test("moves.parse output is applicable by cube.apply", function()
  -- Parser must emit tokens that cube.apply accepts. Use kociemba-shaped input.
  local m = moves.parse("R U2 R' U' F2 B'")
  T.truthy(m)
  local s = cube.new()
  for _, mv in ipairs(m) do
    cube.apply(s, mv) -- would error if any token is unknown
  end
end)

-- ============ end-to-end (no external binary required) ============
--
-- Round-trip: scramble a cube, parse its inverse as a "solution", apply it,
-- assert solved. This exercises facelet→moves→cube.apply integration without
-- needing the kociemba binary.

T.test("end-to-end: applying the inverse of a recorded scramble solves the cube", function()
  for seed = 1, 5 do
    local s = cube.new()
    local _, applied = cube.scramble(s, 20, seed)
    T.falsy(cube.is_solved(s), "seed=" .. seed .. " scrambled")
    -- Build inverse move string in kociemba's notation style and parse it.
    local inv_tokens = {}
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
    for i = #applied, 1, -1 do
      inv_tokens[#inv_tokens + 1] = INV[applied[i]]
    end
    local solution_str = table.concat(inv_tokens, " ")
    local parsed = moves.parse(solution_str)
    T.truthy(parsed, "seed=" .. seed .. " parse")
    for _, m in ipairs(parsed) do
      cube.apply(s, m)
    end
    T.truthy(cube.is_solved(s), "seed=" .. seed .. " solved after inverse")
  end
end)
