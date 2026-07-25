--[[
  core/item_ops.lua — count / afford / consume over a StorageIndex.

  Counting re-reads slots live (never trusts the snapshot) and verifies the
  slot still holds the same item. Consume:
    1) live pre-check across all costs (atomic-ish),
    2) deterministic removal in index order,
    3) removal verified by re-reading the slot count afterwards,
    4) best-effort refund of already-taken stacks on mid-way failure,
    5) index invalidated in every exit path.

  Removal APIs are probed from CONFIG.api.craft.*_remove_ops; if none work
  the consume fails BEFORE anything is taken (probe happens on first take
  and pre-check failure paths take nothing).
]]

local log = require("util.log")
local ue = require("util.ue")
local storage_index = require("core.storage_index")

local M = {
  cfg = nil,
}

function M.init(cfg)
  M.cfg = cfg
end

-- Live count of loc's slot IF it still holds the same item, else 0.
local function live_count(loc)
  local slot = storage_index.read_slot(loc.container, loc.slot_index)
  if slot == nil or slot.item_key ~= loc.item_key then return 0 end
  return slot.count
end

function M.count_available(index, item_key)
  local total = 0
  for _, loc in ipairs(index.by_item[item_key] or {}) do
    total = total + live_count(loc)
  end
  return total
end

-- costs: list of { item_key, count }
function M.can_afford(index, costs)
  for _, c in ipairs(costs) do
    if M.count_available(index, c.item_key) < c.count then
      return false, c.item_key
    end
  end
  return true, nil
end

-- Remove `take` units from loc. Returns the number of units VERIFIED as
-- removed (by re-reading the slot afterwards); 0 means nothing happened.
local function remove_from(loc, take)
  local api = M.cfg.api.craft
  local before = live_count(loc)
  if before < take then return 0 end

  local attempted = false
  local name = ue.probe_call(loc.container, api.container_remove_ops, loc.slot_index, take)
  if name ~= nil then
    attempted = true
  else
    local slot = storage_index.read_slot(loc.container, loc.slot_index)
    if slot ~= nil then
      name = ue.probe_call(slot.slot, api.slot_remove_ops, take)
      attempted = name ~= nil
    end
  end

  if not attempted and M.cfg.craft.allow_property_write_consume then
    -- Last resort, off by default: direct StackCount write. Only safe for
    -- partial takes; clearing a whole slot needs the real remove API.
    local slot = storage_index.read_slot(loc.container, loc.slot_index)
    if slot ~= nil and take < slot.count then
      local ok = pcall(function() slot.slot.StackCount = slot.count - take end)
      attempted = ok
      name = ok and "<StackCount write>" or nil
    end
  end

  if not attempted then
    log.once("no-remove-op", "error",
      "TODO(VERIFY): no working item-remove API among configured candidates; consume unavailable")
    return 0
  end

  local after = live_count(loc)
  local removed = before - after
  if removed ~= take then
    log.warn("remove op %s took %d instead of %d (before=%d after=%d)",
      tostring(name), removed, take, before, after)
  end
  if removed < 0 then return 0 end
  return removed
end

-- Best-effort rollback: try to put taken stacks back.
local function refund(taken)
  if #taken == 0 then return end
  local api = M.cfg.api.craft
  local refunded = 0
  for _, t in ipairs(taken) do
    local name = ue.probe_call(t.loc.container, api.container_add_ops, t.loc.item_key, t.take)
    if name ~= nil then refunded = refunded + 1 end
  end
  if refunded < #taken then
    log.error("consume rollback incomplete: refunded %d/%d stacks — item loss possible, see log above",
      refunded, #taken)
  else
    log.warn("consume rolled back (%d stacks refunded)", #taken)
  end
end

-- Consume costs across the index. Returns true on full success. Never
-- partially succeeds silently: mid-way failure triggers refund + false.
function M.consume(index, costs)
  local ok, missing = M.can_afford(index, costs)
  if not ok then
    log.info("consume pre-check failed: not enough %s in unified pool", tostring(missing))
    storage_index.invalidate()
    return false
  end

  local taken = {}

  for _, c in ipairs(costs) do
    local remaining = c.count
    for _, loc in ipairs(index.by_item[c.item_key] or {}) do
      if remaining <= 0 then break end
      local avail = live_count(loc)
      local take = math.min(avail, remaining)
      if take > 0 then
        local removed = remove_from(loc, take)
        if removed <= 0 then
          log.error("consume aborted: removal failed at container=%s slot=%d item=%s",
            loc.container_key, loc.slot_index, loc.item_key)
          refund(taken)
          storage_index.invalidate()
          return false
        end
        table.insert(taken, { loc = loc, take = removed })
        remaining = remaining - removed
      end
    end
    if remaining > 0 then
      log.error("consume incomplete after pre-check: %s short by %d (race?)", c.item_key, remaining)
      refund(taken)
      storage_index.invalidate()
      return false
    end
  end

  storage_index.invalidate()
  return true
end

return M
