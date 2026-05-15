-- Isometric 3D rendering of the cube into a Neovim buffer.
-- Shows U, F, R faces. Uses highlight extmarks for per-sticker colors.

local M = {}

-- Color → highlight group, bg hex.
M.HL = {
  W = { group = "RubiksW", bg = "#f5f5f5", fg = "#202020" },
  Y = { group = "RubiksY", bg = "#ffd500", fg = "#202020" },
  O = { group = "RubiksO", bg = "#ff7f00", fg = "#202020" },
  R = { group = "RubiksR", bg = "#d32f2f", fg = "#202020" },
  G = { group = "RubiksG", bg = "#1aaa1a", fg = "#202020" },
  B = { group = "RubiksB", bg = "#1d6dd6", fg = "#202020" },
}

M.NS = nil -- extmark namespace, lazily created

function M.setup()
  -- `default = true` lets users (or colorschemes) override these via :hi
  -- without their override being clobbered on every cube open.
  for _, hl in pairs(M.HL) do
    vim.api.nvim_set_hl(0, hl.group, { bg = hl.bg, fg = hl.fg, default = true })
  end
  if not M.NS then
    M.NS = vim.api.nvim_create_namespace("rubikscube")
  end
end

-- Template layout (built programmatically by `build_template` below):
--   - F face occupies rows 8..14, cols 8..20 (each sticker 4 wide × 2 tall content).
--   - U face occupies rows 0..6, cols 8..20 BUT each U row is shifted right by 2 per
--     row going up: U-top-row at cols 12..24, U-mid-row at cols 10..22, U-bot at 8..20.
--     A `/` slant connects U to F.
--   - R face occupies rows 8..14, cols 22..28 with row-shifts.

local W = 4 -- sticker content width in cells
local H = 2 -- sticker content height (1 content row + 1 border row)

