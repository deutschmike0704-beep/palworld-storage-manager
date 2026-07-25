--[[
  run_all.lua — offline test runner for PalStorageManager.

  Usage (from the repo root):
    lua tests/scripts/run_all.lua

  Runs the mod's Lua modules under plain Lua 5.4 (same major version as
  UE4SS) against stubbed UE4SS globals and fake game objects. This verifies
  require-graph integrity, fail-soft behavior, and the count/consume logic —
  it does NOT replace in-game testing (see docs/guides/TESTING_GAMEPASS.md).
]]

package.path = table.concat({
  "src/PalStorageManager/Scripts/?.lua",
  "tests/scripts/?.lua",
  package.path,
}, ";")

local real_print = print
local T = require("test_util")

local files = {
  "test_bootstrap",
  "test_weight",
  "test_storage",
  "test_craft_hooks",
}

for _, f in ipairs(files) do
  _G.print = real_print
  io.write("== " .. f .. " ==\n")
  local ok, err = pcall(require, f)
  _G.print = real_print
  if not ok then
    T.failures = T.failures + 1
    io.write("FAIL  " .. f .. " (file error)\n      " .. tostring(err) .. "\n")
  end
end

_G.print = real_print
io.write(string.format("\n%d test(s), %d failure(s)\n", T.tests, T.failures))
os.exit(T.failures == 0 and 0 or 1)
