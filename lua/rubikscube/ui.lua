-- Buffer + keymap setup. Each move handler mutates state and triggers a repaint.

local cube = require("rubikscube.cube")
local render = require("rubikscube.render")
local config = require("rubikscube.config")
local best = require("rubikscube.best")
local solver = require("rubikscube.solver")
local animate = require("rubikscube.animate")
local tutorial = require("rubikscube.tutorial")

local M = {}

-- Default keymap table: { key, move_or_action }. Lowercase = clockwise face turn,
-- uppercase = prime (counter-clockwise). x/y/z = whole-cube rotations.
-- This reflects the *defaults*; the actual bindings registered by M.open()
-- come from `config.get().keymaps`.
M.KEYMAP = {
  { "u", "U" },
  { "U", "U'" },
  { "d", "D" },
  { "D", "D'" },
  { "l", "L" },
  { "L", "L'" },
  { "r", "R" },
  { "R", "R'" },
  { "f", "F" },
  { "F", "F'" },
  { "b", "B" },
  { "B", "B'" },
  { "x", "x" },
  { "X", "x'" },
  { "y", "y" },
  { "Y", "y'" },
  { "z", "z" },
  { "Z", "z'" },
}

M.ACTION_KEYS = { "s", "<CR>", "q", "?", "t", "n" } -- non-move keys (defaults)

