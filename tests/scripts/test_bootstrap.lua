--[[
  test_bootstrap.lua — the mod must load and fail soft in hostile
  environments: no UE4SS globals at all, and a normal environment where
  no hook path resolves.
]]

local stub = require("stub_ue4ss")
local fakes = require("fakes")
local T = require("test_util")

local MAIN = "src/PalStorageManager/Scripts/main.lua"

-- Scenario A: completely bare environment (no UE4SS API at all).
T.test("bootstrap survives with zero UE4SS globals", function()
  stub.reset_modules()
  stub.install({ bare = true })
  dofile(MAIN)
  T.check(not stub.log_contains("fatal bootstrap error"), "no fatal error")
  T.check(stub.log_contains("bootstrap (Palworld 1.0"), "banner printed")
  T.check(stub.log_contains("init complete"), "init completed")
  T.check(stub.log_contains("F2 weight-in-base DISABLED"), "F2 fail-soft message")
  T.check(stub.log_contains("F1 unified craft storage SOFT-DISABLED"), "F1 fail-soft message")
end)

-- Scenario B: hooks API present but no candidate path resolves.
T.test("bootstrap fail-soft when no hook path resolves", function()
  stub.reset_modules()
  local pawn = fakes.pawn(0, 0)
  stub.install({
    objects = { PlayerController = fakes.controller(pawn) },
    hooks_succeed = {},
  })
  dofile(MAIN)
  T.check(not stub.log_contains("fatal bootstrap error"), "no fatal error")
  T.check(stub.log_contains("F2 weight-in-base DISABLED"), "F2 disabled cleanly")
  T.check(stub.log_contains("TODO(VERIFY)"), "TODO(VERIFY) surfaced, not hidden")
  T.check(stub.log_contains("init complete"), "init completed")
end)

-- Scenario C: weight hook resolves -> F2 activates; F1 stays gated.
T.test("F2 activates when max-weight hook registers", function()
  stub.reset_modules()
  local pawn = fakes.pawn(0, 0)
  stub.install({
    objects = { PlayerController = fakes.controller(pawn) },
    hooks_succeed = {
      ["/Script/Pal.PalPlayerInventoryData:GetMaxInventoryWeight"] = true,
    },
  })
  dofile(MAIN)
  T.check(stub.log_contains("F2 weight hook active"), "F2 hook registered")
  T.check(stub.log_contains("F2 weight-in-base: ON"), "F2 reported ON")
  T.check(stub.log_contains("F1 unified craft storage SOFT-DISABLED"), "F1 still gated")
  T.check(not stub.log_contains("fatal bootstrap error"), "no fatal error")
end)
