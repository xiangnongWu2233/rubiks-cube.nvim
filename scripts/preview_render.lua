-- Manual preview: dump the template + a solved-cube render to stdout for visual inspection.
local cwd = vim.fn.getcwd()
vim.opt.runtimepath:prepend(cwd)
package.path = cwd .. "/lua/?.lua;" .. cwd .. "/lua/?/init.lua;" .. package.path

local render = require("rubikscube.render")

io.write("=== TEMPLATE LINES (" .. #render.TEMPLATE .. " lines) ===\n")
for i, line in ipairs(render.TEMPLATE) do
  io.write(string.format("%2d: |%s|\n", i, line))
end

io.write("\n=== STICKER REGIONS ===\n")
for _, face in ipairs({ "U", "F", "R" }) do
  for i = 1, 9 do
    for _, r in ipairs(render.STICKER_REGIONS[face][i]) do
      io.write(
        string.format("%s[%d] @ row=%d cols=%d..%d\n", face, i, r.row, r.col_start, r.col_end)
      )
    end
  end
end

vim.cmd("qa!")