-- Build the active move-keymap from current config. For each face/rotation letter,
-- the lowercase variant binds CW and the uppercase variant binds prime (CCW).
local function build_move_keymap()
  local km = config.get().keymaps
  local result = {}
  local function pair(letter, move)
    if not letter then
      return
    end -- disabled
    result[#result + 1] = { letter, move }
    result[#result + 1] = { letter:upper(), move .. "'" }
  end
  for _, face in ipairs({ "U", "D", "L", "R", "F", "B" }) do
    pair(km[face], face)
  end
  for _, rot in ipairs({ "x", "y", "z" }) do
    pair(km[rot], rot)
  end
  return result
end

local ROT_AXIS = { x = "R", y = "U", z = "F" }

local function build_hints()
  local km = config.get().keymaps
  local entries = {
    { km.timer, "timer" },
    { km.scramble, "scramble" },
    { km.solve, "solve" },
    { km.tutorial, "tutorial" },
    { km.reset, "reset" },
    { km.help, "help" },
    { km.quit, "quit" },
  }
  local parts = {}
  for _, e in ipairs(entries) do
    if e[1] then
      parts[#parts + 1] = string.format("[%s] %s", e[1], e[2])
    end
  end
  return table.concat(parts, "  ")
end

local function help_text(_session)
  local cfg = config.get()
  local km = cfg.keymaps
  local lines = {
    "  Rubik's Cube — Controls",
    "",
    "  Face turns (lowercase = CW, uppercase = CCW / prime):",
  }
  for _, face in ipairs({ "U", "D", "L", "R", "F", "B" }) do
    local k = km[face]
    if k then
      lines[#lines + 1] = string.format("    %s / %s   →  %s  /  %s'", k, k:upper(), face, face)
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  Whole-cube rotations (to see hidden faces):"
  for _, rot in ipairs({ "x", "y", "z" }) do
    local k = km[rot]
    if k then
      lines[#lines + 1] = string.format(
        "    %s / %s   →  rotate around %s axis (CW / CCW)",
        k,
        k:upper(),
        ROT_AXIS[rot]
      )
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  Actions:"
  local action_rows = {
    { km.scramble, string.format("scramble (%d random moves)", cfg.scramble_length) },
    { km.solve, "auto-solve (requires external `kociemba`)" },
    { km.tutorial, "tutorial: learn to solve it yourself" },
    { km.tutorial_step, "tutorial: apply the next move" },
    { km.timer, "start / stop the timer" },
    { km.reset, "reset to solved (clears timer)" },
    { km.help, "toggle this help" },
    { km.quit, "quit" },
  }
  for _, row in ipairs(action_rows) do
    if row[1] then
      lines[#lines + 1] = string.format("    %-7s →  %s", row[1], row[2])
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  Solve detection auto-stops the timer and shows a result popup."
  return lines
end

local function close_help(session)
  if session.help_win and vim.api.nvim_win_is_valid(session.help_win) then
    vim.api.nvim_win_close(session.help_win, true)
  end
  if session.help_buf and vim.api.nvim_buf_is_valid(session.help_buf) then
    vim.api.nvim_buf_delete(session.help_buf, { force = true })
  end
  session.help_win = nil
  session.help_buf = nil
end

local function open_help(session)
  if session.help_win and vim.api.nvim_win_is_valid(session.help_win) then
    close_help(session)
    return
  end
  local lines = help_text(session)
  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, #l)
  end
  local height = #lines
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = 2,
    col = 2,
    width = width + 2,
    height = height,
    border = "rounded",
    style = "minimal",
    focusable = false,
    -- Above the cube float: among equal-zindex floats Neovim raises the
    -- *focused* one, which would hide this non-focusable overlay behind
    -- the (focused) cube window.
    zindex = 60,
  })
  session.help_buf = buf
  session.help_win = win
end

local function cancel_animation(session)
  if session.anim_handle then
    local h = session.anim_handle
    session.anim_handle = nil
    pcall(function()
      h:cancel()
    end)
  end
  session.auto_solving = false
end

-- Tear down session resources (timer, popups, help, autocmds). Idempotent —
-- safe to call from both the `q` handler and a BufWipeout autocmd.
local function teardown(session)
  close_help(session)
  cancel_animation(session)
  tutorial.stop(session)
  if session.timer_handle then
    session.timer_handle:stop()
    session.timer_handle:close()
    session.timer_handle = nil
  end
  if session.solve_popup and session.solve_popup.close then
    pcall(session.solve_popup.close)
    session.solve_popup = nil
  end
  if session.autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, session.autocmd_group)
    session.autocmd_group = nil
  end
  if session.on_close then
    local cb = session.on_close
    session.on_close = nil
    pcall(cb)
  end
end

-- Quit handler — wipes the buffer (which fires BufWipeout → teardown).
local function do_quit(session)
  if session.buf and vim.api.nvim_buf_is_valid(session.buf) then
    vim.api.nvim_buf_delete(session.buf, { force = true })
  else
    teardown(session)
  end
  session.buf = nil
end

-- The main session table holds state, buffer handle, and meta info.
function M.new_session()
  return {
    state = cube.new(),
    buf = nil,
    last_move = nil,
    move_count = 0,
    help_buf = nil,
    help_win = nil,
    -- timer state
    timer_running = false,
    timer_start_ms = nil, -- vim.uv.now() value at start
    timer_elapsed_ms = nil, -- nil = idle (never started since last reset); number = paused/finished
    timer_handle = nil, -- vim.uv timer
    -- solve detection
    was_solved = true,
    solve_popup = nil,
    -- Set true once a timed attempt has been celebrated; freezes the move
    -- counter and suppresses further popups until reset/scramble.
    solve_locked = false,
    -- auto-solve animation (external kociemba). Mutually exclusive with
    -- timed/manual play: while auto_solving is true, move_count is frozen
    -- and the solve-celebration popup is suppressed.
    auto_solving = false,
    anim_handle = nil,
    -- autocmd group id; on_close fires once after the cube is torn down.
    autocmd_group = nil,
    on_close = nil,
  }
end

local function now_ms()
  return (vim.uv or vim.loop).now()
end

local function current_elapsed(session)
  if session.timer_running then
    return now_ms() - session.timer_start_ms
  end
  return session.timer_elapsed_ms
end

local function repaint_info(session)
  return {
    last_move = session.last_move,
    move_count = session.move_count,
    elapsed_ms = current_elapsed(session),
    timer_running = session.timer_running,
    hints = build_hints(),
  }
end

local function repaint_full(session)
  if session.buf and vim.api.nvim_buf_is_valid(session.buf) then
    render.repaint(session.buf, session.state, repaint_info(session))
  end
end

local function repaint_status(session)
  if session.buf and vim.api.nvim_buf_is_valid(session.buf) then
    render.repaint_status(session.buf, repaint_info(session))
  end
end

local function stop_ticker(session)
  if session.timer_handle then
    session.timer_handle:stop()
    session.timer_handle:close()
    session.timer_handle = nil
  end
end

local function start_ticker(session)
  stop_ticker(session)
  local handle = (vim.uv or vim.loop).new_timer()
  handle:start(
    100,
    100,
    vim.schedule_wrap(function()
      if session.timer_running then
        repaint_status(session)
      else
        stop_ticker(session)
      end
    end)
  )
  session.timer_handle = handle
end

local function start_timer(session)
  -- Resume from prior accumulated time if Space was previously pressed to stop.
  -- Only <CR>/scramble fully reset to zero (via reset_timer).
  local prior = session.timer_elapsed_ms or 0
  session.timer_start_ms = now_ms() - prior
  session.timer_elapsed_ms = nil
  session.timer_running = true
  start_ticker(session)
end

local function stop_timer(session)
  if session.timer_running then
    session.timer_elapsed_ms = now_ms() - session.timer_start_ms
    session.timer_running = false
    stop_ticker(session)
  end
end

local function reset_timer(session)
  stop_ticker(session)
  session.timer_running = false
  session.timer_start_ms = nil
  session.timer_elapsed_ms = nil
end

M._for_test = M._for_test or {}
M._for_test.current_elapsed = current_elapsed
M._for_test.start_timer = start_timer
M._for_test.stop_timer = stop_timer
M._for_test.reset_timer = reset_timer

local function celebrate_solve(session)
  -- Auto-stop timer on solve. Then flash + popup.
  stop_timer(session)
  local elapsed = session.timer_elapsed_ms -- may be nil if user never started the timer
  local moves = session.move_count
  local prior_best, is_new_best
  if config.get().persist_best then
    prior_best, is_new_best = best.maybe_update(elapsed, moves)
  else
    -- Read-only: surface any existing best.json but never write.
    local prior = best.read()
    prior_best = prior and prior.time_ms or nil
    is_new_best = false
  end
  render.flash(250, function()
    repaint_full(session)
    session.solve_popup = render.show_solve_popup(
      elapsed,
      moves,
      prior_best,
      is_new_best,
      function()
        session.solve_popup = nil
      end
    )
  end)
end

local function timer_active(session)
  -- True if the timer has been started at least once since the last reset/scramble.
  return session.timer_running or session.timer_elapsed_ms ~= nil
end

function M.make_move_handler(session, move)
  return function()
    -- Pressing a move key during auto-solve cancels the animation and lets the
    -- user take over: the keystroke still applies as a normal manual move.
    if session.auto_solving then
      cancel_animation(session)
    end
    local was_solved = cube.is_solved(session.state)
    cube.apply(session.state, move)
    session.last_move = move
    local active = timer_active(session)
    if active and not session.solve_locked then
      session.move_count = session.move_count + 1
    end
    session.was_solved = cube.is_solved(session.state)
    repaint_full(session)
    if session.was_solved and not was_solved and active and not session.solve_locked then
      session.solve_locked = true
      celebrate_solve(session)
    end
    -- A manual move during the tutorial: advance if it was the expected
    -- move, re-plan otherwise.
    tutorial.on_manual_move(session, move)
  end
end

function M.make_scramble_handler(session)
  return function()
    cancel_animation(session)
    cube.scramble(session.state, config.get().scramble_length or 20)
    session.last_move = "scramble"
    session.move_count = 0
    reset_timer(session)
    session.was_solved = cube.is_solved(session.state)
    session.solve_locked = false
    repaint_full(session)
    tutorial.refresh(session)
  end
end

function M.make_reset_handler(session)
  return function()
    cancel_animation(session)
    tutorial.stop(session)
    cube.reset(session.state)
    session.last_move = "reset"
    session.move_count = 0
    reset_timer(session)
    session.was_solved = true
    session.solve_locked = false
    repaint_full(session)
  end
end

function M.make_solve_handler(session)
  return function()
    if session.auto_solving then
      vim.notify("rubikscube: auto-solve already running", vim.log.levels.INFO)
      return
    end
    if cube.is_solved(session.state) then
      vim.notify("rubikscube: cube is already solved", vim.log.levels.INFO)
      return
    end
    if not solver.is_available() then
      vim.notify("rubikscube: " .. solver.INSTALL_HINT, vim.log.levels.WARN)
      return
    end
    tutorial.stop(session) -- auto-solve takes over from a running tutorial
    session.auto_solving = true
    session.last_move = "solving…"
    repaint_full(session)
    solver.solve_async(session.state, function(moves, err)
      -- The user may have cancelled (manual move / scramble / reset / quit)
      -- between the time the solver was kicked off and the time it returned.
      -- If so, don't start an animation behind their back.
      if not session.auto_solving then
        return
      end
      if err then
        session.auto_solving = false
        session.last_move = nil
        repaint_full(session)
        vim.notify("rubikscube: " .. err, vim.log.levels.ERROR)
        return
      end
      local tempo = (config.get().solver or {}).tempo_ms or 200
      session.anim_handle = animate.play({
        state = session.state,
        moves = moves,
        tempo_ms = tempo,
        on_step = function(move)
          session.last_move = move
          session.was_solved = cube.is_solved(session.state)
          repaint_full(session)
        end,
        on_done = function()
          session.auto_solving = false
          session.anim_handle = nil
          session.was_solved = cube.is_solved(session.state)
          repaint_full(session)
        end,
        on_cancel = function()
          session.auto_solving = false
          session.anim_handle = nil
          repaint_full(session)
        end,
      })
    end)
  end
end

-- Toggle the beginner-method tutorial. Mutually exclusive with auto-solve.
function M.make_tutorial_handler(session)
  return function()
    if tutorial.is_active(session) then
      tutorial.stop(session)
      return
    end
    cancel_animation(session)
    tutorial.start(session, function()
      repaint_full(session)
    end)
  end
end

function M.make_tutorial_step_handler(session)
  return function()
    tutorial.step(session)
  end
end

function M.make_space_handler(session)
  return function()
    if session.timer_running then
      stop_timer(session)
    else
      start_timer(session)
    end
    repaint_full(session)
  end
end

function M.make_quit_handler(session)
  return function()
    do_quit(session)
  end
end

function M.make_help_handler(session)
  return function()
    open_help(session)
  end
end

local function bind(buf, key, fn, desc)
  vim.keymap.set("n", key, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
end

-- Open the cube UI: creates a buffer, opens it in the current window, registers keymaps,
-- and renders the initial state. Returns the session table.
-- `on_close` (optional) is invoked once after the session is torn down — used by
-- the public entry point in lua/rubikscube/init.lua to clear its session pointer.
function M.open(session, on_close)
  session = session or M.new_session()
  session.on_close = on_close
  render.setup()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "rubikscube"
  session.buf = buf

  -- Move keymaps from current config.
  for _, km in ipairs(build_move_keymap()) do
    bind(buf, km[1], M.make_move_handler(session, km[2]), "Rubik's: " .. km[2])
  end
  -- Actions from current config; each key may be false to skip the bind.
  local actions = config.get().keymaps
  local action_binds = {
    { actions.scramble, M.make_scramble_handler(session), "Rubik's: scramble" },
    { actions.solve, M.make_solve_handler(session), "Rubik's: auto-solve" },
    { actions.tutorial, M.make_tutorial_handler(session), "Rubik's: tutorial" },
    { actions.tutorial_step, M.make_tutorial_step_handler(session), "Rubik's: tutorial next move" },
    { actions.reset, M.make_reset_handler(session), "Rubik's: reset" },
    { actions.timer, M.make_space_handler(session), "Rubik's: timer toggle" },
    { actions.quit, M.make_quit_handler(session), "Rubik's: quit" },
    { actions.help, M.make_help_handler(session), "Rubik's: help" },
  }
  for _, b in ipairs(action_binds) do
    if b[1] then
      bind(buf, b[1], b[2], b[3])
    end
  end

  -- Tear down on external buffer wipe (e.g., :bdelete, :bwipeout, window close).
  local group = vim.api.nvim_create_augroup("rubikscube_session_" .. buf, { clear = true })
  session.autocmd_group = group
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function()
      teardown(session)
    end,
  })

  -- Window placement per config.open_in.
  local mode = config.get().open_in
  if mode == "split" then
    vim.cmd("split")
    vim.api.nvim_set_current_buf(buf)
  elseif mode == "vsplit" then
    vim.cmd("vsplit")
    vim.api.nvim_set_current_buf(buf)
  elseif mode == "float" then
    local total_w, total_h = vim.o.columns, vim.o.lines
    local w = math.min(140, math.max(40, total_w - 4))
    local h = math.min(18, math.max(15, total_h - 4))
    vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      anchor = "NW",
      title = " Rubik's Cube ",
      title_pos = "center",
      row = math.max(0, math.floor((total_h - h) / 2)),
      col = math.max(0, math.floor((total_w - w) / 2)),
      width = w,
      height = h,
      border = "rounded",
      style = "minimal",
      noautocmd = true,
    })
  else
    vim.api.nvim_set_current_buf(buf)
  end

  render.repaint(buf, session.state, {
    last_move = nil,
    move_count = 0,
    hints = build_hints(),
  })

  return session
end

M._for_test.build_move_keymap = build_move_keymap
M._for_test.build_hints = build_hints
M._for_test.teardown = teardown

return M
