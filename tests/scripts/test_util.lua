-- test_util.lua — micro test framework (no dependencies).
local M = { failures = 0, tests = 0, current = nil }

function M.test(name, fn)
  M.current = name
  M.tests = M.tests + 1
  local ok, err = pcall(fn)
  if ok then
    io.write(string.format("PASS  %s\n", name))
  else
    M.failures = M.failures + 1
    io.write(string.format("FAIL  %s\n      %s\n", name, tostring(err)))
  end
end

function M.check(cond, label)
  if not cond then
    error(string.format("check failed: %s", label or "?"), 2)
  end
end

function M.eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s",
      label or "eq", tostring(expected), tostring(actual)), 2)
  end
end

return M
