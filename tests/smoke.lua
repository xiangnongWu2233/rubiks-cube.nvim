-- Headless smoke test: load via the same entry point users would use, then dump
-- the resulting buffer (text only — extmarks don't survive headless cleanly).
-- Invoke: nvim --headless -l tests/smoke.lua

local cwd = vim.fn.getcwd()
vim.opt.runtimepath:prepend(cwd)
package.path = cwd .. "/lua/?.lua;" .. cwd .. "/lua/?/init.lua;" .. package.path

local rubiks = require("rubikscube")
local session = rubiks.open()

-- Apply a few moves to verify everything works end-to-end.
local ui = require("rubikscube.ui")
ui.make_move_handler(session, "U")()
ui.make_move_handler(session, "R")()
ui.make_move_handler(session, "F'")()

local lines = vim.api.nvim_buf_get_lines(session.buf, 0, -1, false)
io.write("=== Buffer contents after U R F' ===\n")
for i, line in ipairs(lines) do
  io.write(string.format("%2d: %s\n", i, line))
end

-- Also verify the keymap is registered for all expected keys.
local maps = vim.api.nvim_buf_get_keymap(session.buf, "n")
io.write(string.format("\nKeymaps registered: %d\n", #maps))

-- Verify quitting works.
ui.make_quit_handler(session)()
io.write(
  string.format(
    "Quit succeeded: buf valid=%s\n",
    tostring(vim.api.nvim_buf_is_valid(session.buf or -1))
  )
)

vim.cmd("qa!")
