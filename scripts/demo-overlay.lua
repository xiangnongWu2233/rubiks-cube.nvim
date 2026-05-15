-- Keypress overlay for vhs recordings of rubiks-cube.nvim.
--
-- Displays the most recent DEMO-RELEVANT keypress in a small floating
-- window at the top-right of the editor. Clears after a short idle period.
-- Keys outside the cube's bound set (cursor moves, escape, : commands,
-- internal Neovim chatter) are filtered out so the overlay only shows
-- the keystrokes the viewer cares about.

local DEMO_KEYS = {
  -- Face turns: lowercase = CW, uppercase = prime.
  u = true,
  U = true,
  d = true,
  D = true,
  l = true,
  L = true,
  r = true,
  R = true,
  f = true,
  F = true,
  b = true,
  B = true,
  -- Whole-cube rotations.
  x = true,
  X = true,
  y = true,
  Y = true,
  z = true,
  Z = true,
  -- Actions.
  s = true,
  S = true,
  q = true,
  ["<CR>"] = true,
  ["<Space>"] = true,
}

local WIDTH = 12
local CLEAR_MS = 1500

local buf, win, clear_timer

local function close_win()
  if clear_timer then
    clear_timer:stop()
    clear_timer:close()
    clear_timer = nil
  end
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  win, buf = nil, nil
end

local function ensure_win()
  if win and vim.api.nvim_win_is_valid(win) then
    return
  end
  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    anchor = "NE",
    width = WIDTH,
    height = 1,
    row = 1,
    col = vim.o.columns - 2,
    border = "rounded",
    style = "minimal",
    focusable = false,
    noautocmd = true,
    zindex = 250, -- above the cube's floating window
  })
end

local function render(label)
  ensure_win()
  local line = (" key: %-" .. (WIDTH - 6) .. "s"):format(label)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  vim.bo[buf].modifiable = false
end

local function schedule_clear()
  if clear_timer then
    clear_timer:stop()
    clear_timer:close()
  end
  clear_timer = (vim.uv or vim.loop).new_timer()
  clear_timer:start(CLEAR_MS, 0, vim.schedule_wrap(close_win))
end

vim.on_key(function(_, typed)
  if not typed or typed == "" then
    return
  end
  local label = vim.fn.keytrans(typed)
  if not DEMO_KEYS[label] then
    return
  end
  vim.schedule(function()
    render(label)
    schedule_clear()
  end)
end)
