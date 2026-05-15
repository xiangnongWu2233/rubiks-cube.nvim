-- Parse a Singmaster-notation move string (as emitted by the kociemba solver)
-- into a flat sequence of moves compatible with cube.apply.
--
-- kociemba output looks like: "R U R' U2 F2 D' L"
-- cube.apply understands "R" and "R'" but not "R2" — so "R2" expands to
-- {"R", "R"} and "R2'" (rare but legal in some notations) to {"R'", "R'"}.

local M = {}

local FACE_TOKENS = { U = true, D = true, L = true, R = true, F = true, B = true }

-- Splits on whitespace, returns array of non-empty tokens.
local function tokenize(str)
  local out = {}
  for tok in str:gmatch("%S+") do
    out[#out + 1] = tok
  end
  return out
end

-- Expands one token like "R", "R'", "R2", "R2'" into 1 or 2 cube.apply-compatible moves.
local function expand(tok)
  local face, rest = tok:sub(1, 1), tok:sub(2)
  if not FACE_TOKENS[face] then
    return nil, "unknown face '" .. face .. "' in token '" .. tok .. "'"
  end
  if rest == "" then
    return { face }
  elseif rest == "'" then
    return { face .. "'" }
  elseif rest == "2" then
    return { face, face }
  elseif rest == "2'" then
    return { face .. "'", face .. "'" }
  else
    return nil, "unrecognized move suffix '" .. rest .. "' in token '" .. tok .. "'"
  end
end

-- Returns (moves, nil) on success or (nil, err) on bad input.
function M.parse(str)
  if type(str) ~= "string" then
    return nil, "moves.parse: expected string, got " .. type(str)
  end
  local out = {}
  for _, tok in ipairs(tokenize(str)) do
    local expanded, err = expand(tok)
    if not expanded then
      return nil, err
    end
    for _, m in ipairs(expanded) do
      out[#out + 1] = m
    end
  end
  return out
end

return M
