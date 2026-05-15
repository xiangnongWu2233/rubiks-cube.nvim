local T = require("test_helper")
local cube = require("rubikscube.cube")
local ui = require("rubikscube.ui")
local render = require("rubikscube.render")
local best = require("rubikscube.best")
local config = require("rubikscube.config")

-- Redirect best-time persistence to a throwaway file so tests don't clobber
-- the user's real ~/.local/share/nvim/rubikscube/best.json.
best._path_override = vim.fn.tempname() .. "-rubikscube-best.json"
local function clear_best()
  best.clear()
end
clear_best()

T.test("new_session has solved cube and zero count", function()
  local s = ui.new_session()
  T.truthy(cube.is_solved(s.state))
  T.eq(s.move_count, 0)
  T.eq(s.last_move, nil)
end)

T.test("open creates a valid scratch buffer", function()
  local s = ui.open()
  T.truthy(s.buf, "session.buf set")
  T.truthy(vim.api.nvim_buf_is_valid(s.buf))
  T.eq(vim.bo[s.buf].buftype, "nofile")
  T.eq(vim.bo[s.buf].swapfile, false)
  T.eq(vim.bo[s.buf].filetype, "rubikscube")
  ui.make_quit_handler(s)()
end)

T.test("open registers all 18 move keymaps + 4 action keymaps", function()
  local s = ui.open()
  local maps = vim.api.nvim_buf_get_keymap(s.buf, "n")
  local lhs_set = {}
  for _, m in ipairs(maps) do
    lhs_set[m.lhs] = true
  end

  local expected = {
    "u",
    "U",
    "d",
    "D",
    "l",
    "L",
    "r",
    "R",
    "f",
    "F",
    "b",
    "B",
    "x",
    "X",
    "y",
    "Y",
    "z",
    "Z",
    "s",
    "<CR>",
    "q",
    "?",
  }
  for _, key in ipairs(expected) do
    T.truthy(lhs_set[key], "keymap missing: " .. key)
  end
  ui.make_quit_handler(s)()
end)

T.test("U handler applies U move and increments count (timer started)", function()
  local s = ui.open()
  ui.make_space_handler(s)() -- timer must be running for count to tick
  local handler = ui.make_move_handler(s, "U")
  handler()
  -- After U from solved: F[1..3] should be R
  T.eq(s.state.F[1], "R")
  T.eq(s.state.F[2], "R")
  T.eq(s.state.F[3], "R")
  T.eq(s.move_count, 1)
  T.eq(s.last_move, "U")
  handler()
  T.eq(s.move_count, 2)
  ui.make_quit_handler(s)()
end)

T.test("prime move handler applies inverse", function()
  local s = ui.open()
  ui.make_scramble_handler(s)() -- scramble so R R' is a no-op on a non-solved cube
  ui.make_space_handler(s)() -- start timer so moves count
  ui.make_move_handler(s, "R")()
  ui.make_move_handler(s, "R'")()
  T.eq(s.move_count, 2, "count tracks both")
  ui.make_quit_handler(s)()
end)

T.test("rotation handlers permute centers without affecting move_count semantics", function()
  local s = ui.open()
  ui.make_move_handler(s, "y")()
  T.eq(s.state.F[5], "R", "after y, F center is red")
  ui.make_move_handler(s, "y'")()
  T.truthy(cube.is_solved(s.state), "y y' should be identity")
  ui.make_quit_handler(s)()
end)

T.test("scramble handler scrambles cube and resets count to 0", function()
  local s = ui.open()
  -- Bump the count via a manual move first (requires timer active).
  ui.make_space_handler(s)()
  ui.make_move_handler(s, "U")()
  T.eq(s.move_count, 1)
  ui.make_scramble_handler(s)()
  T.falsy(cube.is_solved(s.state), "should be scrambled")
  T.eq(s.move_count, 0, "scramble resets count")
  T.eq(s.last_move, "scramble")
  ui.make_quit_handler(s)()
end)

T.test("reset handler returns to solved and clears count", function()
  local s = ui.open()
  ui.make_scramble_handler(s)()
  T.falsy(cube.is_solved(s.state))
  ui.make_reset_handler(s)()
  T.truthy(cube.is_solved(s.state))
  T.eq(s.move_count, 0)
  T.eq(s.last_move, "reset")
  ui.make_quit_handler(s)()
end)

T.test("quit handler invalidates the buffer", function()
  local s = ui.open()
  local buf = s.buf
  T.truthy(vim.api.nvim_buf_is_valid(buf))
  ui.make_quit_handler(s)()
  T.falsy(vim.api.nvim_buf_is_valid(buf))
end)

T.test("help handler opens then toggles closed", function()
  local s = ui.open()
  ui.make_help_handler(s)()
  T.truthy(s.help_win, "help window opened")
  T.truthy(vim.api.nvim_win_is_valid(s.help_win))
  ui.make_help_handler(s)() -- toggle off
  T.falsy(s.help_win, "help window closed")
  ui.make_quit_handler(s)()
end)

