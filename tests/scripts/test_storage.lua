--[[
  test_storage.lua — StorageIndex discovery/count and item_ops consume
  semantics against fake containers (spec §6, test plan C1–C4 logic-level).
]]

local stub = require("stub_ue4ss")
local fakes = require("fakes")
local T = require("test_util")

-- Build a standard world: base at origin (range 2000), player inside,
-- chest A + C in base, chest B far away, player inventory with wood.
local function world(opts)
  opts = opts or {}
  stub.reset_modules()

  local chest_a = fakes.container("A", { { "Wood", 30 }, { "Stone", 10 } }, opts.chest_a_opts)
  local chest_b = fakes.container("B-far", { { "Wood", 999 } })
  local chest_c = fakes.container("C", { { "Wood", 20 } }, opts.chest_c_opts)
  local player_inv = fakes.container("PlayerInv", { { "Wood", 5 } })

  local pawn = fakes.pawn(50, 0, player_inv)
  local env = stub.install({
    objects = { PlayerController = fakes.controller(pawn) },
    all_objects = {
      PalBaseCampModel = { fakes.base_model(0, 0, 2000) },
      PalMapObjectItemContainerModel = {
        fakes.chest_model(chest_a, 100, 0),
        fakes.chest_model(chest_b, 5000, 0), -- outside base radius
        fakes.chest_model(chest_c, -300, 200),
      },
    },
    hooks_succeed = opts.hooks_succeed,
  })

  local loader = require("config.loader")
  local cfg = loader.load()
  if opts.mutate_cfg then opts.mutate_cfg(cfg) end

  require("core.base_context").init(cfg)
  require("core.storage_index").init(cfg)
  require("core.item_ops").init(cfg)
  require("features.unified_craft").init(cfg)

  return {
    env = env, cfg = cfg, pawn = pawn,
    chest_a = chest_a, chest_b = chest_b, chest_c = chest_c, player_inv = player_inv,
  }
end

local function get_index(w)
  local base_context = require("core.base_context")
  local storage_index = require("core.storage_index")
  local base = base_context.get_base_at_location({ x = 50, y = 0, z = 0 })
  T.check(base ~= nil, "base resolves at player location")
  return storage_index.get_index(base, w.pawn)
end

T.test("index counts stacks from all in-base containers + player inventory", function()
  local w = world()
  local item_ops = require("core.item_ops")
  local index = get_index(w)
  -- 30 (A) + 20 (C) + 5 (player); chest B is outside the base
  T.eq(item_ops.count_available(index, "Wood"), 55, "wood total")
  T.eq(item_ops.count_available(index, "Stone"), 10, "stone total")
  T.eq(item_ops.count_available(index, "Gold"), 0, "absent item is 0")
end)

T.test("out-of-base container is excluded (C5 scope guarantee)", function()
  local w = world()
  local index = get_index(w)
  for _, list in pairs(index.by_item) do
    for _, loc in ipairs(list) do
      T.check(not loc.container_key:find("B%-far"), "far chest must not be indexed")
    end
  end
end)

T.test("player inventory can be excluded via config", function()
  local w = world({ mutate_cfg = function(cfg) cfg.craft.include_player_inventory = false end })
  local item_ops = require("core.item_ops")
  local index = get_index(w)
  T.eq(item_ops.count_available(index, "Wood"), 50, "wood without player inventory")
end)

T.test("consume drains player inventory first (prefer_consume_order=player_first)", function()
  local w = world()
  local item_ops = require("core.item_ops")
  local index = get_index(w)
  T.check(item_ops.consume(index, { { item_key = "Wood", count = 10 } }), "consume succeeds")
  T.eq(w.player_inv._slots[1]._count, 0, "player wood drained first (5)")
  -- remaining 5 came from the first storage container in stable order (A)
  local from_a = 30 - w.chest_a._slots[1]._count
  local from_c = 20 - w.chest_c._slots[1]._count
  T.eq(from_a + from_c, 5, "exactly 5 taken from storage")
end)

T.test("consume spans multiple chests and takes exactly the requested amount (C2)", function()
  local w = world()
  local item_ops = require("core.item_ops")
  local index = get_index(w)
  T.check(item_ops.consume(index, { { item_key = "Wood", count = 50 } }), "consume 50 wood")
  local left = w.chest_a._slots[1]._count + w.chest_c._slots[1]._count + w.player_inv._slots[1]._count
  T.eq(left, 5, "5 wood remain overall")
  T.eq(w.chest_b._slots[1]._count, 999, "far chest untouched")
end)

T.test("insufficient material blocks consume with zero partial take (C3)", function()
  local w = world()
  local item_ops = require("core.item_ops")
  local index = get_index(w)
  T.check(not item_ops.consume(index, { { item_key = "Wood", count = 56 } }), "56 > 55 must fail")
  T.eq(w.chest_a._slots[1]._count, 30, "chest A untouched")
  T.eq(w.chest_c._slots[1]._count, 20, "chest C untouched")
  T.eq(w.player_inv._slots[1]._count, 5, "player inventory untouched")
end)

