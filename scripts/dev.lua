-- Dev launcher. Run from the repo root:
--   nvim -u NONE -c 'luafile scripts/dev.lua'
local cwd = vim.fn.getcwd()
vim.opt.runtimepath:prepend(cwd)
package.path = cwd .. "/lua/?.lua;" .. cwd .. "/lua/?/init.lua;" .. package.path

require("rubikscube").open()