T.test("repaint after move updates buffer (smoke test)", function()
  local s = ui.open()
  local before = vim.api.nvim_buf_get_lines(s.buf, 0, -1, false)
  ui.make_move_handler(s, "U")()
  local after = vim.api.nvim_buf_get_lines(s.buf, 0, -1, false)
  -- Status line should have changed because last_move and move_count changed.
  local last_before = before[#before]
  local last_after = after[#after]
  T.truthy(last_before ~= last_after, "status line should change after move")
  ui.make_quit_handler(s)()
end)

T.test("multiple move keys trigger different moves", function()
  local s = ui.open()
  ui.make_space_handler(s)() -- start timer so moves count
  ui.make_move_handler(s, "U")()
  ui.make_move_handler(s, "R")()
  ui.make_move_handler(s, "F")()
  T.eq(s.move_count, 3)
  T.eq(s.last_move, "F")
  -- After U R F, cube is definitely not solved.
  T.falsy(cube.is_solved(s.state))
  ui.make_quit_handler(s)()
end)

-- ============ Timer + solve detection ============

T.test("new_session: timer is idle (not running, no elapsed)", function()
  local s = ui.new_session()
  T.falsy(s.timer_running)
  T.eq(s.timer_elapsed_ms, nil)
end)

T.test("space handler toggles timer running flag", function()
  local s = ui.open()
  T.falsy(s.timer_running)
  ui.make_space_handler(s)()
  T.truthy(s.timer_running, "after first Space, running")
  T.truthy(s.timer_start_ms, "start_ms recorded")
  ui.make_space_handler(s)()
  T.falsy(s.timer_running, "after second Space, stopped")
  T.truthy(s.timer_elapsed_ms, "elapsed recorded")
  ui.make_quit_handler(s)()
end)

T.test("space pause then resume continues accumulated time (does NOT restart)", function()
  local s = ui.open()
  -- Simulate prior accumulated time without actually waiting wall-clock seconds.
  ui.make_space_handler(s)() -- start
  ui.make_space_handler(s)() -- stop
  s.timer_elapsed_ms = 1234 -- pretend ~1.234s elapsed
  ui.make_space_handler(s)() -- resume
  T.truthy(s.timer_running)
  -- After resume, current_elapsed should be >= the prior accumulated value.
  local now = (vim.uv or vim.loop).now()
  T.truthy(now - s.timer_start_ms >= 1234, "start_ms backdated to include prior elapsed")
  T.eq(s.timer_elapsed_ms, nil, "elapsed_ms cleared while running")
  ui.make_space_handler(s)() -- stop again
  T.truthy(s.timer_elapsed_ms >= 1234, "after re-stop, elapsed >= prior")
  ui.make_quit_handler(s)()
end)

T.test("reset handler clears timer to idle", function()
  local s = ui.open()
  ui.make_space_handler(s)()
  ui.make_space_handler(s)()
  T.truthy(s.timer_elapsed_ms)
  ui.make_reset_handler(s)()
  T.falsy(s.timer_running)
  T.eq(s.timer_elapsed_ms, nil)
  ui.make_quit_handler(s)()
end)

T.test("scramble handler clears timer to idle", function()
  local s = ui.open()
  ui.make_space_handler(s)()
  ui.make_space_handler(s)()
  T.truthy(s.timer_elapsed_ms)
  ui.make_scramble_handler(s)()
  T.falsy(s.timer_running)
  T.eq(s.timer_elapsed_ms, nil)
  ui.make_quit_handler(s)()
end)

T.test("solve transition (manual U U' from solved) triggers celebrate", function()
  -- From solved → U (unsolved) → U' (solved again): the U' move IS a transition to solved.
  local s = ui.open()
  ui.make_move_handler(s, "U")()
  T.falsy(cube.is_solved(s.state))
  -- A move that solves the cube triggers a popup (via vim.defer_fn → flash → popup).
  -- We can't easily wait 250ms in the test runner, but we can verify state immediately:
  -- timer should be stopped (auto-stop happens synchronously in celebrate_solve).
  ui.make_space_handler(s)() -- start timer (was idle)
  T.truthy(s.timer_running)
  ui.make_move_handler(s, "U'")()
  T.truthy(cube.is_solved(s.state))
  T.falsy(s.timer_running, "timer should auto-stop on solve transition")
  T.truthy(s.timer_elapsed_ms, "elapsed should be recorded")
  ui.make_quit_handler(s)()
end)

T.test("reset → already solved → no popup, no celebration", function()
  -- Reset on a solved cube must NOT trigger celebrate (we'd be infinitely popping up).
  local s = ui.open()
  ui.make_reset_handler(s)()
  T.falsy(s.solve_popup, "no popup after reset of already-solved cube")
  ui.make_quit_handler(s)()
end)

T.test("scramble produces unsolved state (so subsequent solve transition can fire)", function()
  local s = ui.open()
  ui.make_scramble_handler(s)()
  T.falsy(cube.is_solved(s.state))
  T.falsy(s.was_solved, "was_solved flag tracks current state")
  ui.make_quit_handler(s)()
end)

T.test("format_time produces M:SS.cc for known values", function()
  T.eq(render.format_time(0), "0:00.00")
  T.eq(render.format_time(1500), "0:01.50")
  T.eq(render.format_time(63250), "1:03.25")
  T.eq(render.format_time(nil), "--:--.--")
end)

T.test("status line includes Time field", function()
  local line = render.status_line("U", 3, 12340, true)
  T.truthy(line:find("Time:"), "has Time label")
  T.truthy(line:find("0:12.34"), "has formatted time")
end)

T.test("Space keymap is registered on the cube buffer", function()
  local s = ui.open()
  local maps = vim.api.nvim_buf_get_keymap(s.buf, "n")
  local found = false
  for _, m in ipairs(maps) do
    if m.lhs == " " or m.lhs == "<Space>" then
      found = true
      break
    end
  end
  T.truthy(found, "<Space> keymap exists")
  ui.make_quit_handler(s)()
end)

T.test("solve popup function returns handle and dismiss callback fires", function()
  local closed = false
  local popup = render.show_solve_popup(1234, 5, nil, false, function()
    closed = true
  end)
  T.truthy(popup.win, "popup window created")
  T.truthy(vim.api.nvim_win_is_valid(popup.win))
  popup.close()
  T.truthy(closed, "on_close fired")
  T.falsy(vim.api.nvim_win_is_valid(popup.win))
end)

-- Ensures the render.flash callback is invokable.
T.test("flash schedules and invokes callback (smoke)", function()
  local called = false
  -- Use 1ms so the deferred callback should fire near-immediately.
  render.flash(1, function()
    called = true
  end)
  -- Pump the event loop briefly to allow the deferred callback to run.
  vim.wait(50, function()
    return called
  end)
  T.truthy(called, "flash callback fired")
end)

T.test("keymap RHS table includes all 18 face/rotation move bindings", function()
  T.eq(#ui.KEYMAP, 18)
  -- Verify primes are paired with uppercase: every move ending in ' has an uppercase key
  local primes = 0
  for _, km in ipairs(ui.KEYMAP) do
    if km[2]:sub(-1) == "'" then
      primes = primes + 1
      T.truthy(km[1] == km[1]:upper(), "prime key should be uppercase: " .. km[1])
    end
  end
  T.eq(primes, 9, "9 prime moves")
end)

-- ============ Aggressive: long sequences, timer math, help completeness ============

T.test("long move sequence: count and last_move track every step", function()
  local s = ui.open()
  ui.make_space_handler(s)() -- start timer so moves count
  local seq = {
    "U",
    "R",
    "F",
    "L",
    "B",
    "D",
    "U'",
    "R'",
    "F'",
    "L'",
    "B'",
    "D'",
    "U",
    "U",
    "R",
    "R",
    "F",
    "F",
  }
  for i, m in ipairs(seq) do
    ui.make_move_handler(s, m)()
    T.eq(s.move_count, i, "count after " .. i .. " moves")
    T.eq(s.last_move, m, "last_move=" .. m)
  end
  T.falsy(cube.is_solved(s.state))
  ui.make_quit_handler(s)()
end)

T.test("sexy move six times triggers solve transition on the last move", function()
  local s = ui.open()
  local sexy = { "R", "U", "R'", "U'" }
  for _ = 1, 5 do
    for _, m in ipairs(sexy) do
      ui.make_move_handler(s, m)()
    end
  end
  for i = 1, 3 do
    ui.make_move_handler(s, sexy[i])()
  end -- 5*4 + 3 = 23 moves
  T.falsy(cube.is_solved(s.state), "23 sexy moves not solved")
  T.falsy(s.was_solved)
  ui.make_move_handler(s, "U'")() -- 24th move completes (R U R' U')^6
  T.truthy(cube.is_solved(s.state), "24 sexy moves should solve")
  T.truthy(s.was_solved)
  ui.make_quit_handler(s)()
end)

T.test("timer accumulates across three pause/resume cycles", function()
  local s = ui.open()
  -- Run 1: 1500ms
  ui.make_space_handler(s)()
  s.timer_start_ms = (vim.uv or vim.loop).now() - 1500
  ui.make_space_handler(s)()
  T.truthy(s.timer_elapsed_ms >= 1500, "first run >= 1500ms")
  -- Run 2: +2000ms
  ui.make_space_handler(s)()
  s.timer_start_ms = (vim.uv or vim.loop).now() - (1500 + 2000)
  ui.make_space_handler(s)()
  T.truthy(s.timer_elapsed_ms >= 3500, "after second run, >= 3500ms total")
  -- Run 3: +500ms
  ui.make_space_handler(s)()
  s.timer_start_ms = (vim.uv or vim.loop).now() - (3500 + 500)
  ui.make_space_handler(s)()
  T.truthy(s.timer_elapsed_ms >= 4000, "after third run, >= 4000ms total")
  ui.make_quit_handler(s)()
end)

T.test("help text mentions every move key", function()
  local s = ui.open()
  ui.make_help_handler(s)()
  local lines = vim.api.nvim_buf_get_lines(s.help_buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  for _, km in ipairs(ui.KEYMAP) do
    T.truthy(text:find(km[1], 1, true), "help should mention key '" .. km[1] .. "'")
  end
  ui.make_quit_handler(s)()
end)

T.test("scramble produces a different state from solved", function()
  local s = ui.open()
  local before = cube.copy(s.state)
  ui.make_scramble_handler(s)()
  T.falsy(cube.equal(s.state, before), "scrambled differs from solved")
  ui.make_quit_handler(s)()
end)

T.test("scramble then reset returns to solved", function()
  local s = ui.open()
  ui.make_scramble_handler(s)()
  T.falsy(cube.is_solved(s.state))
  ui.make_reset_handler(s)()
  T.truthy(cube.is_solved(s.state))
  T.eq(s.move_count, 0)
  ui.make_quit_handler(s)()
end)

T.test("100 random move applications keep count and last_move correct", function()
  local s = ui.open()
  ui.make_space_handler(s)() -- start timer so moves count
  local MOVES = { "U", "D", "L", "R", "F", "B", "U'", "D'", "L'", "R'", "F'", "B'" }
  math.randomseed(424242)
  for i = 1, 100 do
    local m = MOVES[math.random(#MOVES)]
    ui.make_move_handler(s, m)()
    T.eq(s.move_count, i)
    T.eq(s.last_move, m)
  end
  T.falsy(cube.is_solved(s.state))
  ui.make_quit_handler(s)()
end)

T.test("was_solved flag tracks whether current state is solved", function()
  local s = ui.open()
  ui.make_move_handler(s, "U")()
  T.falsy(s.was_solved, "after U, not solved")
  ui.make_move_handler(s, "U'")()
  T.truthy(s.was_solved, "after U U', solved")
  ui.make_move_handler(s, "R")()
  T.falsy(s.was_solved, "after R, not solved")
  ui.make_quit_handler(s)()
end)

T.test("reset on already-solved cube does not create a popup", function()
  local s = ui.open()
  ui.make_reset_handler(s)()
  T.falsy(s.solve_popup)
  ui.make_quit_handler(s)()
end)

T.test("Space toggles timer running flag deterministically", function()
  local s = ui.open()
  T.falsy(s.timer_running)
  T.eq(s.timer_elapsed_ms, nil)
  ui.make_space_handler(s)()
  T.truthy(s.timer_running)
  T.eq(s.timer_elapsed_ms, nil, "running: elapsed cleared")
  ui.make_space_handler(s)()
  T.falsy(s.timer_running)
  T.truthy(s.timer_elapsed_ms ~= nil)
  ui.make_quit_handler(s)()
end)

T.test("quit handler stops timer and invalidates buffer", function()
  local s = ui.open()
  ui.make_space_handler(s)()
  T.truthy(s.timer_running)
  local buf = s.buf
  ui.make_quit_handler(s)()
  T.falsy(s.timer_handle, "timer handle cleared")
  T.falsy(vim.api.nvim_buf_is_valid(buf), "buffer destroyed")
end)

T.test("KEYMAP keys are unique and moves are unique", function()
  local keys = {}
  local moves = {}
  for _, km in ipairs(ui.KEYMAP) do
    T.falsy(keys[km[1]], "duplicate key: " .. km[1])
    T.falsy(moves[km[2]], "duplicate move: " .. km[2])
    keys[km[1]] = true
    moves[km[2]] = true
  end
end)

T.test("every KEYMAP move is a valid cube.apply move", function()
  for _, km in ipairs(ui.KEYMAP) do
    local s = cube.new()
    local ok = pcall(cube.apply, s, km[2])
    T.truthy(ok, "keymap " .. km[1] .. " → " .. km[2] .. " applies cleanly")
  end
end)

-- ============ Integration: state, render, and ui agree ============

T.test("after each move, buffer content reflects the move's effect on visible faces", function()
  local s = ui.open()
  local last_lines = vim.api.nvim_buf_get_lines(s.buf, 0, -1, false)
  for _, m in ipairs({ "U", "R", "F", "D", "L", "B" }) do
    ui.make_move_handler(s, m)()
    local lines = vim.api.nvim_buf_get_lines(s.buf, 0, -1, false)
    -- Status line at minimum should change because last_move changed.
    T.truthy(
      table.concat(lines, "\n") ~= table.concat(last_lines, "\n"),
      "buffer content should change after " .. m
    )
    last_lines = lines
  end
  ui.make_quit_handler(s)()
end)

T.test("buffer-rendered visible-face colors match s.state after each move", function()
  -- `render` is already required at the top of the file; do not shadow.
  local s = ui.open()
  for _, m in ipairs({ "U", "R", "F", "y", "x", "L", "B", "z" }) do
    ui.make_move_handler(s, m)()
    local _, hls = render.snapshot(s.buf)
    for _, face in ipairs({ "U", "F", "R" }) do
      for i = 1, 9 do
        local region = render.STICKER_REGIONS[face][i][1]
        local color = s.state[face][i]
        local group = render.HL[color].group
        local found = false
        for _, h in ipairs(hls) do
          if h.row == region.row and h.col == region.col_start and h.hl_group == group then
            found = true
            break
          end
        end
        T.truthy(
          found,
          string.format("after %s, %s[%d]=%s rendered as %s", m, face, i, color, group)
        )
      end
    end
  end
  ui.make_quit_handler(s)()
end)

T.test("new_session creates independent sessions (no shared cube state)", function()
  local s1 = ui.new_session()
  local s2 = ui.new_session()
  -- Mutating s1.state must not affect s2.state.
  cube.apply(s1.state, "U")
  T.falsy(cube.is_solved(s1.state))
  T.truthy(cube.is_solved(s2.state), "s2 unaffected")
end)

T.test("two ui.open() sessions in succession both produce valid buffers", function()
  local s1 = ui.open()
  local buf1 = s1.buf
  T.truthy(vim.api.nvim_buf_is_valid(buf1))
  ui.make_quit_handler(s1)()
  T.eq(s1.buf, nil, "buf cleared on quit")
  T.falsy(vim.api.nvim_buf_is_valid(buf1), "first buffer destroyed")
  -- Open a second session.
  local s2 = ui.open()
  T.truthy(vim.api.nvim_buf_is_valid(s2.buf))
  T.truthy(cube.is_solved(s2.state), "fresh session is solved")
  T.truthy(s2.buf ~= buf1, "different buffer handle from first session")
  ui.make_quit_handler(s2)()
end)

T.test("scramble handler resets timer and was_solved tracking", function()
  local s = ui.open()
  -- First scramble the cube, then solve transition (manual), confirm state.
  ui.make_space_handler(s)() -- start
  ui.make_space_handler(s)() -- stop with some elapsed
  T.truthy(s.timer_elapsed_ms)
  ui.make_scramble_handler(s)()
  T.eq(s.timer_elapsed_ms, nil, "scramble clears elapsed")
  T.falsy(s.timer_running)
  T.falsy(s.was_solved, "was_solved flag matches new state")
  ui.make_quit_handler(s)()
end)

T.test("solve transition only fires when transitioning to solved, not from solved", function()
  local s = ui.open()
  -- From solved: apply U then U' — only the U' triggers celebrate (and only if
  -- the timer is active; see solve-detection-gated-on-timer tests below).
  T.truthy(s.was_solved) -- starts solved
  ui.make_move_handler(s, "U")() -- breaks solved; no popup
  T.falsy(s.solve_popup, "no popup yet after U")
  ui.make_move_handler(s, "U'")() -- back to solved
  T.truthy(s.was_solved, "was_solved updated on solve transition")
  ui.make_quit_handler(s)()
end)

T.test("solve detection does NOT fire if timer was never started", function()
  -- Without ever pressing Space, a trivial U then U' should NOT count as a solve.
  local s = ui.open()
  ui.make_move_handler(s, "U")()
  ui.make_move_handler(s, "U'")()
  T.truthy(cube.is_solved(s.state))
  vim.wait(400, function()
    return s.solve_popup ~= nil
  end)
  T.falsy(s.solve_popup, "no popup when timer was never started")
  T.eq(s.timer_elapsed_ms, nil, "timer remains idle")
  ui.make_quit_handler(s)()
end)

T.test("solve detection DOES fire after timer is started (even if paused before solve)", function()
  local s = ui.open()
  ui.make_space_handler(s)() -- start
  ui.make_space_handler(s)() -- pause -- elapsed_ms is now set
  T.truthy(s.timer_elapsed_ms)
  ui.make_move_handler(s, "U")()
  ui.make_move_handler(s, "U'")()
  vim.wait(400, function()
    return s.solve_popup ~= nil
  end)
  T.truthy(s.solve_popup, "popup should fire after a timed attempt")
  if s.solve_popup and s.solve_popup.close then
    s.solve_popup.close()
  end
  ui.make_quit_handler(s)()
end)

T.test("solve detection does NOT fire after scramble cleared a previous timer", function()
  -- Timer was used, but then scramble reset it — the new attempt has no timer yet.
  local s = ui.open()
  ui.make_space_handler(s)()
  ui.make_space_handler(s)() -- use timer once
  T.truthy(s.timer_elapsed_ms)
  ui.make_scramble_handler(s)()
  T.eq(s.timer_elapsed_ms, nil)
  -- Reset the cube to solved manually (cleaner than reversing the scramble),
  -- then do a no-op-style U U' to test that solve detection stays silent.
  ui.make_reset_handler(s)()
  ui.make_move_handler(s, "U")()
  ui.make_move_handler(s, "U'")()
  vim.wait(400, function()
    return s.solve_popup ~= nil
  end)
  T.falsy(s.solve_popup, "no popup when timer is reset by scramble")
  ui.make_quit_handler(s)()
end)

-- ============ Solve-lock: only celebrate / count once per attempt ============

T.test("move counter does NOT advance when timer is idle", function()
  local s = ui.open()
  ui.make_move_handler(s, "U")()
  ui.make_move_handler(s, "R")()
  ui.make_move_handler(s, "F")()
  T.eq(s.move_count, 0, "count stays at 0 with no timer running")
  T.eq(s.last_move, "F", "last_move still updates")
  ui.make_quit_handler(s)()
end)

T.test("move counter resumes counting when timer starts after some idle moves", function()
  local s = ui.open()
  ui.make_move_handler(s, "U")() -- not counted (no timer)
  T.eq(s.move_count, 0)
  ui.make_space_handler(s)() -- start timer
  ui.make_move_handler(s, "R")()
  ui.make_move_handler(s, "F")()
  T.eq(s.move_count, 2, "only post-timer moves count")
  ui.make_quit_handler(s)()
end)

T.test("solve celebration only fires once per attempt", function()
  -- After a timed solve, subsequent solves (from re-scrambling by hand) must not popup.
  local s = ui.open()
  ui.make_space_handler(s)() -- start timer
  ui.make_move_handler(s, "U")()
  ui.make_move_handler(s, "U'")() -- solved → first celebration
  vim.wait(400, function()
    return s.solve_popup ~= nil
  end)
  T.truthy(s.solve_popup, "first solve fires popup")
  if s.solve_popup and s.solve_popup.close then
    s.solve_popup.close()
  end
  s.solve_popup = nil
  -- Now mess up the cube and solve again without resetting.
  ui.make_move_handler(s, "R")()
  ui.make_move_handler(s, "R'")()
  vim.wait(400, function()
    return s.solve_popup ~= nil
  end)
  T.falsy(s.solve_popup, "second solve in same attempt does NOT fire popup")
  ui.make_quit_handler(s)()
end)

T.test("move counter freezes after solve celebration", function()
  local s = ui.open()
  ui.make_space_handler(s)() -- start timer
  ui.make_move_handler(s, "U")() -- count = 1
  ui.make_move_handler(s, "U'")() -- count = 2, celebrates
  T.eq(s.move_count, 2)
  T.truthy(s.solve_locked, "locked after celebration")
  ui.make_move_handler(s, "R")() -- should NOT count
  ui.make_move_handler(s, "R'")() -- should NOT count, no new popup
  T.eq(s.move_count, 2, "counter frozen post-solve")
  ui.make_quit_handler(s)()
end)

T.test("reset clears solve_lock so a new attempt can count and celebrate", function()
  local s = ui.open()
  ui.make_space_handler(s)()
  ui.make_move_handler(s, "U")()
  ui.make_move_handler(s, "U'")() -- celebrates, locks
  T.truthy(s.solve_locked)
  ui.make_reset_handler(s)()
  T.falsy(s.solve_locked, "reset clears solve_locked")
  -- Fresh attempt: start timer, scramble-and-solve quickly.
  ui.make_space_handler(s)()
  ui.make_move_handler(s, "U")()
  T.eq(s.move_count, 1, "new attempt counts from 1")
  ui.make_quit_handler(s)()
end)

T.test("scramble clears solve_lock", function()
  local s = ui.open()
  ui.make_space_handler(s)()
  ui.make_move_handler(s, "U")()
  ui.make_move_handler(s, "U'")()
  T.truthy(s.solve_locked)
  ui.make_scramble_handler(s)()
  T.falsy(s.solve_locked, "scramble clears solve_locked")
  ui.make_quit_handler(s)()
end)

-- ============ Reopen no-op, public entry point ============

T.test("rubikscube.open() returns existing session when one is already open", function()
  local mod = require("rubikscube")
  mod._session = nil -- reset module-level state
  local s1 = mod.open()
  T.truthy(s1.buf, "first call creates a session")
  local buf1 = s1.buf
  local s2 = mod.open()
  T.eq(s1, s2, "second call returns the same session")
  T.eq(s2.buf, buf1, "buffer not replaced")
  ui.make_quit_handler(s1)()
  T.eq(mod._session, nil, "on_close clears module session pointer")
end)

T.test("rubikscube.open() after quit creates a fresh session", function()
  local mod = require("rubikscube")
  mod._session = nil
  local s1 = mod.open()
  local buf1 = s1.buf
  ui.make_quit_handler(s1)()
  T.eq(mod._session, nil)
  local s2 = mod.open()
  T.truthy(s2.buf, "new session after quit")
  T.truthy(s2.buf ~= buf1, "fresh buffer handle")
  ui.make_quit_handler(s2)()
end)

T.test("rubikscube.setup() merges keymap overrides into config", function()
  local mod = require("rubikscube")
  config.reset()
  mod.setup({ keymaps = { quit = "Q", scramble = "S" } })
  T.eq(config.get().keymaps.quit, "Q")
  T.eq(config.get().keymaps.scramble, "S")
  T.eq(config.get().keymaps.reset, "<CR>", "untouched keys keep defaults")
  config.reset()
end)

-- ============ Configurable keymaps ============

T.test("open registers custom action keys from config", function()
  config.reset()
  config.apply({ keymaps = { quit = "Q", scramble = "S", timer = "t" } })
  local s = ui.open()
  local maps = vim.api.nvim_buf_get_keymap(s.buf, "n")
  local lhs_set = {}
  for _, m in ipairs(maps) do
    lhs_set[m.lhs] = true
  end
  T.truthy(lhs_set["Q"], "custom quit key bound")
  T.truthy(lhs_set["S"], "custom scramble key bound")
  T.truthy(lhs_set["t"], "custom timer key bound")
  T.falsy(lhs_set["q"], "default quit key NOT bound")
  ui.make_quit_handler(s)()
  config.reset()
end)

T.test("build_move_keymap rebases face turns onto custom letters", function()
  config.reset()
  config.apply({ keymaps = { U = "j", R = "k" } })
  local km = ui._for_test.build_move_keymap()
  -- Locate the entries for our overridden faces.
  local seen = {}
  for _, pair in ipairs(km) do
    seen[pair[1]] = pair[2]
  end
  T.eq(seen["j"], "U", "j → U CW")
  T.eq(seen["J"], "U'", "J → U' CCW")
  T.eq(seen["k"], "R", "k → R CW")
  T.eq(seen["K"], "R'", "K → R' CCW")
  -- Untouched defaults still present:
  T.eq(seen["d"], "D", "default d → D survives")
  config.reset()
end)

-- ============ External buffer wipe triggers teardown ============

T.test("BufWipeout from outside the quit handler still stops the timer", function()
  local s = ui.open()
  ui.make_space_handler(s)() -- start timer & ticker
  T.truthy(s.timer_handle)
  vim.api.nvim_buf_delete(s.buf, { force = true }) -- simulate :bwipeout
  -- BufWipeout autocmd should have fired teardown synchronously.
  T.eq(s.timer_handle, nil, "ticker stopped on BufWipeout")
  T.eq(s.autocmd_group, nil, "autocmd group cleaned up")
end)

T.test("on_close callback fires exactly once even with both quit and wipe paths", function()
  local count = 0
  local session = ui.open(nil, function()
    count = count + 1
  end)
  ui.make_quit_handler(session)()
  T.eq(count, 1, "on_close fired once")
  -- Calling teardown again should be a no-op (session.on_close was cleared).
  ui._for_test.teardown(session)
  T.eq(count, 1, "still 1")
end)

-- ============ Best-time persistence ============

T.test("best.maybe_update records the first solve as a new best", function()
  clear_best()
  local prior, is_new = best.maybe_update(12345, 30)
  T.eq(prior, nil, "no prior best")
  T.truthy(is_new, "first solve sets a new best")
  local saved = best.read()
  T.eq(saved.time_ms, 12345)
  T.eq(saved.move_count, 30)
end)

T.test("best.maybe_update keeps prior when new time is slower", function()
  clear_best()
  best.maybe_update(10000, 20)
  local prior, is_new = best.maybe_update(15000, 25)
  T.eq(prior, 10000, "prior reported")
  T.falsy(is_new, "slower attempt is not a new best")
  T.eq(best.read().time_ms, 10000, "file unchanged")
end)

T.test("best.maybe_update updates when new time is faster", function()
  clear_best()
  best.maybe_update(10000, 20)
  local prior, is_new = best.maybe_update(8000, 18)
  T.eq(prior, 10000, "prior best reported")
  T.truthy(is_new, "faster attempt is a new best")
  T.eq(best.read().time_ms, 8000)
  T.eq(best.read().move_count, 18)
end)

T.test("best.maybe_update is a no-op when elapsed_ms is nil", function()
  clear_best()
  best.maybe_update(10000, 20)
  local prior, is_new = best.maybe_update(nil, 0)
  T.eq(prior, nil)
  T.falsy(is_new)
  T.eq(best.read().time_ms, 10000, "file unchanged when elapsed missing")
end)

T.test("celebrate_solve persists the timed solve as a best", function()
  clear_best()
  local s = ui.open()
  ui.make_space_handler(s)() -- start timer
  -- Fake elapsed time by backdating start_ms.
  s.timer_start_ms = (vim.uv or vim.loop).now() - 2000
  ui.make_move_handler(s, "U")()
  ui.make_move_handler(s, "U'")() -- solve transition
  vim.wait(400, function()
    return s.solve_popup ~= nil
  end)
  T.truthy(s.solve_popup)
  local saved = best.read()
  T.truthy(saved, "best file written")
  T.truthy(saved.time_ms >= 2000, "saved time reflects backdated start_ms")
  if s.solve_popup and s.solve_popup.close then
    s.solve_popup.close()
  end
  ui.make_quit_handler(s)()
end)

-- ============ Skip-on-false: disabling specific keys ============

T.test("setting an action key to false skips that binding", function()
  config.reset()
  config.apply({ keymaps = { help = false, quit = false } })
  local s = ui.open()
  local maps = vim.api.nvim_buf_get_keymap(s.buf, "n")
  local lhs = {}
  for _, m in ipairs(maps) do
    lhs[m.lhs] = true
  end
  T.falsy(lhs["?"], "help binding skipped")
  T.falsy(lhs["q"], "quit binding skipped")
  T.truthy(lhs["s"], "scramble still bound")
  -- Clean up: buffer needs manual wipe since quit is unbound.
  if s.buf and vim.api.nvim_buf_is_valid(s.buf) then
    vim.api.nvim_buf_delete(s.buf, { force = true })
  end
  config.reset()
end)

T.test("setting a face key to false omits both CW and CCW bindings", function()
  config.reset()
  config.apply({ keymaps = { B = false } })
  local s = ui.open()
  local maps = vim.api.nvim_buf_get_keymap(s.buf, "n")
  local lhs = {}
  for _, m in ipairs(maps) do
    lhs[m.lhs] = true
  end
  T.falsy(lhs["b"], "b not bound when B = false")
  T.falsy(lhs["B"], "B not bound either")
  T.truthy(lhs["u"], "other faces still bound")
  ui.make_quit_handler(s)()
  config.reset()
end)

T.test("build_move_keymap omits disabled faces and rotations", function()
  config.reset()
  config.apply({ keymaps = { U = false, z = false } })
  local km = ui._for_test.build_move_keymap()
  local keys, moves = {}, {}
  for _, p in ipairs(km) do
    keys[p[1]] = true
    moves[p[2]] = true
  end
  T.falsy(keys["u"])
  T.falsy(keys["U"])
  T.falsy(moves["U"])
  T.falsy(moves["U'"])
  T.falsy(keys["z"])
  T.falsy(keys["Z"])
  T.truthy(keys["d"], "untouched faces present")
  config.reset()
end)

-- ============ scramble_length config knob ============

T.test("scramble_length config controls the number of random moves", function()
  config.reset()
  config.apply({ scramble_length = 0 }) -- 0 moves → cube remains solved
  local s = ui.open()
  T.truthy(cube.is_solved(s.state))
  ui.make_scramble_handler(s)()
  T.truthy(cube.is_solved(s.state), "scramble_length=0 leaves cube solved")
  T.eq(s.last_move, "scramble")
  ui.make_quit_handler(s)()
  config.reset()
end)

T.test("default scramble_length still produces a scrambled cube", function()
  config.reset()
  local s = ui.open()
  ui.make_scramble_handler(s)()
  T.falsy(cube.is_solved(s.state), "default 20 moves scrambles")
  ui.make_quit_handler(s)()
end)

-- ============ persist_best toggle ============

T.test("persist_best = false skips writing best.json on solve", function()
  config.reset()
  clear_best()
  config.apply({ persist_best = false })
  local s = ui.open()
  ui.make_space_handler(s)()
  s.timer_start_ms = (vim.uv or vim.loop).now() - 3000
  ui.make_move_handler(s, "U")()
  ui.make_move_handler(s, "U'")()
  vim.wait(400, function()
    return s.solve_popup ~= nil
  end)
  T.truthy(s.solve_popup, "popup still fires")
  T.eq(best.read(), nil, "best.json NOT written when persist_best=false")
  if s.solve_popup and s.solve_popup.close then
    s.solve_popup.close()
  end
  ui.make_quit_handler(s)()
  config.reset()
end)

T.test("persist_best = false still reads existing best.json", function()
  config.reset()
  clear_best()
  -- Seed a prior best directly.
  best.write({ time_ms = 5000, move_count = 12, recorded_at = 0 })
  config.apply({ persist_best = false })
  local s = ui.open()
  ui.make_space_handler(s)()
  s.timer_start_ms = (vim.uv or vim.loop).now() - 10000 -- slower than seed
  ui.make_move_handler(s, "U")()
  ui.make_move_handler(s, "U'")()
  vim.wait(400, function()
    return s.solve_popup ~= nil
  end)
  T.truthy(s.solve_popup)
  local still = best.read()
  T.truthy(still, "seed best.json untouched")
  T.eq(still.time_ms, 5000, "still the seeded value")
  if s.solve_popup and s.solve_popup.close then
    s.solve_popup.close()
  end
  ui.make_quit_handler(s)()
  config.reset()
end)

-- ============ Dynamic help text + status-line hints ============

T.test("help text reflects remapped face keys", function()
  config.reset()
  config.apply({ keymaps = { U = "j", quit = "Q" } })
  local s = ui.open()
  ui.make_help_handler(s)()
  local lines = vim.api.nvim_buf_get_lines(s.help_buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  T.truthy(text:find("j / J", 1, true), "shows j / J for remapped U")
  T.falsy(text:find("u / U", 1, true), "no stale u / U")
  T.truthy(text:find("Q", 1, true), "shows Q for remapped quit")
  ui.make_quit_handler(s)()
  config.reset()
end)

T.test("help text omits lines for disabled keys", function()
  config.reset()
  config.apply({ keymaps = { B = false, help = false } })
  local s = ui.open()
  -- help is disabled, so directly call the internal lines builder via open_help
  -- side effect: open_help skips when help_win exists; instead build text directly.
  -- Easiest path: tap make_help_handler still functions (the *function* is callable)
  -- but the binding doesn't exist. Open help programmatically:
  ui.make_help_handler(s)()
  local lines = vim.api.nvim_buf_get_lines(s.help_buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  T.falsy(text:find("b / B", 1, true), "no B-face line")
  T.falsy(text:find("toggle this help", 1, true), "no help action line")
  ui.make_quit_handler(s)()
  config.reset()
end)

T.test("build_hints reflects remapped action keys and skips disabled ones", function()
  config.reset()
  config.apply({ keymaps = { quit = "Q", help = false } })
  local hints = ui._for_test.build_hints()
  T.truthy(hints:find("[Q] quit", 1, true), "remapped quit appears")
  T.falsy(hints:find("help", 1, true), "help omitted")
  T.truthy(hints:find("scramble", 1, true), "other actions still listed")
  config.reset()
end)

T.test("default build_hints includes every action", function()
  config.reset()
  local hints = ui._for_test.build_hints()
  for _, verb in ipairs({ "timer", "scramble", "reset", "help", "quit" }) do
    T.truthy(hints:find(verb, 1, true), "hints include " .. verb)
  end
end)

-- ============ open_in window placement ============

T.test("open_in = 'split' opens the cube in a horizontal split", function()
  config.reset()
  local wins_before = #vim.api.nvim_list_wins()
  config.apply({ open_in = "split" })
  local s = ui.open()
  local wins_after = #vim.api.nvim_list_wins()
  T.eq(wins_after, wins_before + 1, "one new window")
  T.eq(vim.api.nvim_get_current_buf(), s.buf, "cube buffer is current")
  ui.make_quit_handler(s)()
  config.reset()
end)

T.test("open_in = 'float' opens the cube in a floating window", function()
  config.reset()
  config.apply({ open_in = "float" })
  local s = ui.open()
  local cfg = vim.api.nvim_win_get_config(0)
  T.truthy(cfg.relative ~= nil and cfg.relative ~= "", "current window is floating")
  T.eq(vim.api.nvim_get_current_buf(), s.buf)
  ui.make_quit_handler(s)()
  config.reset()
end)

T.test("open_in defaults to float", function()
  config.reset()
  local s = ui.open()
  local cfg = vim.api.nvim_win_get_config(0)
  T.truthy(cfg.relative ~= nil and cfg.relative ~= "", "default opens floating")
  T.eq(vim.api.nvim_get_current_buf(), s.buf)
  ui.make_quit_handler(s)()
end)

T.test("open_in = 'current' replaces the current buffer (no new wins)", function()
  config.reset()
  config.apply({ open_in = "current" })
  local wins_before = #vim.api.nvim_list_wins()
  local s = ui.open()
  T.eq(#vim.api.nvim_list_wins(), wins_before, "no new windows created")
  T.eq(vim.api.nvim_get_current_buf(), s.buf)
  ui.make_quit_handler(s)()
  config.reset()
end)

-- ============ public `rubikscube.current_session()` accessor ============

T.test("current_session returns nil when no cube is open", function()
  local rubiks = require("rubikscube")
  rubiks._session = nil
  T.eq(rubiks.current_session(), nil)
end)

T.test("current_session returns the session while a cube is open", function()
  local rubiks = require("rubikscube")
  config.reset()
  local s = rubiks.open()
  T.truthy(s)
  T.truthy(rubiks.current_session() == s, "same session ref")
  ui.make_quit_handler(s)()
  T.eq(rubiks.current_session(), nil, "after quit, no session")
end)