T.test("multi-item cost with one short item takes nothing (C3 multi)", function()
  local w = world()
  local item_ops = require("core.item_ops")
  local index = get_index(w)
  local ok = item_ops.consume(index, {
    { item_key = "Wood", count = 10 },
    { item_key = "Stone", count = 11 }, -- only 10 exist
  })
  T.check(not ok, "must fail on stone shortfall")
  T.eq(w.chest_a._slots[1]._count, 30, "wood untouched despite being affordable")
end)

T.test("misbehaving remove API is detected and consume aborts", function()
  local w = world({ chest_a_opts = { remove_is_noop = true }, chest_c_opts = { remove_is_noop = true },
    mutate_cfg = function(cfg) cfg.craft.include_player_inventory = false end })
  local item_ops = require("core.item_ops")
  local index = get_index(w)
  T.check(not item_ops.consume(index, { { item_key = "Wood", count = 10 } }), "no-op removal must fail")
  T.check(stub.log_contains("consume aborted") or stub.log_contains("did not take effect"),
    "abort is reported")
end)

T.test("container without any remove API fails soft with TODO log", function()
  local w = world({ chest_a_opts = { no_remove = true }, chest_c_opts = { no_remove = true },
    mutate_cfg = function(cfg) cfg.craft.include_player_inventory = false end })
  local item_ops = require("core.item_ops")
  local index = get_index(w)
  T.check(not item_ops.consume(index, { { item_key = "Wood", count = 10 } }), "consume unavailable")
  T.check(stub.log_contains("no working item-remove API"), "TODO(VERIFY) surfaced")
end)

T.test("partial-effect remove API fails the craft safely (never under-consumes)", function()
  -- Remove op silently caps at 2 units per call: the verified-removal check
  -- must notice, and the craft must fail rather than hand out free items.
  local w = world({ chest_a_opts = { remove_cap = 2 }, chest_c_opts = { remove_cap = 2 },
    mutate_cfg = function(cfg) cfg.craft.include_player_inventory = false end })
  local item_ops = require("core.item_ops")
  local index = get_index(w)
  local ok = item_ops.consume(index, { { item_key = "Wood", count = 10 } })
  T.check(not ok, "capped removal must not report success")
  T.check(stub.log_contains("took 2 instead of"), "partial removal detected and logged")
end)

T.test("repeat crafting stays consistent (C4)", function()
  local w = world()
  local base_context = require("core.base_context")
  local storage_index = require("core.storage_index")
  local item_ops = require("core.item_ops")
  local base = base_context.get_base_at_location({ x = 50, y = 0, z = 0 })
  for i = 1, 10 do
    local index = storage_index.get_index(base, w.pawn)
    T.check(item_ops.consume(index, { { item_key = "Wood", count = 5 } }), "craft #" .. i)
  end
  local left = w.chest_a._slots[1]._count + w.chest_c._slots[1]._count + w.player_inv._slots[1]._count
  T.eq(left, 5, "55 - 10*5 = 5 wood left, no double take")
  local index = storage_index.get_index(base, w.pawn)
  T.check(not item_ops.consume(index, { { item_key = "Wood", count = 6 } }), "11th craft fails cleanly")
end)

T.test("include_guild_chest=false filters Guild-classed containers", function()
  stub.reset_modules()
  local guild_chest = fakes.container("Guild", { { "Wood", 40 } })
  local normal_chest = fakes.container("Normal", { { "Wood", 7 } })
  local pawn = fakes.pawn(50, 0)
  stub.install({
    objects = { PlayerController = fakes.controller(pawn) },
    all_objects = {
      PalBaseCampModel = { fakes.base_model(0, 0, 2000) },
      PalMapObjectItemContainerModel = {
        fakes.chest_model(guild_chest, 100, 0, "Class /Script/Pal.PalMapObjectGuildChestModel"),
        fakes.chest_model(normal_chest, 200, 0),
      },
    },
  })
  local cfg = require("config.loader").load()
  cfg.craft.include_guild_chest = false
  cfg.craft.include_player_inventory = false
  require("core.base_context").init(cfg)
  require("core.storage_index").init(cfg)
  require("core.item_ops").init(cfg)
  local base = require("core.base_context").get_base_at_location({ x = 50, y = 0, z = 0 })
  local index = require("core.storage_index").get_index(base, pawn)
  T.eq(require("core.item_ops").count_available(index, "Wood"), 7, "guild chest excluded")
end)

T.test("class-substring exclusion removes containers from discovery", function()
  local w = world({ mutate_cfg = function(cfg)
    cfg.craft.exclude_class_substrings = { "FakeChestModel" }
    cfg.craft.include_player_inventory = false
  end })
  local item_ops = require("core.item_ops")
  local index = get_index(w)
  T.eq(item_ops.count_available(index, "Wood"), 0, "all fake chests excluded by class substring")
end)
