-- Auto-solver: shells out to the external `kociemba` CLI.
--
-- The plugin does NOT bundle a solver. Users who want auto-solve must install
-- the optional dependency themselves (typically `pip install kociemba`). This
-- module detects the binary, hands it a 54-character facelet string, and
-- returns the parsed move sequence via callback.

local facelet = require("rubikscube.facelet")
local moves = require("rubikscube.moves")
local cube = require("rubikscube.cube")

local M = {}

M.BINARY = "kociemba"

M.INSTALL_HINT =
  "Auto-solve requires the `kociemba` CLI. Install with: pipx install kociemba  (or uv tool install kociemba / pip install kociemba)"

-- Returns true if the external solver binary is on PATH.
function M.is_available()
  return vim.fn.executable(M.BINARY) == 1
end

-- Solve the given state asynchronously. `callback(moves, err)` runs on the
-- main Neovim loop (via vim.schedule). On success, `moves` is a list of
-- cube.apply-compatible tokens; on failure, `err` is a string explaining why.
function M.solve_async(state, callback)
  if cube.is_solved(state) then
    return vim.schedule(function()
      callback({})
    end)
  end

  if not M.is_available() then
    return vim.schedule(function()
      callback(nil, M.INSTALL_HINT)
    end)
  end

  local input
  do
    local ok, result = pcall(facelet.to_string, state)
    if not ok then
      return vim.schedule(function()
        callback(nil, "facelet error: " .. tostring(result))
      end)
    end
    input = result
  end

  -- `kociemba <facelet_string>` prints the solution to stdout. Capture stderr
  -- separately so we can surface a useful message if the input is rejected
  -- (e.g. an inconsistent state would be reported there).
  -- `timeout = 5000` guards against a hung subprocess — kociemba normally
  -- returns in <100ms; 5 seconds is well past any real case.
  vim.system({ M.BINARY, input }, { text = true, timeout = 5000 }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        local err = (obj.stderr and obj.stderr ~= "") and obj.stderr
          or "kociemba exited with code " .. tostring(obj.code)
        return callback(nil, err:gsub("%s+$", ""))
      end
      local out = (obj.stdout or ""):gsub("%s+$", "")
      if out == "" then
        return callback(nil, "kociemba returned empty output")
      end
      local parsed, perr = moves.parse(out)
      if not parsed then
        return callback(nil, "could not parse kociemba output: " .. tostring(perr))
      end
      callback(parsed)
    end)
  end)
end

return M
