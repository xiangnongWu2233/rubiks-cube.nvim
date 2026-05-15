local T = require("test_helper")
local cube = require("rubikscube.cube")
local render = require("rubikscube.render")

local function fresh_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].modifiable = true
  return buf
end

T.test("setup defines 6 highlight groups", function()
  render.setup()
  for _, color in ipairs({ "W", "Y", "O", "R", "G", "B" }) do
    local hl = vim.api.nvim_get_hl(0, { name = render.HL[color].group })
    T.truthy(hl, "missing highlight " .. color)
  end
end)

T.test("STICKER_REGIONS has 9 entries for each visible face", function()
  for _, face in ipairs({ "U", "F", "R" }) do
    T.eq(#render.STICKER_REGIONS[face], 9, face)
  end
end)

T.test("repaint produces non-empty buffer lines", function()
  local buf = fresh_buf()
  render.repaint(buf, cube.new(), {})
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  T.truthy(#lines > 5)
  local total_len = 0
  for _, l in ipairs(lines) do
    total_len = total_len + #l
  end
  T.truthy(total_len > 50)
end)

T.test("solved cube: all U stickers have RubiksW highlight", function()
  local buf = fresh_buf()
  render.repaint(buf, cube.new(), {})
  local _, hls = render.snapshot(buf)
  -- Collect all hl_groups appearing in extmarks
  local by_group = {}
  for _, h in ipairs(hls) do
    by_group[h.hl_group] = (by_group[h.hl_group] or 0) + 1
  end
  -- Solved cube has 9 white (U), 9 green (F), 9 red (R) visible stickers
  T.eq(by_group["RubiksW"], 9, "white sticker count")
  T.eq(by_group["RubiksG"], 9, "green sticker count")
  T.eq(by_group["RubiksR"], 9, "red sticker count")
end)

T.test("each U sticker on solved cube highlights the right cells with RubiksW", function()
  local buf = fresh_buf()
  render.repaint(buf, cube.new(), {})
  local _, hls = render.snapshot(buf)
  -- Group hls by hl_group and verify the U-face regions match what STICKER_REGIONS says.
  local expected = {}
  for i = 1, 9 do
    for _, r in ipairs(render.STICKER_REGIONS.U[i]) do
      table.insert(expected, { row = r.row, col_start = r.col_start, col_end = r.col_end })
    end
  end
  -- Find actual W marks
  local actual = {}
  for _, h in ipairs(hls) do
    if h.hl_group == "RubiksW" then
      table.insert(actual, { row = h.row, col_start = h.col, col_end = h.end_col })
    end
  end
  T.eq(#actual, #expected, "U-W mark count")
  -- For each expected region, find a matching actual mark.
  for _, e in ipairs(expected) do
    local found = false
    for _, a in ipairs(actual) do
      if a.row == e.row and a.col_start == e.col_start and a.col_end == e.col_end then
        found = true
        break
      end
    end
    T.truthy(
      found,
      string.format("expected U mark at (row=%d, cols=%d..%d)", e.row, e.col_start, e.col_end)
    )
  end
end)

T.test("after U turn, F-top stickers are highlighted RubiksR", function()
  local s = cube.new()
  cube.apply(s, "U") -- F top row becomes R (red)
  local buf = fresh_buf()
  render.repaint(buf, s, {})
  local _, hls = render.snapshot(buf)
  -- F[1], F[2], F[3] should have RubiksR highlight
  for i = 1, 3 do
    local region = render.STICKER_REGIONS.F[i][1]
    local matched = false
    for _, h in ipairs(hls) do
      if
        h.row == region.row
        and h.col == region.col_start
        and h.end_col == region.col_end
        and h.hl_group == "RubiksR"
      then
        matched = true
        break
      end
    end
    T.truthy(matched, "F[" .. i .. "] should be RubiksR after U turn")
  end
end)

T.test("after y rotation, F-face stickers are RubiksR (centers permute)", function()
  -- After y, new F = old R, so F-face stickers should all be red.
  local s = cube.new()
  cube.apply(s, "y")
  local buf = fresh_buf()
  render.repaint(buf, s, {})
  local _, hls = render.snapshot(buf)
  local r_count_in_F = 0
  for i = 1, 9 do
    local region = render.STICKER_REGIONS.F[i][1]
    for _, h in ipairs(hls) do
      if h.row == region.row and h.col == region.col_start and h.hl_group == "RubiksR" then
        r_count_in_F = r_count_in_F + 1
        break
      end
    end
  end
  T.eq(r_count_in_F, 9, "9 red stickers on F face after y rotation")
end)

T.test("repaint is idempotent: two calls produce same buffer content", function()
  local buf = fresh_buf()
  render.repaint(buf, cube.new(), {})
  local lines1 = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local _, hls1 = render.snapshot(buf)
  render.repaint(buf, cube.new(), {})
  local lines2 = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local _, hls2 = render.snapshot(buf)
  T.same(lines1, lines2, "lines should match")
  T.eq(#hls1, #hls2, "extmark count should match")
end)

T.test("status_line includes Last and Moves fields", function()
  local s = render.status_line("R'", 42)
  T.truthy(s:find("Last:"), "has Last")
  T.truthy(s:find("R'"), "has move text")
  T.truthy(s:find("Moves:"), "has Moves")
  T.truthy(s:find("42"), "has count")
end)

T.test("status_line handles nil last_move with placeholder", function()
  local s = render.status_line(nil, 0)
  T.truthy(s:find("Last:"))
  T.truthy(s:find("Moves:"))
  T.truthy(s:find("0"))
end)

T.test("rendering covers all 6 face colors across cube rotations", function()
  -- Each of the 6 face colors must appear as a sticker highlight at some point as we rotate.
  local seen_colors = {}
  local function record_colors_in_render(state)
    local buf = fresh_buf()
    render.repaint(buf, state, {})
    local _, hls = render.snapshot(buf)
    for _, h in ipairs(hls) do
      for color, info in pairs(render.HL) do
        if info.group == h.hl_group then
          seen_colors[color] = true
        end
      end
    end
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  local s = cube.new()
  record_colors_in_render(s) -- W, G, R visible (U, F, R faces of solved)
  cube.apply(s, "y")
  record_colors_in_render(s) -- F becomes R, R becomes B
  cube.apply(s, "y")
  record_colors_in_render(s) -- F becomes B, R becomes O
  cube.apply(s, "x")
  record_colors_in_render(s) -- U slot now has D (Y)
  for _, c in ipairs({ "W", "Y", "O", "R", "G", "B" }) do
    T.truthy(seen_colors[c], "should render color " .. c .. " somewhere")
  end
end)

-- All-faces-rendered test: scramble the cube, repaint, verify all 6 colors are present
-- on the U/F/R surfaces (since rotations cycle colors through these slots).
T.test("after rotating cube through y, y, y, all faces have been visible in F position", function()
  local seen_in_F = {}
  local s = cube.new()
  for _, rot in ipairs({ "", "y", "y", "y" }) do
    if rot ~= "" then
      cube.apply(s, rot)
    end
    seen_in_F[s.F[5]] = true -- center color of F slot
  end
  -- After identity, y, y, y → F center cycles through G, R, B, O (4 of 6 colors).
  -- Adding x rotation puts the other two (W, Y) into F.
  cube.apply(s, "x") -- now F = old D = Y
  seen_in_F[s.F[5]] = true
  cube.apply(s, "x")
  cube.apply(s, "x")
  seen_in_F[s.F[5]] = true
  T.truthy(seen_in_F.G)
  T.truthy(seen_in_F.R)
  T.truthy(seen_in_F.B)
  T.truthy(seen_in_F.O)
  T.truthy(seen_in_F.Y)
  T.truthy(seen_in_F.W)
end)

-- ============ Render: state→pixel correspondence under scramble ============
-- These tests assert that for ANY cube state, every visible sticker is rendered
-- with the highlight group matching its color. This catches bugs where the
-- render mapping (face index → buffer cell) goes out of sync with cube.lua's
-- face index convention.

local function find_highlight(hls, region, group)
  for _, h in ipairs(hls) do
    if h.row == region.row and h.col == region.col_start and h.hl_group == group then
      return true
    end
  end
  return false
end

T.test("scrambled cube: every U/F/R sticker highlight matches its color", function()
  for seed = 1, 10 do
    local s = cube.new()
    cube.scramble(s, 25, seed)
    local buf = fresh_buf()
    render.repaint(buf, s, {})
    local _, hls = render.snapshot(buf)
    for _, face in ipairs({ "U", "F", "R" }) do
      for i = 1, 9 do
        local region = render.STICKER_REGIONS[face][i][1]
        local color = s[face][i]
        local group = render.HL[color].group
        T.truthy(
          find_highlight(hls, region, group),
          string.format("seed=%d %s[%d]=%s should highlight as %s", seed, face, i, color, group)
        )
      end
    end
  end
end)

T.test("rendered sticker count: total visible = 27 (9 per face × 3 faces)", function()
  for seed = 1, 5 do
    local s = cube.new()
    cube.scramble(s, 20, seed)
    local buf = fresh_buf()
    render.repaint(buf, s, {})
    local _, hls = render.snapshot(buf)
    -- count distinct (row, col_start) anchors highlighted with any Rubiks group
    local seen = {}
    for _, h in ipairs(hls) do
      if h.hl_group:sub(1, 6) == "Rubiks" then
        seen[h.row .. "," .. h.col] = true
      end
    end
    local n = 0
    for _ in pairs(seen) do
      n = n + 1
    end
    T.eq(n, 27, "seed=" .. seed .. " distinct sticker anchors")
  end
end)

T.test("rendered color counts match state color counts on visible faces", function()
  -- Sum of W/Y/O/R/G/B highlights should equal the count of those colors on U+F+R.
  for seed = 1, 5 do
    local s = cube.new()
    cube.scramble(s, 20, seed)
    local expected = { W = 0, Y = 0, O = 0, R = 0, G = 0, B = 0 }
    for _, f in ipairs({ "U", "F", "R" }) do
      for i = 1, 9 do
        expected[s[f][i]] = expected[s[f][i]] + 1
      end
    end
    local buf = fresh_buf()
    render.repaint(buf, s, {})
    local _, hls = render.snapshot(buf)
    local actual = { W = 0, Y = 0, O = 0, R = 0, G = 0, B = 0 }
    for _, h in ipairs(hls) do
      for color, info in pairs(render.HL) do
        if info.group == h.hl_group then
          actual[color] = actual[color] + 1
        end
      end
    end
    for color, n in pairs(expected) do
      T.eq(actual[color], n, "seed=" .. seed .. " color " .. color)
    end
  end
end)

T.test("U-face slot displays correct face after each whole-cube rotation", function()
  -- After x: U holds old F (green). After y: U unchanged (W).
  -- After z: U holds old L (orange). After x': U holds old B (blue).
  local cases = {
    { rot = "x", color = "G", group = "RubiksG" },
    { rot = "y", color = "W", group = "RubiksW" },
    { rot = "z", color = "O", group = "RubiksO" },
    { rot = "x'", color = "B", group = "RubiksB" },
    { rot = "z'", color = "R", group = "RubiksR" },
  }
  for _, c in ipairs(cases) do
    local s = cube.new()
    cube.apply(s, c.rot)
    T.eq(s.U[5], c.color, "state check: U[5] after " .. c.rot)
    local buf = fresh_buf()
    render.repaint(buf, s, {})
    local _, hls = render.snapshot(buf)
    local count = 0
    for i = 1, 9 do
      local region = render.STICKER_REGIONS.U[i][1]
      if find_highlight(hls, region, c.group) then
        count = count + 1
      end
    end
    T.eq(count, 9, "after " .. c.rot .. ", U slot should have 9 " .. c.color .. " stickers")
  end
end)

T.test("repaint after every face turn matches state via highlights", function()
  for _, m in ipairs({ "U", "D", "L", "R", "F", "B", "U'", "D'", "L'", "R'", "F'", "B'" }) do
    local s = cube.new()
    cube.apply(s, m)
    local buf = fresh_buf()
    render.repaint(buf, s, {})
    local _, hls = render.snapshot(buf)
    for _, face in ipairs({ "U", "F", "R" }) do
      for i = 1, 9 do
        local region = render.STICKER_REGIONS[face][i][1]
        local color = s[face][i]
        local group = render.HL[color].group
        T.truthy(
          find_highlight(hls, region, group),
          "after " .. m .. ", " .. face .. "[" .. i .. "]=" .. color
        )
      end
    end
  end
end)

-- ============ Render: format_time edge cases ============

T.test("format_time: zero and small values", function()
  T.eq(render.format_time(0), "0:00.00")
  T.eq(render.format_time(10), "0:00.01")
  T.eq(render.format_time(990), "0:00.99")
end)

T.test("format_time: minute and hour boundaries", function()
  T.eq(render.format_time(59990), "0:59.99")
  T.eq(render.format_time(60000), "1:00.00")
  T.eq(render.format_time(60010), "1:00.01")
  T.eq(render.format_time(599990), "9:59.99")
  T.eq(render.format_time(600000), "10:00.00")
end)

T.test("format_time: nil and negative", function()
  T.eq(render.format_time(nil), "--:--.--")
  -- Negative shouldn't crash — graceful is fine.
  local ok = pcall(render.format_time, -100)
  T.truthy(ok, "format_time should not crash on negative")
end)

-- ============ Render: popup + flash robustness ============

T.test("show_solve_popup with nil elapsed renders something sensible", function()
  local popup = render.show_solve_popup(nil, 5, nil, false, function() end)
  T.truthy(popup.win)
  T.truthy(vim.api.nvim_win_is_valid(popup.win))
  popup.close()
end)

T.test("show_solve_popup with zero moves", function()
  local popup = render.show_solve_popup(1234, 0, nil, false, function() end)
  T.truthy(popup.win)
  T.truthy(vim.api.nvim_win_is_valid(popup.win))
  popup.close()
end)

T.test("show_solve_popup shows NEW PERSONAL BEST banner when is_new_best=true", function()
  local popup = render.show_solve_popup(8000, 30, 12000, true, function() end)
  local lines = vim.api.nvim_buf_get_lines(popup.buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  T.truthy(text:find("NEW PERSONAL BEST", 1, true), "banner present")
  T.truthy(text:find("Prior", 1, true), "prior time shown")
  popup.close()
end)

T.test("show_solve_popup shows existing Best line when not a new best", function()
  local popup = render.show_solve_popup(15000, 30, 12000, false, function() end)
  local lines = vim.api.nvim_buf_get_lines(popup.buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  T.falsy(text:find("NEW PERSONAL BEST", 1, true), "no banner")
  T.truthy(text:find("Best:", 1, true), "best line present")
  T.truthy(text:find("0:12.00", 1, true), "best time formatted")
  popup.close()
end)

T.test("show_solve_popup with no prior best shows dashes for Best", function()
  local popup = render.show_solve_popup(15000, 30, nil, false, function() end)
  local lines = vim.api.nvim_buf_get_lines(popup.buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  T.truthy(text:find("Best:", 1, true))
  T.truthy(text:find("--:--.--", 1, true))
  popup.close()
end)

T.test("flash with 0ms still fires callback", function()
  local called = false
  render.flash(0, function()
    called = true
  end)
  vim.wait(50, function()
    return called
  end)
  T.truthy(called)
end)

T.test("snapshot is deterministic: two snapshots of the same buffer agree", function()
  local s = cube.new()
  cube.scramble(s, 20, 4)
  local buf = fresh_buf()
  render.repaint(buf, s, {})
  local l1, h1 = render.snapshot(buf)
  local l2, h2 = render.snapshot(buf)
  T.same(l1, l2)
  T.eq(#h1, #h2)
end)

T.test("no two highlights share the same (row, col) anchor", function()
  -- A bug in region computation could overlap stickers; this catches that.
  for seed = 1, 5 do
    local s = cube.new()
    cube.scramble(s, 20, seed)
    local buf = fresh_buf()
    render.repaint(buf, s, {})
    local _, hls = render.snapshot(buf)
    local seen = {}
    for _, h in ipairs(hls) do
      if h.hl_group:sub(1, 6) == "Rubiks" then
        local key = h.row .. "," .. h.col
        T.falsy(seen[key], "seed=" .. seed .. " duplicate sticker anchor " .. key)
        seen[key] = h.hl_group
      end
    end
  end
end)

T.test("status_line shows updated last_move and move_count for many cases", function()
  local samples = {
    { "U", 1 },
    { "U'", 5 },
    { "F", 17 },
    { "B'", 100 },
    { "x", 42 },
    { "scramble", 0 },
  }
  for _, sm in ipairs(samples) do
    local line = render.status_line(sm[1], sm[2])
    T.truthy(line:find(sm[1], 1, true), "shows " .. sm[1])
    T.truthy(line:find(tostring(sm[2]), 1, true), "shows count " .. sm[2])
  end
end)

T.test("render produces 6 highlight groups even on solved input (idempotent setup)", function()
  -- Setup is meant to be called any number of times safely.
  render.setup()
  render.setup()
  render.setup()
  for _, c in ipairs({ "W", "Y", "O", "R", "G", "B" }) do
    local hl = vim.api.nvim_get_hl(0, { name = render.HL[c].group })
    T.truthy(hl, "missing " .. c)
  end
end)

T.test("repaint cleans up old highlights from a previously rendered scrambled state", function()
  local buf = fresh_buf()
  local s1 = cube.new()
  cube.scramble(s1, 20, 1)
  render.repaint(buf, s1, {})
  local _, h1 = render.snapshot(buf)
  -- Re-render with solved cube; should overwrite extmarks, not accumulate.
  render.repaint(buf, cube.new(), {})
  local _, h2 = render.snapshot(buf)
  T.eq(#h1, #h2, "extmark count stable across repaints")
  -- And the U-face after solved should be all RubiksW.
  local w_in_U = 0
  for i = 1, 9 do
    local region = render.STICKER_REGIONS.U[i][1]
    for _, h in ipairs(h2) do
      if h.row == region.row and h.col == region.col_start and h.hl_group == "RubiksW" then
        w_in_U = w_in_U + 1
        break
      end
    end
  end
  T.eq(w_in_U, 9, "U should be all white after repaint to solved")
end)