-- Build the template programmatically so positions are easy to track.
local function build_template()
  -- Use a grid of characters, then convert to lines.
  local grid = {}
  local nrows, ncols = 32, 60
  for r = 1, nrows do
    grid[r] = {}
    for c = 1, ncols do
      grid[r][c] = " "
    end
  end
  local function setch(r, c, ch)
    if r >= 1 and r <= nrows and c >= 1 and c <= ncols then
      grid[r][c] = ch
    end
  end

  -- Anchor: F top-left content at (row=10, col=6).  (1-based grid coords)
  -- F is rows 10..15 (6 rows: 3 content rows interleaved with 3 border rows + closing).
  -- Wait: 3 sticker rows × 2 (content+border) = 6, plus opening border = 7 lines.
  -- We'll lay out F as: row 9 = top border, row 10 = content row 1, row 11 = mid border,
  -- row 12 = content row 2, row 13 = mid border, row 14 = content row 3, row 15 = bottom border.

  -- F borders:
  local F_TOP = 9
  local F_LEFT = 6
  local function hborder(row, col_start, cols)
    -- draws +----+----+----+ ...
    for i = 0, cols do
      setch(row, col_start + i * (W + 1), "+")
      if i < cols then
        for k = 1, W do
          setch(row, col_start + i * (W + 1) + k, "-")
        end
      end
    end
  end
  local function vborder_row(row, col_start, cols)
    -- draws |    |    |    |
    for i = 0, cols do
      setch(row, col_start + i * (W + 1), "|")
    end
  end

  for r = 0, 3 do
    hborder(F_TOP + r * 2, F_LEFT, 3)
  end
  for r = 0, 2 do
    vborder_row(F_TOP + 1 + r * 2, F_LEFT, 3)
  end

  -- U: above F, shifted right per row going up.
  -- U-bot-row content at row F_TOP - 1 = row 8, U-mid at row 6, U-top at row 4.
  -- Each U row shifted +2 cols per row going up.
  -- U borders use '/' instead of '|' for slant on the SIDES of stickers,
  -- and '-' for top/bottom edges.
  local U_LEFT_BASE = F_LEFT -- bottom-row left edge aligns with F top-left
  local U_OFFSET_PER_ROW = 2

  -- U bottom border = F top border (already drawn at row F_TOP).
  -- U content rows are at row F_TOP - 1, F_TOP - 3, F_TOP - 5.
  -- Borders for U: rows F_TOP, F_TOP-2, F_TOP-4, F_TOP-6.
  --                 ^-- F top   ^-- between U rows 3/2  ^-- between 2/1  ^-- U top
  for u = 0, 3 do
    local row = F_TOP - u * 2 -- 9, 7, 5, 3
    local col_start = U_LEFT_BASE + u * U_OFFSET_PER_ROW
    -- Draw "+ - - - - +" style border. Use '/' at the corners where the slant goes up-right.
    for i = 0, 3 do
      local c = col_start + i * (W + 1)
      setch(row, c, "+")
      if i < 3 then
        for k = 1, W do
          setch(row, c + k, "-")
        end
      end
    end
  end
  -- U content rows: at rows F_TOP - 1, F_TOP - 3, F_TOP - 5 (which are 8, 6, 4).
  -- Slant chars '/' separate stickers. Each sticker content is 4 cols.
  -- For each U row (from bottom u=0 to top u=2), col_start = U_LEFT_BASE + (u+1)*U_OFFSET_PER_ROW.
  -- Wait, bottom content row is between bot border and next-up border, so above U_LEFT_BASE level.
  -- Let me reconsider.
  -- The slanted shape: bottom-row content at row 8 (between border at row 9 and border at row 7).
  -- At row 8, the left edge is between U-bot-border-left (col 6) and U-mid-border-left (col 8).
  -- So at row 8, the left edge should be at col 7 (halfway).
  for u = 0, 2 do
    local row = F_TOP - 1 - u * 2 -- 8, 6, 4
    local col_start = U_LEFT_BASE + u * U_OFFSET_PER_ROW + 1 -- halfway between borders
    for i = 0, 3 do
      setch(row, col_start + i * (W + 1), "/")
    end
  end

  -- R: iso parallelogram right of F (slope 1 row per 1 col = 45°, matching U_OFFSET=2).
  --   Front (left) edge:  vertical | shared with F's right border at col 21.
  --   Back  (right) edge: vertical | at col 27.
  --   Top edge:    slanted +/+/+/+ from (col 21, row F_TOP) to (col 27, F_TOP-6).
  --   Bottom edge: slanted +/+/+/+ from (col 21, row F_TOP+6) to (col 27, F_TOP).
  --   Row separators (slanted): from (col 21, F_TOP+2)→(col 27, F_TOP-4) and (col 21, F_TOP+4)→(col 27, F_TOP-2).
  --   Col separators (vertical): | at cols 23 and 25 inside R.
  --   Each R sticker has one interior content cell at (col 22+2c, row F_TOP+1-2c+2r).
  local R_FRONT_COL = F_LEFT + 3 * (W + 1) -- col 21
  local R_DEPTH = 6 -- 3 sticker-cols × 2 cols each
  local R_BACK_COL = R_FRONT_COL + R_DEPTH -- col 27

  -- Slanted line: slope -1 row per +1 col. '+' at endpoints and at every 2-col col-separator
  -- crossing; '/' on the diagonal steps between.
  local function slant(col0, row0, length)
    for i = 0, length do
      local c = col0 + i
      local r = row0 - i
      local ch
      if i == 0 or i == length or i % 2 == 0 then
        ch = "+"
      else
        ch = "/"
      end
      setch(r, c, ch)
    end
  end

  slant(R_FRONT_COL, F_TOP, R_DEPTH) -- top edge:    (21, 9) → (27, 3)
  slant(R_FRONT_COL, F_TOP + 2, R_DEPTH) -- row sep 1:   (21, 11) → (27, 5)
  slant(R_FRONT_COL, F_TOP + 4, R_DEPTH) -- row sep 2:   (21, 13) → (27, 7)
  slant(R_FRONT_COL, F_TOP + 6, R_DEPTH) -- bottom edge: (21, 15) → (27, 9)

  -- Right edge: vertical | at col 27, rows F_TOP-5 .. F_TOP-1
  for r = 1, R_DEPTH - 1 do
    setch(F_TOP - r, R_BACK_COL, "|")
  end

  -- Vertical col separators inside R, at cols 23 and 25
  for k = 1, 2 do
    local c = R_FRONT_COL + 2 * k
    local top_r = F_TOP - 2 * k
    for off = 1, R_DEPTH - 1 do
      local r = top_r + off
      local existing = grid[r] and grid[r][c]
      if existing == " " or existing == nil then
        setch(r, c, "|")
      end
    end
  end

  -- Convert grid to lines (preserve trailing whitespace — sticker cells live there).
  local lines = {}
  for r = 1, nrows do
    lines[r] = table.concat(grid[r])
  end
  -- Drop leading/trailing whitespace-only lines. Track leading shift so callers can rebase row indices.
  local leading = 0
  while #lines > 0 and lines[1]:match("^%s*$") do
    table.remove(lines, 1)
    leading = leading + 1
  end
  while #lines > 0 and lines[#lines]:match("^%s*$") do
    table.remove(lines)
  end
  return lines,
    {
      F_TOP = F_TOP,
      F_LEFT = F_LEFT,
      U_LEFT_BASE = U_LEFT_BASE,
      U_OFFSET_PER_ROW = U_OFFSET_PER_ROW,
      W = W,
      H = H,
      LEADING_TRIM = leading,
    }
