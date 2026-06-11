local T = require("test_helper")
local cube = require("rubikscube.cube")
local lbl = require("rubikscube.lbl")

-- Replays `moves` on a copy of `state`; returns the resulting state.
local function replay(state, moves)
  local s = cube.copy(state)
  for _, m in ipairs(moves) do
    cube.apply(s, m)
  end
  return s
end

T.test("lbl: solves 200 seeded scrambles (replay verification)", function()
  for seed = 1, 200 do
    local s = cube.new()
    cube.scramble(s, 25, seed)
    local before = cube.copy(s)
    local result = lbl.solve(s)
    T.truthy(lbl.is_solved_any_orientation(replay(before, result.moves)), "seed=" .. seed)
  end
end)

T.test("lbl: solve does not mutate its input", function()
  local s = cube.new()
  cube.scramble(s, 25, 7)
  local snapshot = cube.copy(s)
  lbl.solve(s)
  T.truthy(cube.equal(s, snapshot))
end)

T.test("lbl: handles cubes in any whole-cube orientation", function()
  local rots = { "x", "x'", "y", "y'", "z", "z'" }
  math.randomseed(99)
  for seed = 1, 40 do
    local s = cube.new()
    cube.scramble(s, 25, 5000 + seed)
    for _ = 1, math.random(0, 4) do
      cube.apply(s, rots[math.random(#rots)])
    end
    local before = cube.copy(s)
    local result = lbl.solve(s)
    T.truthy(lbl.is_solved_any_orientation(replay(before, result.moves)), "seed=" .. seed)
  end
end)

T.test("lbl: already-solved cube needs no face turns", function()
  local result = lbl.solve(cube.new())
  for _, m in ipairs(result.moves) do
    T.truthy(m:match("^[xyz]"), "unexpected face turn on solved cube: " .. m)
  end
end)

T.test("lbl: single-move scramble solves", function()
  local s = cube.apply(cube.new(), "R")
  local result = lbl.solve(s)
  T.truthy(lbl.is_solved_any_orientation(replay(s, result.moves)))
end)

T.test("lbl: returns 8 named stages with descriptions", function()
  local s = cube.new()
  cube.scramble(s, 25, 3)
  local result = lbl.solve(s)
  T.eq(#result.stages, 8)
  for _, st in ipairs(result.stages) do
    T.truthy(type(st.name) == "string" and #st.name > 0)
    T.truthy(type(st.desc) == "string" and #st.desc > 0)
    T.truthy(type(st.moves) == "table")
  end
  T.eq(result.stages[2].name, "White cross")
  T.eq(result.stages[8].name, "Twist corners")
end)

T.test("lbl: flat move list equals concatenated stage moves", function()
  local s = cube.new()
  cube.scramble(s, 25, 11)
  local result = lbl.solve(s)
  local n = 0
  for _, st in ipairs(result.stages) do
    n = n + #st.moves
  end
  T.eq(#result.moves, n)
end)

T.test("lbl: emitted moves contain no adjacent cancellations", function()
  local function inv(m)
    return m:find("'") and m:sub(1, -2) or (m .. "'")
  end
  for seed = 1, 20 do
    local s = cube.new()
    cube.scramble(s, 25, 100 + seed)
    local result = lbl.solve(s)
    for _, st in ipairs(result.stages) do
      for i = 1, #st.moves - 1 do
        T.truthy(st.moves[i + 1] ~= inv(st.moves[i]), "seed=" .. seed .. " idx=" .. i)
      end
    end
  end
end)

T.test("lbl: every emitted move is cube.apply-compatible", function()
  -- cube.apply errors on unknown tokens; replay across several seeds.
  for seed = 1, 10 do
    local s = cube.new()
    cube.scramble(s, 25, 200 + seed)
    replay(s, lbl.solve(s).moves)
  end
end)

T.test("lbl: solution length stays in the expected beginner range", function()
  for seed = 1, 30 do
    local s = cube.new()
    cube.scramble(s, 25, 300 + seed)
    local n = #lbl.solve(s).moves
    T.truthy(n > 0 and n <= 320, "seed=" .. seed .. " len=" .. n)
  end
end)
