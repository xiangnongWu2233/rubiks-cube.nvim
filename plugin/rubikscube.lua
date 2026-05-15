if vim.g.loaded_rubikscube == 1 then
  return
end
vim.g.loaded_rubikscube = 1

vim.api.nvim_create_user_command("Rubikscube", function()
  require("rubikscube").open()
end, { desc = "Open the Rubik's cube" })

vim.api.nvim_create_user_command("RubikscubeSolve", function()
  local rubiks = require("rubikscube")
  local session = rubiks.open()
  local ui = require("rubikscube.ui")
  ui.make_solve_handler(session)()
end, { desc = "Auto-solve the open Rubik's cube (requires `kociemba` CLI)" })