end

local TEMPLATE_LINES, GEOM = build_template()
M.TEMPLATE = TEMPLATE_LINES
M.GEOM = GEOM

-- For each visible sticker (U[1..9], F[1..9], R[1..9]) we record a list of
-- {row, col_start, col_end} ranges to highlight. Coordinates are 0-based for
-- nvim_buf_set_extmark.
local STICKER_REGIONS = {}

do
  local function box(row_1based, col_1based)
    -- Convert 1-based grid coords to 0-based buffer coords, and return a single row range.
    -- Account for leading whitespace-only rows trimmed off the top of the template.
    return {
      row = row_1based - 1 - GEOM.LEADING_TRIM,
      col_start = col_1based - 1,
      col_end = col_1based - 1 + GEOM.W,
    }
  end

  -- F stickers (3x3, flat):
  -- F[1] at row F_TOP+1, col F_LEFT+1
  -- F[2] at row F_TOP+1, col F_LEFT+1+(W+1)
  -- etc.
  STICKER_REGIONS.F = {}
  for r = 0, 2 do
    for c = 0, 2 do
      local idx = r * 3 + c + 1
      STICKER_REGIONS.F[idx] = { box(GEOM.F_TOP + 1 + r * 2, GEOM.F_LEFT + 1 + c * (GEOM.W + 1)) }
    end
  end

  -- R stickers: each is the single interior cell of a slanted parallelogram.
  -- For R-col c (0=front, 2=back) and R-row r (0=top, 2=bot):
  --   interior cell at 1-based grid (col = R_FRONT_COL + 1 + 2*c, row = F_TOP + 1 - 2*c + 2*r)
  STICKER_REGIONS.R = {}
  local R_FRONT_COL = GEOM.F_LEFT + 3 * (GEOM.W + 1)
  for r = 0, 2 do
    for c = 0, 2 do
      local idx = r * 3 + c + 1
      local row1 = GEOM.F_TOP + 1 - 2 * c + 2 * r
      local col1 = R_FRONT_COL + 1 + 2 * c
      local cell_row = row1 - 1 - GEOM.LEADING_TRIM
      local cell_col = col1 - 1
      STICKER_REGIONS.R[idx] = { { row = cell_row, col_start = cell_col, col_end = cell_col + 1 } }
    end
  end

  -- U stickers: parallelogram. Each U-row r (0=top, 2=bottom) is at:
  --   content row = F_TOP - 5 + r * 2  (top row r=0 → F_TOP - 5; bot row r=2 → F_TOP - 1)
  --   col_start = U_LEFT_BASE + (2 - r) * U_OFFSET_PER_ROW + 1
  -- Sticker c (0=left, 2=right) at col_start + c * (W + 1).
  STICKER_REGIONS.U = {}
  for r = 0, 2 do
    for c = 0, 2 do
      local idx = r * 3 + c + 1
      local row1 = GEOM.F_TOP - 5 + r * 2 -- 1-based grid row
      local col1 = GEOM.U_LEFT_BASE + (2 - r) * GEOM.U_OFFSET_PER_ROW + 1 + c * (GEOM.W + 1)
      STICKER_REGIONS.U[idx] = { box(row1, col1) }
    end
  end
end

M.STICKER_REGIONS = STICKER_REGIONS

-- Format elapsed milliseconds as M:SS.cc, or "--:--.--" for nil/idle.
local function format_time(ms)
  if not ms then
    return "--:--.--"
  end
  local total_cs = math.floor(ms / 10)
  local cs = total_cs % 100
  local total_s = math.floor(total_cs / 100)
  local s = total_s % 60
  local m = math.floor(total_s / 60)
  return string.format("%d:%02d.%02d", m, s, cs)
end
M.format_time = format_time

-- Default hint string when the caller doesn't supply one. ui.lua builds a
-- dynamic version from the current keymap config and passes it via `hints`.
local DEFAULT_HINTS = "[<Space>]timer  [s]cramble  [S]olve  [<CR>]reset  [?]help  [q]uit"
M.DEFAULT_HINTS = DEFAULT_HINTS

