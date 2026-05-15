local M = {}

-- Face base letters: lowercase = clockwise, uppercase (auto) = prime.
-- Rotation base letters: same lowercase/uppercase convention.
-- Action keys: lhs strings passed to vim.keymap.set.
-- Any keymap entry may be set to `false` to skip that binding entirely.
M.defaults = {
  keymaps = {
    U = "u",
    D = "d",
    L = "l",
    R = "r",
    F = "f",
    B = "b",
    x = "x",
    y = "y",
    z = "z",
    scramble = "s",
    reset = "<CR>",
    timer = "<Space>",
    quit = "q",
    help = "?",
    solve = "S", -- auto-solve via external kociemba binary; false to disable
  },
  scramble_length = 20, -- moves applied by the scramble action
  persist_best = true, -- false → solves never write best.json (reads still work)
  open_in = "float", -- "float" | "current" | "split" | "vsplit"
  solver = {
    tempo_ms = 200, -- delay between animated moves during auto-solve
  },
}

M.current = vim.deepcopy(M.defaults)

function M.apply(opts)
  if type(opts) ~= "table" then
    return
  end
  M.current = vim.tbl_deep_extend("force", M.current, opts)
end

function M.reset()
  M.current = vim.deepcopy(M.defaults)
end

function M.get()
  return M.current
end

return M
