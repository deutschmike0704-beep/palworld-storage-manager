--[[
  hooks/craft_hooks.lua — F1 wiring (count + consume).

  HARD GATE (CLAUDE.md rule 1/2): both hook paths are nil in the shipped
  defaults because no Palworld 1.0 craft hook path is publicly verified.
  F1 therefore soft-disables at startup with an explicit TODO(VERIFY) log.
  Workflow to enable: run the API dump (debug.dump_key), identify the
  count/consume functions in the dump output or a CXXHeaderDump, put the
  paths into user config (api.craft.count_hook / consume_hook), retest.

  Double-consume prevention (CLAUDE.md rule 2, spec §6.6):
  UE4SS Lua hooks run AFTER the original function, so we cannot stop
  vanilla from executing. Two modes, chosen via craft.consume_mode:

  * "vanilla_fallback" (default, structurally safe):
      - If vanilla's consume SUCCEEDED, we do nothing — vanilla paid from
        its own reachable containers; we never touch items. No double take.
      - If vanilla's consume FAILED (materials not reachable for vanilla)
        and the unified pool can pay, WE consume and override the hook's
        return value to success. Exactly one consumer ever runs.
      - Requires the hook's vanilla result to be readable from the last
        callback parameter; if it isn't, we log once and never consume.
  * "replace": assumes the verified hook point is one where returning a
      value fully replaces the vanilla effect (e.g. a pure BP branch).
      Only for setups verified in-game; consumes on every call.
]]

local log = require("util.log")
local ue = require("util.ue")
local unified_craft = require("features.unified_craft")
local storage_index = require("core.storage_index")

local M = {}

-- Read a RemoteUnrealParam-ish value defensively.
local function param_value(param)
  if param == nil then return nil end
  local ok, v = pcall(function() return param:get() end)
  if ok then return v end
  return param
end

-- Map the count-hook's item parameter to our normalized item key.
function M.item_key_from_param(param)
  return storage_index.item_key(param_value(param))
end

-- Parse the consume-hook's cost parameter into { {item_key, count}, ... }.
-- TODO(VERIFY): the real parameter layout of the verified consume hook.
-- Supports: TArray-of-struct with (ItemId|StaticId, Num|Count) fields.
function M.parse_costs(param)
  local raw = param_value(param)
  if raw == nil then return nil end
  local costs = {}
  local ok = pcall(function()
    raw:ForEach(function(_, elem)
      local e = elem
      local ok_get, inner = pcall(function() return elem:get() end)
      if ok_get and inner ~= nil then e = inner end
      local id = nil
      pcall(function() id = e.ItemId end)
      if id == nil then pcall(function() id = e.StaticId end) end
      local n = nil
      pcall(function() n = e.Num end)
      if n == nil then pcall(function() n = e.Count end) end
      local key = storage_index.item_key(id)
      if key ~= nil and type(n) == "number" and n > 0 then
        table.insert(costs, { item_key = key, count = n })
      end
    end)
  end)
  if not ok or #costs == 0 then return nil end
  return costs
end

local function on_count_hook(_self, item_param)
  local key = M.item_key_from_param(item_param)
  if key == nil then return nil end
  local unified = unified_craft.query_available(key)
  if unified == nil then return nil end -- no base context: leave vanilla count
  -- The unified pool is a superset of whatever vanilla counted, so
  -- returning it directly can only raise availability, never lower it.
  return unified
end

local function on_consume_hook(cfg, params)
  local costs = M.parse_costs(params[1])
  if costs == nil then
    log.once("consume-parse-failed", "warn",
      "F1: cannot parse consume-hook costs — unified consume inactive. TODO(VERIFY) parameter layout.")
    return nil
  end

  if cfg.craft.consume_mode == "replace" then
    local ok = unified_craft.try_consume(costs)
    return ok
  end

  -- vanilla_fallback: last parameter should be the vanilla result.
  local vanilla_result = param_value(params[#params])
  if type(vanilla_result) ~= "boolean" then
    log.once("consume-result-unreadable", "warn",
      "F1: vanilla consume result not readable from hook params — unified consume stays inactive " ..
      "(safe mode, no double-consume possible). TODO(VERIFY) hook signature.")
    return nil
  end

  if vanilla_result == true then
    -- Vanilla paid from its own containers; touching anything now would
    -- double-consume. Refresh our view and stand down.
    storage_index.invalidate()
    return nil
  end

  -- Vanilla failed -> the unified pool gets its turn.
  local ok = unified_craft.try_consume(costs)
  if ok then
    log.debug("F1: unified pool paid a craft vanilla could not")
    return true -- override the failed vanilla result
  end
  return nil -- keep vanilla's failure (insufficient materials overall)
end

function M.register(cfg)
  if not cfg.craft.enabled then
    log.info("F1 unified craft storage: disabled by config")
    return false
  end

  local count_path = cfg.api.craft.count_hook
  local consume_path = cfg.api.craft.consume_hook

  local missing = {}
  if count_path == nil then table.insert(missing, "api.craft.count_hook") end
  if consume_path == nil then table.insert(missing, "api.craft.consume_hook") end
  if #missing > 0 then
    log.warn("F1 unified craft storage SOFT-DISABLED: unverified hook paths (%s).", table.concat(missing, ", "))
    log.warn("TODO(VERIFY): run the API dump (key %s / debug.dump_apis_on_init) and follow " ..
      "research/notes/verified-hooks.md to fill the craft hook paths.", tostring(cfg.debug.dump_key))
    if cfg.debug.log_index_summary then
      unified_craft.start_log_only()
    end
    return false
  end

  -- F1 needs BOTH count and consume (CLAUDE.md rule 2): register consume
  -- first so a count-only half-activation can never happen.
  local ok_consume, err_consume = ue.register_hook(consume_path, function(self, ...)
    local params = table.pack(...)
    local ok_cb, override = pcall(on_consume_hook, cfg, params)
    if not ok_cb then
      log.once("consume-hook-error", "error", "F1 consume hook failed: %s", tostring(override))
      return nil
    end
    if override ~= nil then return override end
  end)
  if not ok_consume then
    log.error("F1 DISABLED: consume hook %s did not register (%s)", consume_path, tostring(err_consume))
    return false
  end

  local ok_count, err_count = ue.register_hook(count_path, function(self, item_param)
    local ok_cb, override = pcall(on_count_hook, self, item_param)
    if not ok_cb then
      log.once("count-hook-error", "error", "F1 count hook failed: %s", tostring(override))
      return nil
    end
    if override ~= nil then return override end
  end)
  if not ok_count then
    -- Count without consume is unsafe; consume without count is merely
    -- invisible. Still treat as failure: report and bail.
    log.error("F1 DISABLED: count hook %s did not register (%s) — consume hook stays passive " ..
      "(it only ever acts when vanilla already failed)", count_path, tostring(err_count))
    return false
  end

  if cfg.api.craft.workbench_open_hook ~= nil then
    local ok_ui = ue.register_hook(cfg.api.craft.workbench_open_hook, function(self)
      pcall(function() unified_craft.on_workbench_opened(param_value(self)) end)
    end)
    if not ok_ui then
      log.debug("optional workbench-open hook not registered; falling back to player-position base context")
    end
  end

  log.info("F1 unified craft storage ACTIVE (count=%s, consume=%s, mode=%s)",
    count_path, consume_path, cfg.craft.consume_mode)
  return true
end

return M