-- Status line text builder.
local function status_line(last_move, move_count, elapsed_ms, timer_running, hints)
  local move = last_move or "-"
  local time_str = format_time(elapsed_ms)
  local timer_mark = timer_running and "*" or " "
  return string.format(
    "  Time: %s %s   Last: %-3s   Moves: %-4d   %s",
    time_str,
    timer_mark,
    move,
    move_count or 0,
    hints or DEFAULT_HINTS
  )
end
M.status_line = status_line

function M.repaint(buf, state, info)
  info = info or {}
  M.setup()
  -- Build buffer lines: template lines + blank + status line.
  local lines = {}
  for _, line in ipairs(TEMPLATE_LINES) do
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] =
    status_line(info.last_move, info.move_count, info.elapsed_ms, info.timer_running, info.hints)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, M.NS, 0, -1)

  -- Add extmark highlights for each visible sticker.
  for _, face in ipairs({ "U", "F", "R" }) do
    for i = 1, 9 do
      local color = state[face][i]
      local hl = M.HL[color].group
      for _, region in ipairs(STICKER_REGIONS[face][i]) do
        vim.api.nvim_buf_set_extmark(buf, M.NS, region.row, region.col_start, {
          end_col = region.col_end,
          hl_group = hl,
        })
      end
    end
  end

  vim.bo[buf].modifiable = false
end

-- Repaint only the status line (last buffer line). Used by the timer ticker
-- ~10× per second; avoids redrawing the whole cube + extmarks.
function M.repaint_status(buf, info)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  info = info or {}
  local total = vim.api.nvim_buf_line_count(buf)
  local line =
    status_line(info.last_move, info.move_count, info.elapsed_ms, info.timer_running, info.hints)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, total - 1, total, false, { line })
  vim.bo[buf].modifiable = false
end

-- Briefly invert sticker colors (swap fg/bg) for `ms` milliseconds, then restore.
-- `done` callback fires after restoration.
function M.flash(ms, done)
  ms = ms or 250
  for _, info in pairs(M.HL) do
    vim.api.nvim_set_hl(0, info.group, { bg = info.fg, fg = info.bg })
  end
  vim.defer_fn(function()
    for _, info in pairs(M.HL) do
      vim.api.nvim_set_hl(0, info.group, { bg = info.bg, fg = info.fg })
    end
    if done then
      done()
    end
  end, ms)
end

-- Open a centered floating window with the solve summary.
-- Dismissed via <CR>, <Space>, q, or <Esc>. Calls `on_close` after dismissal.
-- `best_ms` is the prior personal best (nil if none); `is_new_best` is true
-- when this solve beat (or set) the prior record.
function M.show_solve_popup(elapsed_ms, move_count, best_ms, is_new_best, on_close)
  local time_str = format_time(elapsed_ms)
  local lines = {
    "",
    "         SOLVED!         ",
    "",
  }
  if is_new_best then
    lines[#lines + 1] = "    * NEW PERSONAL BEST *"
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = string.format("   Time:    %s", time_str)
  lines[#lines + 1] = string.format("   Moves:   %d", move_count or 0)
  if is_new_best then
    if best_ms then
      lines[#lines + 1] = string.format("   Prior:   %s", format_time(best_ms))
    end
  else
    lines[#lines + 1] =
      string.format("   Best:    %s", best_ms and format_time(best_ms) or "--:--.--")
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "   press <CR>/<Space>/q to dismiss"
  lines[#lines + 1] = ""
  local width = 0
  for _, l in ipairs(lines) do
    if #l > width then
      width = #l
    end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - #lines) / 2) - 2),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width + 2,
    height = #lines,
    border = "double",
    style = "minimal",
    focusable = true,
  })
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if on_close then
      on_close()
    end
  end
  for _, k in ipairs({ "<CR>", "<Space>", "q", "<Esc>" }) do
    vim.keymap.set("n", k, close, { buffer = buf, silent = true, nowait = true })
  end
  return { buf = buf, win = win, close = close }
end

-- Returns the buffer text plus a per-line list of (col_start, col_end, hl_group)
-- highlight runs. Used for testing without TUI.
function M.snapshot(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local marks = vim.api.nvim_buf_get_extmarks(buf, M.NS, 0, -1, { details = true })
  local hls = {}
  for _, m in ipairs(marks) do
    local row, col = m[2], m[3]
    local details = m[4]
    hls[#hls + 1] = { row = row, col = col, end_col = details.end_col, hl_group = details.hl_group }
  end
  return lines, hls
end

return M
