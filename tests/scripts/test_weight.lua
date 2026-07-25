--[[
  test_weight.lua — F2 state machine: override only inside own base,
  automatic restore on leave, config off-switch (test plan W1/W2/W4 logic).
]]

local stub = require("stub_ue4ss")
local fakes = require("fakes")
local T = require("test_util")

local WEIGHT_PATH = "/Script/Pal.PalPlayerInventoryData:GetMaxInventoryWeight"

local function world(opts)
  opts = opts or {}
  stub.reset_modules()
  local pawn = fakes.pawn(opts.x or 50, 0)
  local env = stub.install({
    objects = { PlayerController = fakes.controller(pawn) },
    all_objects = { PalBaseCampModel = { fakes.base_model(0, 0, 2000) } },
    hooks_succeed = { [WEIGHT_PATH] = true },
    loop_iterations = 1,
  })
  local loader = require("config.loader")
  local cfg = loader.load()
  if opts.mutate_cfg then opts.mutate_cfg(cfg) end
  require("core.base_context").init(cfg)
  require("features.weight_in_base").init(cfg)
  return { env = env, cfg = cfg, pawn = pawn }
end

T.test("inside own base: hook overrides max weight to configured value", function()
  local w = world({ x = 50 })
  require("hooks.weight_hooks").register(w.cfg)
  local cb = w.env.hooks[WEIGHT_PATH]
  T.check(cb ~= nil, "hook captured")
  T.eq(cb(nil), 1000000, "override active inside base")
end)

T.test("outside base: hook yields nothing, vanilla value stands (restore)", function()
  local w = world({ x = 50 })
  require("hooks.weight_hooks").register(w.cfg)
  local cb = w.env.hooks[WEIGHT_PATH]
  T.eq(cb(nil), 1000000, "buff on inside")
  -- walk out of the base and let the poll tick
  w.pawn._loc = fakes.vec(9000, 0)
  require("features.weight_in_base").update()
  T.eq(cb(nil), nil, "no override outside -> vanilla restored")
  T.check(stub.log_contains("left base"), "leave transition logged")
end)

T.test("weight disabled via config: no hook, no override", function()
  local w = world({ mutate_cfg = function(cfg) cfg.weight.enabled = false end })
  local ok = require("hooks.weight_hooks").register(w.cfg)
  T.eq(ok, false, "register declines when disabled")
  T.check(w.env.hooks[WEIGHT_PATH] == nil, "no hook registered")
end)

T.test("teleport back in re-applies within one poll tick (W4)", function()
  local w = world({ x = 9000 })
  require("hooks.weight_hooks").register(w.cfg)
  local cb = w.env.hooks[WEIGHT_PATH]
  T.eq(cb(nil), nil, "starts outside, no buff")
  w.pawn._loc = fakes.vec(10, 10)
  require("features.weight_in_base").update()
  T.eq(cb(nil), 1000000, "buff after re-entering")
end)

T.test("strict ownership mode without group APIs refuses the buff", function()
  local w = world({ x = 50, mutate_cfg = function(cfg)
    cfg.weight.assume_own_base_when_unverified = false
  end })
  require("hooks.weight_hooks").register(w.cfg)
  local cb = w.env.hooks[WEIGHT_PATH]
  T.eq(cb(nil), nil, "no buff when ownership cannot be verified in strict mode")
end)
