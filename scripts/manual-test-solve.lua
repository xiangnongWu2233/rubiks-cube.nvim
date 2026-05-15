-- Manual interactive verification of the auto-solve flow.
-- Run from the plugin root:
--
--     nvim -u NONE --cmd 'set rtp+=.' -c 'luafile scripts/manual-test-solve.lua'
--
-- (Do NOT use `nvim -l` — that runs in headless batch mode and exits
-- without showing any UI. The `-c 'luafile ...'` form opens Neovim normally
-- and sources the script at startup, leaving you in an interactive editor.)
--
-- Once Neovim opens you'll see the cube already scrambled (deterministic
-- seed=1). Press `S` to auto-solve, `q` to quit.

vim.opt.runtimepath:prepend(vim.fn.getcwd())

local rubiks = require("rubikscube")
local cube = require("rubikscube.cube")
local solver = require("rubikscube.solver")

if not solver.is_available() then
  vim.notify(
    "kociemba not found on PATH. Install with `uv tool install kociemba` (or pipx/pip) and re-run.",
    vim.log.levels.ERROR
  )
  return
end

-- Open the cube and apply a deterministic 20-move scramble (so the visual
-- output is the same every time you run this script — easier to compare runs).
local session = rubiks.open()
cube.scramble(session.state, 20, 1)

local render = require("rubikscube.render")
render.repaint(session.buf, session.state, {
  last_move = "scramble (seed 1)",
  move_count = 0,
  hints = "press S to auto-solve, q to quit",
})

vim.notify(
  "rubiks-cube manual test: cube is scrambled (seed=1). Press S to auto-solve, or q to quit.",
  vim.log.levels.INFO
)
