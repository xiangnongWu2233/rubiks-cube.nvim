-- Persists the user's best solve time as JSON in stdpath("data").
-- Schema: { time_ms = number, move_count = number, recorded_at = epoch_seconds }

local M = {}

-- Tests set this to redirect reads/writes away from the real data dir.
M._path_override = nil

local function path()
  return M._path_override or (vim.fn.stdpath("data") .. "/rubikscube/best.json")
end

local function ensure_parent_dir()
  -- pcall: degrade gracefully on read-only data dirs instead of aborting the solve flow.
  if M._path_override then
    local dir = vim.fn.fnamemodify(M._path_override, ":h")
    if dir ~= "" then
      pcall(vim.fn.mkdir, dir, "p")
    end
  else
    pcall(vim.fn.mkdir, vim.fn.stdpath("data") .. "/rubikscube", "p")
  end
end

function M.read()
  local p = path()
  local fh = io.open(p, "r")
  if not fh then
    return nil
  end
  local s = fh:read("*a")
  fh:close()
  if not s or s == "" then
    return nil
  end
  local ok, data = pcall(vim.json.decode, s)
  if not ok or type(data) ~= "table" then
    return nil
  end
  return data
end

function M.write(data)
  ensure_parent_dir()
  local fh, err = io.open(path(), "w")
  if not fh then
    return false, err
  end
  fh:write(vim.json.encode(data))
  fh:close()
  return true
end

-- Returns the prior best time (ms) and whether `elapsed_ms` is a new best.
-- Writes the new best if it improves on the prior. nil elapsed is a no-op.
function M.maybe_update(elapsed_ms, move_count)
  if type(elapsed_ms) ~= "number" then
    return nil, false
  end
  local prior = M.read()
  local prior_ms = prior and prior.time_ms
  if prior_ms and prior_ms <= elapsed_ms then
    return prior_ms, false
  end
  M.write({
    time_ms = elapsed_ms,
    move_count = move_count,
    recorded_at = os.time(),
  })
  return prior_ms, true
end

function M.clear()
  os.remove(path())
end

return M
