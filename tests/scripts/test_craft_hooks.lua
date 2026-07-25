--[[
  test_craft_hooks.lua — F1 hook gating and double-consume prevention
  (CLAUDE.md rule 2, spec §6.6).
]]

local stub = require("stub_ue4ss")
local fakes = require("fakes")
local T = require("test_util")

local COUNT_PATH = "/Script/Pal.FakeCraft:GetMaterialNum"
local CONSUME_PATH = "/Script/Pal.FakeCraft:ConsumeMaterials"

local function world(opts)
  opts = opts or {}
  stub.reset_modules()

  local chest = fakes.container("A", { { "Wood", 30 } })
  local player_inv = fakes.container("PlayerInv", { { "Wood", 5 } })
  local pawn = fakes.pawn(50, 0, player_inv)

  local env = stub.install({
    objects = { PlayerController = fakes.controller(pawn) },
    all_objects = {
      PalBaseCampModel = { fakes.base_model(0, 0, 2000) },
      PalMapObjectItemContainerModel = { fakes.chest_model(chest, 100, 0) },
    },
    hooks_succeed = {
      [COUNT_PATH] = true,
      [CONSUME_PATH] = true,
    },
  })

  local loader = require("config.loader")
  local cfg = loader.load()
  cfg.api.craft.count_hook = COUNT_PATH
  cfg.api.craft.consume_hook = CONSUME_PATH
  if opts.mutate_cfg then opts.mutate_cfg(cfg) end

  require("core.base_context").init(cfg)
  require("core.storage_index").init(cfg)
  require("core.item_ops").init(cfg)
  require("features.unified_craft").init(cfg)

  return { env = env, cfg = cfg, pawn = pawn, chest = chest, player_inv = player_inv }
end

local function total_wood(w)
  return w.chest._slots[1]._count + w.player_inv._slots[1]._count
end

T.test("F1 refuses to register with unverified (nil) hook paths", function()
  local w = world({ mutate_cfg = function(cfg)
    cfg.api.craft.count_hook = nil
    cfg.api.craft.consume_hook = nil
  end })
  local craft_hooks = require("hooks.craft_hooks")
  T.eq(craft_hooks.register(w.cfg), false, "register must decline")
  T.check(stub.log_contains("SOFT-DISABLED"), "soft-disable logged")
  T.check(next(w.env.hooks) == nil, "no hook actually registered")
end)

T.test("count hook returns the unified total", function()
  local w = world()
  local craft_hooks = require("hooks.craft_hooks")
  T.eq(craft_hooks.register(w.cfg), true, "register ok")
  local count_cb = w.env.hooks[COUNT_PATH]
  T.check(count_cb ~= nil, "count callback captured")
  local result = count_cb(nil, { get = function() return "Wood" end })
  T.eq(result, 35, "30 chest + 5 player")
end)

T.test("vanilla_fallback: vanilla success means we take NOTHING (no double-consume)", function()
  local w = world()
  require("hooks.craft_hooks").register(w.cfg)
  local consume_cb = w.env.hooks[CONSUME_PATH]
  local before = total_wood(w)
  local override = consume_cb(nil, fakes.cost_array({ { "Wood", 10 } }), fakes.bool_param(true))
  T.eq(override, nil, "vanilla result untouched")
  T.eq(total_wood(w), before, "unified pool untouched when vanilla paid")
end)

T.test("vanilla_fallback: vanilla failure + affordable pool -> we pay and flip result", function()
  local w = world()
  require("hooks.craft_hooks").register(w.cfg)
  local consume_cb = w.env.hooks[CONSUME_PATH]
  local override = consume_cb(nil, fakes.cost_array({ { "Wood", 10 } }), fakes.bool_param(false))
  T.eq(override, true, "hook overrides failure to success")
  T.eq(total_wood(w), 25, "exactly 10 wood taken once")
end)

T.test("vanilla_fallback: vanilla failure + unaffordable pool -> failure stands, nothing taken", function()
  local w = world()
  require("hooks.craft_hooks").register(w.cfg)
  local consume_cb = w.env.hooks[CONSUME_PATH]
  local override = consume_cb(nil, fakes.cost_array({ { "Wood", 100 } }), fakes.bool_param(false))
  T.eq(override, nil, "failure not overridden")
  T.eq(total_wood(w), 35, "nothing taken")
end)

T.test("vanilla_fallback: unreadable vanilla result -> never consume (safe mode)", function()
  local w = world()
  require("hooks.craft_hooks").register(w.cfg)
  local consume_cb = w.env.hooks[CONSUME_PATH]
  -- last param is not a readable boolean
  local override = consume_cb(nil, fakes.cost_array({ { "Wood", 10 } }))
  T.eq(override, nil, "no override")
  T.eq(total_wood(w), 35, "nothing taken in safe mode")
  T.check(stub.log_contains("unified consume stays inactive"), "safe-mode reason logged once")
end)

T.test("replace mode consumes exactly once per call", function()
  local w = world({ mutate_cfg = function(cfg) cfg.craft.consume_mode = "replace" end })
  require("hooks.craft_hooks").register(w.cfg)
  local consume_cb = w.env.hooks[CONSUME_PATH]
  local override = consume_cb(nil, fakes.cost_array({ { "Wood", 10 } }), fakes.bool_param(false))
  T.eq(override, true, "replace mode reports success")
  T.eq(total_wood(w), 25, "10 taken once")
end)

T.test("craft disabled via config: no hooks registered at all", function()
  local w = world({ mutate_cfg = function(cfg) cfg.craft.enabled = false end })
  local craft_hooks = require("hooks.craft_hooks")
  T.eq(craft_hooks.register(w.cfg), false, "register declines")
  T.check(next(w.env.hooks) == nil, "no hooks registered")
end)
