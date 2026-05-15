local M = {}

M.passed = 0
M.failed = 0
M.failures = {}
M._current_suite = "?"

function M.suite(name)
  M._current_suite = name
end

local function deep_equal(a, b)
  if a == b then
    return true
  end
  if type(a) ~= "table" or type(b) ~= "table" then
    return false
  end
  for k, v in pairs(a) do
    if not deep_equal(v, b[k]) then
      return false
    end
  end
  for k, _ in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

local function fmt(v)
  if type(v) == "table" then
    local parts = {}
    -- assume array
    for i, x in ipairs(v) do
      parts[i] = tostring(x)
    end
    if #parts > 0 then
      return "{" .. table.concat(parts, ",") .. "}"
    end
    local kvs = {}
    for k, x in pairs(v) do
      kvs[#kvs + 1] = tostring(k) .. "=" .. tostring(x)
    end
    return "{" .. table.concat(kvs, ",") .. "}"
  end
  return tostring(v)
end

function M.test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    M.passed = M.passed + 1
  else
    M.failed = M.failed + 1
    table.insert(M.failures, M._current_suite .. " :: " .. name .. " :: " .. tostring(err))
  end
end

function M.eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "eq") .. ": expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
  end
end

function M.same(actual, expected, msg)
  if not deep_equal(actual, expected) then
    error((msg or "same") .. ": expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
  end
end

function M.neq(actual, expected, msg)
  if actual == expected then
    error((msg or "neq") .. ": did not expect " .. fmt(expected), 2)
  end
end

function M.nsame(actual, expected, msg)
  if deep_equal(actual, expected) then
    error((msg or "nsame") .. ": did not expect deep-equal " .. fmt(expected), 2)
  end
end

function M.truthy(v, msg)
  if not v then
    error((msg or "truthy") .. ": expected truthy, got " .. fmt(v), 2)
  end
end

function M.falsy(v, msg)
  if v then
    error((msg or "falsy") .. ": expected falsy, got " .. fmt(v), 2)
  end
end

function M.summary()
  io.write(string.format("\n== %d passed, %d failed ==\n", M.passed, M.failed))
  if M.failed > 0 then
    io.write("\nFailures:\n")
    for _, f in ipairs(M.failures) do
      io.write("  - " .. f .. "\n")
    end
    return false
  end
  return true
end

return M
