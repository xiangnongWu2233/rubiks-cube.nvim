-- Pure-Lua layer-by-layer (beginner method) solver for the tutorial mode.
--
-- Produces a solution segmented into pedagogical stages, each with a name and
-- a human explanation — the data the tutorial UI steps through. Unlike the
-- kociemba auto-solver this needs no external binary. Solutions are long
-- (beginner-style, ~150-250 moves) on purpose: these are the moves a human
-- would learn, using only the standard beginner algorithms (the R U R' U'
-- trigger, F R U R' U' F', Sune, Niklas, R' D' R D).

local cube = require("rubikscube.cube")

local M = {}

-- Sticker coordinates for every edge/corner slot, derived from cube.lua's
-- per-face indexing convention. For U/D slots the U/D sticker is listed first.
local EDGES = {
  UF = { { "U", 8 }, { "F", 2 } },
  UR = { { "U", 6 }, { "R", 2 } },
  UB = { { "U", 2 }, { "B", 2 } },
  UL = { { "U", 4 }, { "L", 2 } },
  FR = { { "F", 6 }, { "R", 4 } },
  FL = { { "F", 4 }, { "L", 6 } },
  BR = { { "B", 4 }, { "R", 6 } },
  BL = { { "B", 6 }, { "L", 4 } },
  DF = { { "D", 2 }, { "F", 8 } },
  DR = { { "D", 6 }, { "R", 8 } },
  DB = { { "D", 8 }, { "B", 8 } },
  DL = { { "D", 4 }, { "L", 8 } },
}

local CORNERS = {
  UFR = { { "U", 9 }, { "F", 3 }, { "R", 1 } },
  UFL = { { "U", 7 }, { "F", 1 }, { "L", 3 } },
  UBL = { { "U", 1 }, { "B", 3 }, { "L", 1 } },
  UBR = { { "U", 3 }, { "B", 1 }, { "R", 3 } },
  DFR = { { "D", 3 }, { "F", 9 }, { "R", 7 } },
  DFL = { { "D", 1 }, { "F", 7 }, { "L", 9 } },
  DBL = { { "D", 7 }, { "B", 9 }, { "L", 7 } },
  DBR = { { "D", 9 }, { "B", 7 }, { "R", 9 } },
}

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function sticker(s, ref)
  return s[ref[1]][ref[2]]
end

local function edge_colors(s, slot)
  local e = EDGES[slot]
  return sticker(s, e[1]), sticker(s, e[2])
end

local function corner_colors(s, slot)
  local c = CORNERS[slot]
  return sticker(s, c[1]), sticker(s, c[2]), sticker(s, c[3])
end

local function find_edge(s, x, y)
  for slot in pairs(EDGES) do
    local a, b = edge_colors(s, slot)
    if (a == x and b == y) or (a == y and b == x) then
      return slot
    end
  end
  error("edge not found: " .. x .. y)
end

local function find_corner(s, x, y, z)
  for slot in pairs(CORNERS) do
    local a, b, c = corner_colors(s, slot)
    local set = { [a] = true, [b] = true, [c] = true }
    if set[x] and set[y] and set[z] then
      return slot
    end
  end
  error("corner not found: " .. x .. y .. z)
end

-- All faces uniform == solved, regardless of whole-cube rotations.
function M.is_solved_any_orientation(s)
  for _, face in ipairs(cube.FACES) do
    local arr = s[face]
    for i = 1, 9 do
      if arr[i] ~= arr[5] then
        return false
      end
    end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Move tables (all derived from cube.lua's turn definitions)
-- ---------------------------------------------------------------------------

-- U-layer edge cycle under U is UF→UL→UB→UR; moves bringing a slot to UF:
local U_EDGE_TO_UF = { UF = {}, UR = { "U" }, UB = { "U", "U" }, UL = { "U'" } }
-- U-layer corner cycle under U is UFR→UFL→UBL→UBR; moves bringing a slot to UFR:
local U_CORNER_TO_UFR = { UFR = {}, UBR = { "U" }, UBL = { "U", "U" }, UFL = { "U'" } }
-- Whole-cube y rotation moves a slot's PHYSICAL position F→L; bring slot to FR:
local Y_SLOT_TO_FR = { FR = {}, BR = { "y" }, BL = { "y", "y" }, FL = { "y'" } }
-- Bring a U-layer corner slot to UFR by rotating the whole cube:
local Y_CORNER_TO_UFR = { UFR = {}, UBR = { "y" }, UBL = { "y", "y" }, UFL = { "y'" } }

-- Lift a wrongly-placed D-layer cross edge straight up to the U layer.
local CROSS_D_LIFT = { DF = { "F", "F" }, DR = { "R", "R" }, DB = { "B", "B" }, DL = { "L", "L" } }
-- Lift a middle-layer edge to the U layer; trailing undo restores the cross
-- edge the first turn displaced.
local CROSS_MID_LIFT = {
  FR = { "R", "U", "R'" },
  FL = { "L'", "U", "L" },
  BR = { "R'", "U", "R" },
  BL = { "L", "U", "L'" },
}
-- Lift a wrongly-placed D-layer corner to the U layer (same restore trick).
local CORNER_LIFT = {
  DFR = { "R", "U", "R'" },
  DFL = { "L'", "U'", "L" },
  DBR = { "R'", "U'", "R" },
  DBL = { "L", "U", "L'" },
}

local SEXY = { "R", "U", "R'", "U'" }
local INSERT_RIGHT = { "U", "R", "U'", "R'", "U'", "F'", "U", "F" }
local INSERT_LEFT_FROM_UR = { "U'", "F'", "U", "F", "U", "R", "U'", "R'" }
local YELLOW_CROSS_ALG = { "F", "R", "U", "R'", "U'", "F'" }
local SUNE = { "R", "U", "R'", "U", "R", "U", "U", "R'" }
local NIKLAS = { "U", "R", "U'", "L'", "U", "R'", "U'", "L" }
local TWIST = { "R'", "D'", "R", "D" }

-- Map "which face holds white" → rotation putting white on D.
local WHITE_TO_D =
  { U = { "x", "x" }, D = {}, F = { "x'" }, B = { "x" }, L = { "z'" }, R = { "z" } }

-- ---------------------------------------------------------------------------
-- Tiny peephole cleanup: cancel adjacent inverses, fold triples (X X X → X').
-- ---------------------------------------------------------------------------

local function inverse(m)
  return m:find("'") and m:sub(1, -2) or (m .. "'")
end

local function cleanup(seq)
  local changed = true
  while changed do
    changed = false
    local i = 1
    while i <= #seq do
      if seq[i + 1] and seq[i + 1] == inverse(seq[i]) then
        table.remove(seq, i + 1)
        table.remove(seq, i)
        changed = true
        i = math.max(1, i - 1)
      elseif seq[i + 2] and seq[i] == seq[i + 1] and seq[i] == seq[i + 2] then
        table.remove(seq, i + 2)
        table.remove(seq, i + 1)
        seq[i] = inverse(seq[i])
        changed = true
      else
        i = i + 1
      end
    end
  end
  return seq
end

-- ---------------------------------------------------------------------------
-- Solver
-- ---------------------------------------------------------------------------

-- Returns { stages = { {name, desc, moves}, ... }, moves = flat list }.
-- Does not mutate `state`.
function M.solve(state)
  local s = cube.copy(state)
  local stages = {}
  local rec -- move recorder for the current stage

  local function play(moves)
    for _, m in ipairs(moves) do
      cube.apply(s, m)
      rec[#rec + 1] = m
    end
  end

  local function stage(name, desc, fn)
    rec = {}
    fn()
    stages[#stages + 1] = { name = name, desc = desc, moves = cleanup(rec) }
  end

  local function guard(cond, what)
    if not cond then
      error("lbl solver stuck in stage: " .. what)
    end
  end

  -- Stage 1: hold the cube white-side-down.
  stage(
    "Hold the cube",
    "Find the white center and turn the whole cube so white faces down.",
    function()
      for face in pairs(cube.SOLVED_COLORS) do
        if s[face][5] == "W" then
          play(WHITE_TO_D[face])
          return
        end
      end
    end
  )

  local W = s.D[5]

  -- Stage 2: white cross. Solve each white edge with its side color held at F.
  stage(
    "White cross",
    "Place the four white edges around the white center, matching each side color to its center.",
    function()
      for _ = 1, 4 do
        local c = s.F[5]
        local done = false
        for _ = 1, 12 do
          local slot = find_edge(s, W, c)
          if slot == "DF" and s.D[2] == W then
            done = true
            break
          elseif CROSS_D_LIFT[slot] and slot ~= "DF" then
            play(CROSS_D_LIFT[slot])
          elseif slot == "DF" then -- in place but flipped
            play(CROSS_D_LIFT.DF)
          elseif CROSS_MID_LIFT[slot] then
            play(CROSS_MID_LIFT[slot])
          else -- U layer: align over the front slot, then drop in
            play(U_EDGE_TO_UF[slot])
            if s.U[8] == W then
              play({ "F", "F" })
            else -- white faces front: thread it in through the right side
              play({ "F", "D", "R'", "D'" })
            end
          end
        end
        guard(done, "white cross")
        play({ "y" })
      end
    end
  )

  -- Stage 3: white corners via the repeated R U R' U' "trigger".
  stage(
    "White corners",
    "Put each white corner above its home slot, then repeat R U R' U' until it drops in correctly.",
    function()
      for _ = 1, 4 do
        local c1, c2 = s.F[5], s.R[5]
        local done = false
        for _ = 1, 12 do
          local slot = find_corner(s, W, c1, c2)
          if slot == "DFR" and s.D[3] == W and s.F[9] == c1 then
            done = true
            break
          elseif CORNER_LIFT[slot] then
            play(CORNER_LIFT[slot])
          else
            play(U_CORNER_TO_UFR[slot])
            for _ = 1, 6 do
              play(SEXY)
              if s.D[3] == W and s.F[9] == c1 and s.R[7] == c2 then
                break
              end
            end
          end
        end
        guard(done, "white corners")
        play({ "y" })
      end
    end
  )

  -- Stage 4: middle-layer edges.
  stage(
    "Middle layer",
    "Insert the four side edges: match an edge with a center to form an upside-down T, then insert right or left.",
    function()
      local function slot_solved(slot)
        local e = EDGES[slot]
        local a, b = edge_colors(s, slot)
        return a == s[e[1][1]][5] and b == s[e[2][1]][5]
      end
      local function middle_solved_count()
        local n = 0
        for _, slot in ipairs({ "FR", "FL", "BR", "BL" }) do
          n = n + (slot_solved(slot) and 1 or 0)
        end
        return n
      end
      local Y = s.U[5]
      local centers_to_slot = function(a, b)
        for _, slot in ipairs({ "FR", "FL", "BR", "BL" }) do
          local e = EDGES[slot]
          local ca, cb = s[e[1][1]][5], s[e[2][1]][5]
          if (ca == a and cb == b) or (ca == b and cb == a) then
            return slot
          end
        end
      end
      for _ = 1, 16 do
        if middle_solved_count() == 4 then
          return
        end
        -- Prefer inserting a middle edge waiting in the U layer.
        local acted = false
        for _, uslot in ipairs({ "UF", "UR", "UB", "UL" }) do
          local u, side = edge_colors(s, uslot)
          if u ~= Y and side ~= Y then
            play(Y_SLOT_TO_FR[centers_to_slot(u, side)])
            -- relocate after the cube rotation
            local cur = find_edge(s, u, side)
            local e = EDGES[cur]
            local side_color = s[e[2][1]][e[2][2]]
            if side_color == s.F[5] then
              play(U_EDGE_TO_UF[cur])
              play(INSERT_RIGHT)
            else
              -- align the edge to UR (side sticker on R), mirror insert
              local to_ur = { UR = {}, UB = { "U" }, UL = { "U", "U" }, UF = { "U'" } }
              play(to_ur[cur])
              play(INSERT_LEFT_FROM_UR)
            end
            acted = true
            break
          end
        end
        if not acted then
          -- A needed edge is stuck (or flipped) in a middle slot: eject it by
          -- running the insert alg on that slot with whatever is on top.
          for _, slot in ipairs({ "FR", "FL", "BR", "BL" }) do
            local a, b = edge_colors(s, slot)
            if a ~= Y and b ~= Y and not slot_solved(slot) then
              play(Y_SLOT_TO_FR[slot])
              play(INSERT_RIGHT)
              acted = true
              break
            end
          end
        end
        guard(acted, "middle layer")
      end
      guard(middle_solved_count() == 4, "middle layer")
    end
  )

  local Y = s.U[5]

  -- Stage 5: yellow cross (orient last-layer edges).
  stage(
    "Yellow cross",
    "Make a yellow plus on top with F R U R' U' F': dot → L-shape (held back-left) → line (held across) → cross.",
    function()
      local function yellow_up()
        local n = 0
        for _, i in ipairs({ 2, 4, 6, 8 }) do
          n = n + (s.U[i] == Y and 1 or 0)
        end
        return n
      end
      for _ = 1, 8 do
        if yellow_up() == 4 then
          return
        end
        if yellow_up() == 2 then
          -- rotate U until the shape sits as back-left L or horizontal line
          for _ = 1, 4 do
            if (s.U[2] == Y and s.U[4] == Y) or (s.U[4] == Y and s.U[6] == Y) then
              break
            end
            play({ "U" })
          end
        end
        play(YELLOW_CROSS_ALG)
      end
      guard(yellow_up() == 4, "yellow cross")
    end
  )

  -- Stage 6: permute last-layer edges (match side colors) with Sune.
  stage(
    "Yellow edges",
    "Turn the top until at least two yellow edges match their centers, then cycle the rest with R U R' U R U2 R'.",
    function()
      local USLOTS = { "UF", "UR", "UB", "UL" }
      local function matched_after(k)
        local t = cube.copy(s)
        for _ = 1, k do
          cube.apply(t, "U")
        end
        local set, n = {}, 0
        for _, slot in ipairs(USLOTS) do
          local e = EDGES[slot]
          if t[e[2][1]][e[2][2]] == t[e[2][1]][5] then
            set[slot] = true
            n = n + 1
          end
        end
        return n, set
      end
      for _ = 1, 12 do
        local best_k, best_n, best_set = 0, -1, nil
        for k = 0, 3 do
          local n, set = matched_after(k)
          if n > best_n then
            best_k, best_n, best_set = k, n, set
          end
        end
        for _ = 1, best_k do
          play({ "U" })
        end
        if best_n == 4 then
          return
        end
        if best_n >= 2 then
          if (best_set.UF and best_set.UB) or (best_set.UL and best_set.UR) then
            play(SUNE) -- opposite pair: one Sune turns it into an adjacent pair
          else
            -- adjacent pair: rotate the whole cube so the matched two sit at back+right
            for _ = 1, 4 do
              local _, set = matched_after(0)
              if set.UB and set.UR then
                break
              end
              play({ "y" })
            end
            play(SUNE)
          end
        else
          play(SUNE)
        end
      end
      local n = matched_after(0)
      guard(n == 4, "yellow edges")
    end
  )

  -- Stage 7: permute last-layer corners with Niklas.
  stage(
    "Yellow corners",
    "Find a corner already between its three matching centers, hold it front-right, and cycle the others with U R U' L' U R' U' L.",
    function()
      local USLOTS = { "UFR", "UFL", "UBL", "UBR" }
      local function positioned(slot)
        local refs = CORNERS[slot]
        local want = {}
        for _, r in ipairs(refs) do
          want[s[r[1]][5]] = true
        end
        local a, b, c = corner_colors(s, slot)
        return want[a] and want[b] and want[c]
      end
      for _ = 1, 12 do
        local fixed = nil
        local n = 0
        for _, slot in ipairs(USLOTS) do
          if positioned(slot) then
            n = n + 1
            fixed = fixed or slot
          end
        end
        if n == 4 then
          return
        end
        if fixed then
          play(Y_CORNER_TO_UFR[fixed])
        end
        play(NIKLAS)
      end
      guard(false, "yellow corners")
    end
  )

  -- Stage 8: orient last-layer corners with the R' D' R D trigger.
  stage(
    "Twist corners",
    "With an unsolved corner at front-right-top, repeat R' D' R D until its yellow faces up; turn ONLY the top to bring the next corner, then align the top at the end.",
    function()
      local function all_oriented()
        return s.U[1] == Y and s.U[3] == Y and s.U[7] == Y and s.U[9] == Y
      end
      for _ = 1, 48 do
        if all_oriented() then
          break
        end
        if s.U[9] ~= Y then
          play(TWIST)
        else
          play({ "U" })
        end
      end
      guard(all_oriented(), "twist corners")
      for _ = 1, 4 do
        if M.is_solved_any_orientation(s) then
          return
        end
        play({ "U" })
      end
      guard(M.is_solved_any_orientation(s), "final alignment")
    end
  )

  local flat = {}
  for _, st in ipairs(stages) do
    for _, m in ipairs(st.moves) do
      flat[#flat + 1] = m
    end
  end
  return { stages = stages, moves = flat }
end

return M
