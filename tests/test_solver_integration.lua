-- Integration tests for the solver/animation/UI pipeline. Uses a stub
-- `kociemba` binary on PATH so these tests run without the real solver
-- being installed.

local T = require("test_helper")
local cube = require("rubikscube.cube")
local config = require("rubikscube.config")

-- Test harness: writes a fake kociemba binary, prepends its dir to PATH for
-- the duration of `fn`, restores PATH and removes the temp dir afterwards.
local function with_stub_kociemba(stub_body, fn)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local script = dir .. "/kociemba"
  local f = assert(io.open(script, "w"))
  f:write("#!/bin/sh\n")
  f:write(stub_body)
  f:close()
  vim.fn.system({ "chmod", "+x", script })

  local prev_path = vim.env.PATH
  vim.env.PATH = dir .. ":" .. prev_path

  local ok, err = pcall(fn)

  -- Give any in-flight async vim.system calls a chance to finish exec'ing
  -- before we yank the script out from under them. Polled, not slept — the
  -- "kociemba" binary is short-running so this returns quickly.
  vim.wait(500, function()
    local handles = vim.api.nvim_list_chans()
    for _, ch in ipairs(handles) do
      if ch.argv and ch.argv[1] and ch.argv[1]:match("kociemba$") then
        return false
      end
    end
    return true
  end)

  vim.env.PATH = prev_path
  vim.fn.delete(dir, "rf")
  if not ok then
    error(err, 0)
  end
end

-- Wait until either the animation has started (anim_handle is set) or the
-- solver has finished with an error (auto_solving has been reset).
local function wait_for_solver_settled(session, max_ms)
  vim.wait(max_ms or 2000, function()
    return session.anim_handle ~= nil or session.auto_solving == false
  end)
end

