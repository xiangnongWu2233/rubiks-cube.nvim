-- Headless test runner. Invoke: nvim --headless -l tests/run.lua
local cwd = vim.fn.getcwd()
vim.opt.runtimepath:prepend(cwd)
package.path = cwd
  .. "/lua/?.lua;"
  .. cwd
  .. "/lua/?/init.lua;"
  .. cwd
  .. "/tests/?.lua;"
  .. package.path

local T = require("test_helper")

local suites = {
  "test_cube",
  "test_render",
  "test_ui",
  "test_solver",
  "test_animate",
  "test_solver_integration",
  "test_kociemba_e2e",
}
for _, name in ipairs(suites) do
  T.suite(name)
  local ok, err = pcall(require, name)
  if not ok then
    T.failed = T.failed + 1
    table.insert(T.failures, name .. " :: load error :: " .. tostring(err))
  end
end

local pass = T.summary()
vim.cmd(pass and "qa!" or "cq!")
