--[[
  features/unified_craft.lua — F1 orchestration: unified count + consume over
  all storage containers of the current base (+ player inventory per config).

  The craft hooks (hooks/craft_hooks.lua) call into:
    query_available(item_key)  -> unified count or nil (no base context)
    try_consume(costs)         -> true only if the unified pool fully paid
  plus workbench open/close context if the optional UI hook resolves.

  Also hosts the STEP 4 log-only mode (debug.log_index_summary): periodic
  index summaries so container discovery can be verified in-game before any
  craft hook goes live.
]]

local log = require("util.log")
local ue = require("util.ue")
local base_context = require("core.base_context")
local storage_index = require("core.storage_index")
local item_ops = require("core.item_ops")

local M = {
  cfg = nil,
  active_workbench = nil,
}

function M.init(cfg)
  M.cfg = cfg
end

function M.on_workbench_opened(workbench)
  M.active_workbench = workbench
  local pawn = base_context.get_player_pawn()
  local base = base_context.get_craft_context_base(workbench, pawn)
  if base ~= nil then
    storage_index.get_index(base, pawn) -- warm the cache
    log.debug("F1: craft context base=%s", base_context.base_id(base))
  end
end

function M.on_workbench_closed()
  M.active_workbench = nil
  storage_index.invalidate()
end

local function context_index()
  local pawn = base_context.get_player_pawn()
  if pawn == nil then return nil end
  local base = base_context.get_craft_context_base(M.active_workbench, pawn)
  if base == nil then return nil end
  return storage_index.get_index(base, pawn)
end

-- Unified availability. nil => caller must leave vanilla behavior untouched.
function M.query_available(item_key)
  if not M.cfg.craft.enabled then return nil end
  local index = context_index()
  if index == nil then return nil end
  return item_ops.count_available(index, item_key)
end

-- costs: list of { item_key, count }. True only when fully paid from the
-- unified pool. False leaves game state untouched (modulo verified rollback).
function M.try_consume(costs)
  if not M.cfg.craft.enabled then return false end
  if costs == nil or #costs == 0 then return false end
  local index = context_index()
  if index == nil then
    log.debug("F1: no base context for consume; leaving vanilla behavior")
    return false
  end
  return item_ops.consume(index, costs)
end

-- STEP 4 log-only mode: periodically log what the unified pool sees.
function M.start_log_only()
  local interval = (M.cfg.debug.index_summary_interval_sec or 5.0) * 1000
  local started = ue.loop_async(interval, function()
    if not M.cfg.debug.log_index_summary then return true end -- stop loop
    local ok, err = pcall(function()
      local index = context_index()
      if index == nil then
        log.debug("F1[log-only]: no base context (player outside any own base?)")
        return
      end
      local s = storage_index.summarize(index)
      log.info("F1[log-only]: unified pool = %d item type(s), %d stack(s), %d unit(s) across %d container(s)",
        s.items, s.stacks, s.units, s.containers)
    end)
    if not ok then
      log.once("log-only-error", "error", "F1 log-only tick failed: %s", tostring(err))
    end
    return false -- keep looping (LoopAsync stops on true)
  end)
  if started then
    log.info("F1: log-only index summary active (every %.1fs)", interval / 1000)
  end
end

return M
