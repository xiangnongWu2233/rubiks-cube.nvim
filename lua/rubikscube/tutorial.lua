-- Tutorial mode: walk the user through solving their own cube with the
-- beginner layer-by-layer method, one explained move at a time.
--
-- The controller owns a side panel (floating window) showing the current
-- stage, its explanation, and the next move. The user advances with the
-- step key; manual moves are allowed at any time — the solution is simply
-- recomputed from the new state (lbl.solve runs in well under a millisecond).

local cube = require("rubikscube.cube")
local lbl = require("rubikscube.lbl")
local config = require("rubikscube.config")

local M = {}

function M.is_active(session)
  return session.tutorial ~= nil
end

-- Wrap `text` to `width`, returning a list of lines.
local function wrap(text, width)
  local lines, line = {}, ""
  for word in text:gmatch("%S+") do
    if line == "" then
      line = word
    elseif #line + 1 + #word <= width then
      line = line .. " " .. word
    else
      lines[#lines + 1] = line
      line = word
    end
  end
  if line ~= "" then
    lines[#lines + 1] = line
  end
  return lines
end

local ROTATIONS = { x = true, ["x'"] = true, y = true, ["y'"] = true, z = true, ["z'"] = true }

local function describe_move(move)
  if ROTATIONS[move] then
    return move .. "  (turn the whole cube)"
  end
  return move
end

-- Advance (stage_idx, move_idx) past empty stages; returns nil when done.
local function current_position(tut)
  while tut.stage_idx <= #tut.solution.stages do
    local stage = tut.solution.stages[tut.stage_idx]
    if tut.move_idx <= #stage.moves then
      return stage, stage.moves[tut.move_idx]
    end
    tut.stage_idx = tut.stage_idx + 1
    tut.move_idx = 1
  end
  return nil
end

local function panel_lines(session)
  local tut = session.tutorial
  local stage, next_move = current_position(tut)
  local width = 44
  local lines = { "  Tutorial — beginner method", "" }
  if not stage then
    lines[#lines + 1] = "  Cube solved — well done!"
    return lines, width
  end
  lines[#lines + 1] =
    string.format("  Stage %d/%d: %s", tut.stage_idx, #tut.solution.stages, stage.name)
  lines[#lines + 1] = ""
  for _, l in ipairs(wrap(stage.desc, width - 4)) do
    lines[#lines + 1] = "  " .. l
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  Next move:  " .. describe_move(next_move)
  -- short preview of what follows in this stage
  local preview = {}
  for i = tut.move_idx + 1, math.min(tut.move_idx + 6, #stage.moves) do
    preview[#preview + 1] = stage.moves[i]
  end
  if #preview > 0 then
    lines[#lines + 1] = "  Then:       " .. table.concat(preview, " ")
  end
  lines[#lines + 1] = string.format("  Stage progress: %d/%d", tut.move_idx - 1, #stage.moves)
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  Keys: lowercase = clockwise, SHIFT = ' (reverse)"
  local km = config.get().keymaps
  lines[#lines + 1] =
    string.format("  [%s] do it for me   [%s] leave tutorial", km.tutorial_step, km.tutorial)
  return lines, width
end

local function close_panel(session)
  local tut = session.tutorial
  if not tut then
    return
  end
  if tut.panel_win and vim.api.nvim_win_is_valid(tut.panel_win) then
    vim.api.nvim_win_close(tut.panel_win, true)
  end
  if tut.panel_buf and vim.api.nvim_buf_is_valid(tut.panel_buf) then
    vim.api.nvim_buf_delete(tut.panel_buf, { force = true })
  end
  tut.panel_win, tut.panel_buf = nil, nil
end

local function repaint_panel(session)
  local tut = session.tutorial
  local lines, width = panel_lines(session)
  if not (tut.panel_buf and vim.api.nvim_buf_is_valid(tut.panel_buf)) then
    tut.panel_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[tut.panel_buf].bufhidden = "wipe"
  end
  vim.bo[tut.panel_buf].modifiable = true
  vim.api.nvim_buf_set_lines(tut.panel_buf, 0, -1, false, lines)
  vim.bo[tut.panel_buf].modifiable = false
  local win_cfg = {
    relative = "editor",
    row = 1,
    col = math.max(0, vim.o.columns - width - 4),
    width = width,
    height = #lines,
    border = "rounded",
    style = "minimal",
    focusable = false,
    title = " Tutorial ",
    title_pos = "center",
  }
  if tut.panel_win and vim.api.nvim_win_is_valid(tut.panel_win) then
    vim.api.nvim_win_set_config(tut.panel_win, win_cfg)
    vim.api.nvim_win_set_buf(tut.panel_win, tut.panel_buf)
  else
    tut.panel_win = vim.api.nvim_open_win(tut.panel_buf, false, win_cfg)
  end
end

-- Start tutorial mode. `repaint` is the ui callback that redraws the cube.
function M.start(session, repaint)
  if session.tutorial then
    return
  end
  if cube.is_solved(session.state) then
    vim.notify("rubikscube: cube is already solved — scramble it first", vim.log.levels.INFO)
    return
  end
  session.tutorial = {
    solution = lbl.solve(session.state),
    stage_idx = 1,
    move_idx = 1,
    repaint = repaint,
  }
  repaint_panel(session)
end

function M.stop(session)
  if not session.tutorial then
    return
  end
  close_panel(session)
  session.tutorial = nil
end

-- Apply the next tutorial move. Tutorial steps don't count as manual moves
-- (mirrors auto-solve: move_count stays frozen).
function M.step(session)
  local tut = session.tutorial
  if not tut then
    return
  end
  local _, move = current_position(tut)
  if not move then
    M.finish(session)
    return
  end
  cube.apply(session.state, move)
  session.last_move = move
  session.was_solved = cube.is_solved(session.state)
  tut.move_idx = tut.move_idx + 1
  tut.repaint()
  if not current_position(tut) then
    M.finish(session)
  else
    repaint_panel(session)
  end
end

function M.finish(session)
  M.stop(session)
  vim.notify("rubikscube: tutorial complete — cube solved!", vim.log.levels.INFO)
end

-- The user made a move themselves. If it is exactly the move the tutorial
-- asked for, advance the walkthrough — following along by hand is the whole
-- point. Only a deviating move triggers a re-plan; re-planning on EVERY
-- manual move would let the fresh plan open with the inverse of what the
-- user just did, trapping obedient followers in an undo/redo loop.
function M.on_manual_move(session, move)
  local tut = session.tutorial
  if not tut then
    return
  end
  local _, expected = current_position(tut)
  if expected == move then
    tut.move_idx = tut.move_idx + 1
    if not current_position(tut) then
      M.finish(session)
    else
      repaint_panel(session)
    end
    return
  end
  M.refresh(session)
end

-- The cube changed outside the tutorial (manual move, scramble, reset):
-- recompute the walkthrough from the new state, or finish if it's solved.
function M.refresh(session)
  local tut = session.tutorial
  if not tut then
    return
  end
  if cube.is_solved(session.state) then
    M.finish(session)
    return
  end
  tut.solution = lbl.solve(session.state)
  tut.stage_idx = 1
  tut.move_idx = 1
  repaint_panel(session)
end

M._for_test = { panel_lines = panel_lines, current_position = current_position }

return M
