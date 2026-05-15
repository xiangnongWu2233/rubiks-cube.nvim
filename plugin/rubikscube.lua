if vim.g.loaded_rubikscube == 1 then
  return
end
vim.g.loaded_rubikscube = 1

vim.api.nvim_create_user_command("Rubikscube", function()
  require("rubikscube").open()
end, { desc = "Open the Rubik's cube" })