-- Capture vim.notify calls into a list. Returns a restore fn.
local function capture_notify()
  local prev = vim.notify
  local notes = {}
  vim.notify = function(msg, lvl)
    notes[#notes + 1] = { msg = msg, lvl = lvl }
  end
  return notes, function()
    vim.notify = prev
  end
end

-- Drive the solve handler and wait for the animation to settle (or for an
-- error notification, whichever comes first). Returns once `auto_solving`
-- becomes false again.
local function drive_solve(session, max_ms)
  local ui = require("rubikscube.ui")
  ui.make_solve_handler(session)()
  vim.wait(max_ms or 3000, function()
    return session.auto_solving == false
  end)
end

local function fresh_session()
  -- Reset config so each test starts from defaults (esp. solver.tempo_ms).
  config.reset()
  -- Speed up the animation in tests; we don't need 200 ms between moves.
  config.apply({ solver = { tempo_ms = 5 } })
  local ui = require("rubikscube.ui")
  return ui.new_session()
end

-- ============ availability + happy path ============

T.test("integration: stub binary is discovered via PATH", function()
  with_stub_kociemba([[echo "R U R' U'"]], function()
    local solver = require("rubikscube.solver")
    T.truthy(solver.is_available())
  end)
end)

T.test("integration: solve_async parses stubbed kociemba output", function()
  with_stub_kociemba([[echo "R U R' U2 F'"]], function()
    local solver = require("rubikscube.solver")
    local got_moves, done
    local s = cube.new()
    cube.apply(s, "U") -- not solved
    solver.solve_async(s, function(m, _)
      got_moves = m
      done = true
    end)
    vim.wait(2000, function()
      return done
    end)
    T.truthy(done)
    T.same(got_moves, { "R", "U", "R'", "U", "U", "F'" })
  end)
end)

T.test("integration: full handler animates moves then cube reaches solved state", function()
  -- Stub returns the *inverse* of a fixed scramble: applying U then U' returns to solved.
  with_stub_kociemba([[echo "U'"]], function()
    local session = fresh_session()
    cube.apply(session.state, "U") -- one move from solved
    T.falsy(cube.is_solved(session.state))
    drive_solve(session)
    T.falsy(session.auto_solving, "auto_solving cleared")
    T.truthy(cube.is_solved(session.state), "stub solution should solve the state")
    T.eq(session.last_move, "U'")
  end)
end)

-- ============ cancellation behaviours ============

T.test("integration: manual face-key keystroke cancels in-flight auto-solve", function()
  -- Long stub solution + slow tempo so we have multiple ms to interrupt.
  with_stub_kociemba([[echo "R R R R R R R R"]], function()
    config.reset()
    config.apply({ solver = { tempo_ms = 50 } })
    local ui = require("rubikscube.ui")
    local session = ui.new_session()
    cube.apply(session.state, "U")
    ui.make_solve_handler(session)()
    -- Wait for the solver to actually return and the animation to start.
    wait_for_solver_settled(session)
    T.truthy(session.anim_handle, "animation should have started")
    T.truthy(session.auto_solving)
    ui.make_move_handler(session, "L")()
    T.falsy(session.auto_solving, "manual move clears auto_solving immediately")
    T.falsy(session.anim_handle, "anim_handle cleared by cancellation")
    T.eq(session.last_move, "L")
  end)
end)

T.test("integration: scramble action cancels in-flight auto-solve", function()
  with_stub_kociemba([[echo "R R R R R R R R"]], function()
    config.reset()
    config.apply({ solver = { tempo_ms = 50 } })
    local ui = require("rubikscube.ui")
    local session = ui.new_session()
    cube.apply(session.state, "U")
    ui.make_solve_handler(session)()
    wait_for_solver_settled(session)
    T.truthy(session.anim_handle, "animation should have started")
    ui.make_scramble_handler(session)()
    T.falsy(session.auto_solving, "scramble cancels auto_solving")
    T.falsy(session.anim_handle, "anim_handle cleared")
    T.eq(session.last_move, "scramble")
  end)
end)

T.test("integration: reset action cancels in-flight auto-solve", function()
  with_stub_kociemba([[echo "R R R R R R R R"]], function()
    config.reset()
    config.apply({ solver = { tempo_ms = 50 } })
    local ui = require("rubikscube.ui")
    local session = ui.new_session()
    cube.apply(session.state, "U")
    ui.make_solve_handler(session)()
    wait_for_solver_settled(session)
    T.truthy(session.anim_handle)
    ui.make_reset_handler(session)()
    T.falsy(session.auto_solving, "reset cancels auto_solving")
    T.falsy(session.anim_handle, "anim_handle cleared")
    T.truthy(cube.is_solved(session.state), "reset returns to solved")
  end)
end)

T.test(
  "integration: cancellation BEFORE solver returns prevents animation from starting",
  function()
    -- Use a stub that sleeps for a beat so we can cancel during the in-flight
    -- vim.system call (before the animation begins). This guards the bug
    -- where the solver's callback would start an animation even after the
    -- user cancelled.
    with_stub_kociemba(
      [[
sleep 0.2
echo "R R R R"
]],
      function()
        config.reset()
        config.apply({ solver = { tempo_ms = 50 } })
        local ui = require("rubikscube.ui")
        local session = ui.new_session()
        cube.apply(session.state, "U")
        ui.make_solve_handler(session)()
        -- Cancel immediately (well before the 200ms sleep elapses).
        T.truthy(session.auto_solving, "auto_solving set synchronously")
        T.falsy(session.anim_handle, "anim_handle not yet set")
        ui.make_reset_handler(session)()
        T.falsy(session.auto_solving, "reset cleared auto_solving")
        -- Wait long enough for the stub to finish and the callback to run.
        vim.wait(800, function()
          return false
        end)
        T.falsy(session.anim_handle, "no animation should have started after late callback")
        T.falsy(session.auto_solving, "auto_solving should remain false")
      end
    )
  end
)

T.test("integration: pressing solve twice does not start a second animation", function()
  with_stub_kociemba([[echo "R R R R"]], function()
    local notes, restore = capture_notify()
    local session = fresh_session()
    config.reset()
    config.apply({ solver = { tempo_ms = 30 } })
    cube.apply(session.state, "U")
    local ui = require("rubikscube.ui")
    ui.make_solve_handler(session)()
    vim.wait(40)
    T.truthy(session.auto_solving)
    ui.make_solve_handler(session)() -- second press
    -- Second press should have emitted an "already running" notify and NOT
    -- restarted the animation. (Hard to introspect handle identity from here,
    -- so we assert via the notify content.)
    local saw = false
    for _, n in ipairs(notes) do
      if n.msg:find("already running") then
        saw = true
      end
    end
    T.truthy(saw, "second solve press should notify 'already running'")
    restore()
  end)
end)

-- ============ no-op + error paths ============

T.test("integration: solve on an already-solved cube notifies and does nothing", function()
  with_stub_kociemba([[echo "R U R' U'"]], function()
    local notes, restore = capture_notify()
    local session = fresh_session()
    T.truthy(cube.is_solved(session.state))
    local ui = require("rubikscube.ui")
    ui.make_solve_handler(session)()
    T.falsy(session.auto_solving, "should not start an animation")
    local saw = false
    for _, n in ipairs(notes) do
      if n.msg:find("already solved") then
        saw = true
      end
    end
    T.truthy(saw, "expected 'already solved' notify")
    restore()
  end)
end)

T.test("integration: missing binary path emits install hint via notify", function()
  -- Don't install the stub: ensure kociemba is NOT on PATH for this test.
  local prev_path = vim.env.PATH
  -- Filter out any path component that has kociemba on it.
  local cleaned = {}
  for part in (prev_path .. ":"):gmatch("([^:]+):") do
    if vim.fn.executable(part .. "/kociemba") ~= 1 then
      cleaned[#cleaned + 1] = part
    end
  end
  vim.env.PATH = table.concat(cleaned, ":")
  local ok, err = pcall(function()
    local solver = require("rubikscube.solver")
    T.falsy(solver.is_available(), "stub-free PATH should not find kociemba")
    local notes, restore = capture_notify()
    local session = fresh_session()
    cube.apply(session.state, "U")
    local ui = require("rubikscube.ui")
    ui.make_solve_handler(session)()
    T.falsy(session.auto_solving, "should not start animation when binary missing")
    local saw = false
    for _, n in ipairs(notes) do
      if n.msg:find("kociemba") then
        saw = true
      end
    end
    T.truthy(saw, "expected kociemba install hint notify")
    restore()
  end)
  vim.env.PATH = prev_path
  if not ok then
    error(err, 0)
  end
end)

T.test("integration: kociemba nonzero exit surfaces error via notify", function()
  with_stub_kociemba(
    [[
echo "bad facelet" >&2
exit 2
]],
    function()
      local notes, restore = capture_notify()
      local session = fresh_session()
      cube.apply(session.state, "U")
      drive_solve(session, 2000)
      T.falsy(session.auto_solving, "auto_solving cleared after error")
      local saw_err = false
      for _, n in ipairs(notes) do
        if n.lvl == vim.log.levels.ERROR then
          saw_err = true
        end
      end
      T.truthy(saw_err, "expected an ERROR notify when kociemba exits non-zero")
      restore()
    end
  )
end)

T.test("integration: empty kociemba stdout surfaces error via notify", function()
  with_stub_kociemba([[exit 0]], function()
    local notes, restore = capture_notify()
    local session = fresh_session()
    cube.apply(session.state, "U")
    drive_solve(session, 2000)
    T.falsy(session.auto_solving)
    local saw = false
    for _, n in ipairs(notes) do
      if n.msg:find("empty") then
        saw = true
      end
    end
    T.truthy(saw, "expected an 'empty output' error notify")
    restore()
  end)
end)

-- ============ lifecycle / state hygiene ============

T.test("integration: move_count is NOT bumped during auto-solve", function()
  with_stub_kociemba([[echo "U'"]], function()
    local session = fresh_session()
    cube.apply(session.state, "U")
    -- Pretend the user had started the timer manually so move_count would
    -- normally accumulate during manual play.
    session.timer_running = true
    session.timer_start_ms = (vim.uv or vim.loop).now()
    local pre = session.move_count
    drive_solve(session)
    T.eq(session.move_count, pre, "move_count should be frozen during auto-solve")
  end)
end)

T.test("integration: auto-solve completing does not trigger celebrate popup", function()
  with_stub_kociemba([[echo "U'"]], function()
    local session = fresh_session()
    cube.apply(session.state, "U")
    drive_solve(session)
    T.truthy(cube.is_solved(session.state))
    T.falsy(session.solve_popup, "no solve popup should fire on auto-solve")
    T.falsy(session.solve_locked, "solve_locked should remain false")
  end)
end)
