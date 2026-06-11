local T = require("test_helper")
local cube = require("rubikscube.cube")
local ui = require("rubikscube.ui")
local tutorial = require("rubikscube.tutorial")

-- Helper: open a session with a seeded scramble and the tutorial running.
local function open_tutorial_session(seed)
  local s = ui.open()
  cube.scramble(s.state, 25, seed or 1)
  ui.make_tutorial_handler(s)()
  return s
end

T.test("tutorial: starting opens the side panel and plans a solution", function()
  local s = open_tutorial_session(1)
  T.truthy(tutorial.is_active(s))
  T.truthy(s.tutorial.panel_win and vim.api.nvim_win_is_valid(s.tutorial.panel_win))
  T.truthy(s.tutorial.panel_buf and vim.api.nvim_buf_is_valid(s.tutorial.panel_buf))
  T.eq(#s.tutorial.solution.stages, 8)
  ui.make_quit_handler(s)()
end)

T.test("tutorial: does not start on a solved cube", function()
  local s = ui.open()
  ui.make_tutorial_handler(s)()
  T.falsy(tutorial.is_active(s))
  ui.make_quit_handler(s)()
end)

T.test("tutorial: toggle key stops it and closes the panel", function()
  local s = open_tutorial_session(2)
  local win = s.tutorial.panel_win
  ui.make_tutorial_handler(s)()
  T.falsy(tutorial.is_active(s))
  T.falsy(vim.api.nvim_win_is_valid(win))
  ui.make_quit_handler(s)()
end)

T.test("tutorial: step applies a move without counting it", function()
  local s = open_tutorial_session(3)
  local before = cube.copy(s.state)
  ui.make_tutorial_step_handler(s)()
  T.falsy(cube.equal(before, s.state))
  T.truthy(s.last_move)
  T.eq(s.move_count, 0)
  ui.make_quit_handler(s)()
end)

T.test("tutorial: stepping to the end solves the cube and finishes", function()
  local s = open_tutorial_session(4)
  local step = ui.make_tutorial_step_handler(s)
  for _ = 1, 400 do
    if not tutorial.is_active(s) then
      break
    end
    step()
  end
  T.falsy(tutorial.is_active(s))
  T.truthy(require("rubikscube.lbl").is_solved_any_orientation(s.state))
  ui.make_quit_handler(s)()
end)

T.test("tutorial: manual move matching the expected one advances, no re-plan", function()
  local s = open_tutorial_session(12)
  local solution = s.tutorial.solution
  local _, expected = tutorial._for_test.current_position(s.tutorial)
  local idx_before = s.tutorial.move_idx
  ui.make_move_handler(s, expected)()
  T.truthy(tutorial.is_active(s))
  T.eq(s.tutorial.solution, solution, "same plan object — no re-plan")
  T.eq(s.tutorial.move_idx, idx_before + 1)
  ui.make_quit_handler(s)()
end)

T.test("tutorial: following the panel by hand never loops and solves the cube", function()
  -- Regression: re-planning after EVERY manual move could tell the user to
  -- undo the move they just made, ping-ponging forever. Simulate a user who
  -- always presses exactly the key the panel asks for.
  local s = open_tutorial_session(13)
  local steps = 0
  while tutorial.is_active(s) do
    steps = steps + 1
    T.truthy(steps <= 400, "tutorial loops: " .. steps .. " manual moves without finishing")
    local _, expected = tutorial._for_test.current_position(s.tutorial)
    ui.make_move_handler(s, expected)()
  end
  T.truthy(require("rubikscube.lbl").is_solved_any_orientation(s.state))
  ui.make_quit_handler(s)()
end)

T.test("tutorial: panel shows pure notation plus a one-line key legend", function()
  local s = open_tutorial_session(14)
  local lines = vim.api.nvim_buf_get_lines(s.tutorial.panel_buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  T.falsy(text:match("press"), "no per-move key hint")
  T.truthy(text:match("Keys: lowercase = clockwise"), "key legend present")
  ui.make_quit_handler(s)()
end)

T.test("tutorial: a manual move re-plans instead of breaking", function()
  local s = open_tutorial_session(5)
  ui.make_tutorial_step_handler(s)()
  ui.make_tutorial_step_handler(s)()
  local _, expected = tutorial._for_test.current_position(s.tutorial)
  ui.make_move_handler(s, expected == "R" and "L" or "R")() -- guaranteed deviation
  T.truthy(tutorial.is_active(s))
  -- progress resets (empty leading stages may already be skipped over)
  T.eq(s.tutorial.move_idx, 1)
  -- the re-planned solution still solves the (deviated) cube
  local replayed = cube.copy(s.state)
  for _, m in ipairs(s.tutorial.solution.moves) do
    cube.apply(replayed, m)
  end
  T.truthy(require("rubikscube.lbl").is_solved_any_orientation(replayed))
  ui.make_quit_handler(s)()
end)

T.test("tutorial: scramble during tutorial re-plans from the new state", function()
  local s = open_tutorial_session(6)
  ui.make_scramble_handler(s)()
  T.truthy(tutorial.is_active(s))
  T.eq(s.tutorial.move_idx, 1)
  ui.make_quit_handler(s)()
end)

T.test("tutorial: reset stops the tutorial silently", function()
  local s = open_tutorial_session(7)
  ui.make_reset_handler(s)()
  T.falsy(tutorial.is_active(s))
  T.truthy(cube.is_solved(s.state))
  ui.make_quit_handler(s)()
end)

T.test("tutorial: quitting the cube closes the panel", function()
  local s = open_tutorial_session(8)
  local win = s.tutorial.panel_win
  ui.make_quit_handler(s)()
  T.falsy(vim.api.nvim_win_is_valid(win))
end)

T.test("tutorial: t and n keymaps are registered on the cube buffer", function()
  local s = ui.open()
  local maps = vim.api.nvim_buf_get_keymap(s.buf, "n")
  local lhs_set = {}
  for _, m in ipairs(maps) do
    lhs_set[m.lhs] = true
  end
  T.truthy(lhs_set["t"], "tutorial toggle key")
  T.truthy(lhs_set["n"], "tutorial step key")
  ui.make_quit_handler(s)()
end)

T.test("tutorial: panel text shows stage, next move, and progress", function()
  local s = open_tutorial_session(9)
  local lines = vim.api.nvim_buf_get_lines(s.tutorial.panel_buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  T.truthy(text:match("Stage 1/8"), "stage header")
  T.truthy(text:match("Next move:"), "next move line")
  T.truthy(text:match("Stage progress:"), "progress line")
  ui.make_quit_handler(s)()
end)
