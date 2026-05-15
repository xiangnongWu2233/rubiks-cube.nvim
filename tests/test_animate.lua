local T = require("test_helper")
local cube = require("rubikscube.cube")
local animate = require("rubikscube.animate")

-- Drive an animation to completion, gathering the moves seen by on_step.
local function play_to_done(state, moves, tempo_ms)
  local seen, done = {}, false
  animate.play({
    state = state,
    moves = moves,
    tempo_ms = tempo_ms or 5, -- fast for tests
    on_step = function(move, idx)
      seen[#seen + 1] = { move = move, idx = idx }
    end,
    on_done = function()
      done = true
    end,
  })
  -- (#moves + 1) ticks of tempo at most, plus some headroom for scheduling.
  vim.wait(2000, function()
    return done
  end)
  return seen, done
end

T.test("animate: applies moves in order, then fires on_done", function()
  local s = cube.new()
  local seen, done = play_to_done(s, { "R", "U", "R'", "U'" })
  T.truthy(done, "on_done should fire after last move")
  T.eq(#seen, 4, "on_step should fire once per move")
  T.eq(seen[1].move, "R")
  T.eq(seen[1].idx, 1)
  T.eq(seen[2].move, "U")
  T.eq(seen[4].move, "U'")
  -- sexy move once is not identity, but sexy^6 is.
  T.falsy(cube.is_solved(s))
end)

T.test("animate: applying inverse via animation solves a scrambled cube", function()
  local s = cube.new()
  local _, scramble_moves = cube.scramble(s, 10, 7)
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
  local inverse = {}
  for i = #scramble_moves, 1, -1 do
    inverse[#inverse + 1] = INV[scramble_moves[i]]
  end
  local _, done = play_to_done(s, inverse)
  T.truthy(done)
  T.truthy(cube.is_solved(s), "cube should be solved after inverse animation")
end)

T.test("animate: empty move list still fires on_done asynchronously", function()
  local s = cube.new()
  local done = false
  local handle = animate.play({
    state = s,
    moves = {},
    tempo_ms = 5,
    on_done = function()
      done = true
    end,
  })
  -- Must be async — even with an empty list, on_done fires on a later tick.
  T.falsy(done, "on_done should not fire synchronously")
  T.truthy(handle:is_running(), "handle starts as running")
  vim.wait(200, function()
    return done
  end)
  T.truthy(done, "on_done eventually fires")
  T.falsy(handle:is_running(), "handle is no longer running")
end)

T.test(
  "animate: cancel() before completion stops further on_step calls and fires on_cancel",
  function()
    local s = cube.new()
    local step_count, cancelled = 0, false
    local handle
    handle = animate.play({
      state = s,
      moves = { "R", "U", "R'", "U'", "R", "U", "R'", "U'" },
      tempo_ms = 30,
      on_step = function()
        step_count = step_count + 1
        if step_count == 2 then
          handle:cancel()
        end
      end,
      on_cancel = function()
        cancelled = true
      end,
    })
    vim.wait(500, function()
      return cancelled
    end)
    T.truthy(cancelled, "on_cancel should have fired")
    T.eq(step_count, 2, "on_step should not fire after cancel")
    T.falsy(handle:is_running())
  end
)

T.test("animate: cancel() is idempotent and on_cancel only fires once", function()
  local s = cube.new()
  local cancel_count = 0
  local handle = animate.play({
    state = s,
    moves = { "R", "U" },
    tempo_ms = 30,
    on_cancel = function()
      cancel_count = cancel_count + 1
    end,
  })
  handle:cancel()
  handle:cancel()
  handle:cancel()
  T.eq(cancel_count, 1, "on_cancel fired more than once")
end)

T.test("animate: bad move token cancels the run and surfaces err to on_cancel", function()
  local s = cube.new()
  local err_seen
  local done = false
  animate.play({
    state = s,
    moves = { "R", "NOPE", "U" },
    tempo_ms = 5,
    on_step = function() end,
    on_done = function()
      done = true
    end,
    on_cancel = function(err)
      err_seen = err
    end,
  })
  vim.wait(500, function()
    return err_seen ~= nil
  end)
  T.truthy(err_seen, "on_cancel should fire with the apply error")
  T.falsy(done, "on_done should not fire after a bad move")
end)
