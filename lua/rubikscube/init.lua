local config = require("rubikscube.config")

local M = {}

-- The single active session for this Neovim instance. nil when no cube is open.
M._session = nil

function M.setup(opts)
  config.apply(opts)
end

-- Open the cube. If a cube buffer is already open and valid, this is a no-op
-- (returns the existing session); the user can `q` it first to get a fresh one.
function M.open()
  if M._session and M._session.buf and vim.api.nvim_buf_is_valid(M._session.buf) then
    return M._session
  end
  local ui = require("rubikscube.ui")
  M._session = ui.open(nil, function()
    M._session = nil
  end)
  return M._session
end

-- Returns the currently-open session, or nil if no cube is open.
-- Validates the underlying buffer too — a stale session with an invalidated
-- buffer is treated as "not open".
function M.current_session()
  if M._session and M._session.buf and vim.api.nvim_buf_is_valid(M._session.buf) then
    return M._session
  end
  return nil
end

return M
