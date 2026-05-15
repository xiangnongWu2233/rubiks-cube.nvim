-- `:checkhealth rubikscube` provider.
--
-- Reports on the plugin's environment requirements: Neovim version,
-- termguicolors, and the optional `kociemba` CLI used by auto-solve.

local M = {}

function M.check()
  vim.health.start("rubiks-cube.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim 0.10+ (uses `vim.uv`)")
  else
    vim.health.error("Neovim 0.10 or newer is required (this plugin uses `vim.uv`)")
  end

  if vim.o.termguicolors then
    vim.health.ok("`termguicolors` is enabled")
  else
    vim.health.warn(
      "`termguicolors` is disabled — sticker colors will fall back to cterm approximations",
      "Set `vim.opt.termguicolors = true` in your config for true-color rendering."
    )
  end

  local solver = require("rubikscube.solver")
  if solver.is_available() then
    vim.health.ok(
      "`"
        .. solver.BINARY
        .. "` CLI found on PATH — auto-solve (`S` / `:RubikscubeSolve`) is enabled"
    )
  else
    vim.health.warn(
      "`"
        .. solver.BINARY
        .. "` CLI not found on PATH — auto-solve (`S` / `:RubikscubeSolve`) will be unavailable",
      { solver.INSTALL_HINT, "Auto-solve is OPTIONAL; the rest of the plugin works without it." }
    )
  end
end

return M
