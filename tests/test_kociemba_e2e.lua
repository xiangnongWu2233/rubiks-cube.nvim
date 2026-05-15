-- Real-binary end-to-end tests. Skipped gracefully if the `kociemba` CLI
-- is not on PATH — install with `uv tool install kociemba`,
-- `pipx install kociemba`, or `pip install kociemba` to enable.

local T = require("test_helper")
local cube = require("rubikscube.cube")
local solver = require("rubikscube.solver")

if not solver.is_available() then
  T.test("kociemba e2e: SKIPPED (no kociemba binary on PATH)", function()
    -- Always-passing skip marker.
  end)
  return
end

-- Block until the async solver returns. Returns moves, err.
local function solve_sync(state, max_ms)
  local got_moves, got_err, done = nil, nil, false
  solver.solve_async(state, function(m, e)
    got_moves, got_err, done = m, e, true
  end)
  vim.wait(max_ms or 5000, function()
    return done
  end)
  return got_moves, got_err, done
end

T.test("e2e: real kociemba is on PATH and reports available", function()
  T.truthy(solver.is_available())
end)

T.test("e2e: solving the solved cube returns an empty move list", function()
  local s = cube.new()
  local moves, err, done = solve_sync(s, 1000)
  T.truthy(done, "callback fired")
  T.falsy(err)
  T.truthy(moves)
  T.eq(#moves, 0)
end)

T.test("e2e: solving a one-move scramble returns at most 2 moves", function()
  for _, mv in ipairs({ "R", "U", "L", "D", "F", "B", "R'", "U'" }) do
    local s = cube.new()
    cube.apply(s, mv)
    local moves, err, done = solve_sync(s, 5000)
    T.truthy(done, "callback fired for " .. mv)
    T.falsy(err, "no err for " .. mv .. ": " .. tostring(err))
    T.truthy(
      moves and #moves >= 1 and #moves <= 2,
      mv .. " produced " .. (moves and #moves or "nil") .. " moves"
    )
    for _, m in ipairs(moves) do
      cube.apply(s, m)
    end
    T.truthy(cube.is_solved(s), "cube should be solved after applying e2e solution for " .. mv)
  end
end)

T.test("e2e: kociemba solves random 20-move scrambles correctly", function()
  -- Note: muodov/kociemba returns the FIRST solution found (~30-40 moves
  -- worst case), not the shortest. The contract that matters here is that
  -- applying the moves solves the cube — the move count is kociemba's
  -- problem, not the plugin's.
  for seed = 1, 10 do
    local s = cube.new()
    cube.scramble(s, 20, seed)
    T.falsy(cube.is_solved(s), "seed=" .. seed .. " setup")
    local moves, err, done = solve_sync(s, 5000)
    T.truthy(done, "seed=" .. seed .. " callback fired")
    T.falsy(err, "seed=" .. seed .. " err: " .. tostring(err))
    T.truthy(moves and #moves > 0, "seed=" .. seed .. " got moves")
    for _, m in ipairs(moves) do
      cube.apply(s, m)
    end
    T.truthy(cube.is_solved(s), "seed=" .. seed .. " cube should be solved after applying solution")
  end
end)

T.test("e2e: kociemba solves deeper 40-move scrambles", function()
  for seed = 21, 25 do
    local s = cube.new()
    cube.scramble(s, 40, seed)
    local moves, err = solve_sync(s, 5000)
    T.falsy(err, "seed=" .. seed)
    T.truthy(moves)
    for _, m in ipairs(moves) do
      cube.apply(s, m)
    end
    T.truthy(cube.is_solved(s), "seed=" .. seed)
  end
end)

T.test("e2e: full UI handler completes a real solve animation", function()
  local config = require("rubikscube.config")
  config.reset()
  config.apply({ solver = { tempo_ms = 5 } }) -- snappy for tests
  local ui = require("rubikscube.ui")
  local session = ui.new_session()
  cube.scramble(session.state, 20, 99)
  T.falsy(cube.is_solved(session.state))
  ui.make_solve_handler(session)()
  -- Wait generously: solver call + N moves at 5ms tempo.
  vim.wait(5000, function()
    return session.auto_solving == false and not session.anim_handle
  end)
  T.falsy(session.auto_solving, "auto_solving cleared")
  T.falsy(session.anim_handle, "anim_handle cleared")
  T.truthy(cube.is_solved(session.state), "cube ends in solved state")
end)
