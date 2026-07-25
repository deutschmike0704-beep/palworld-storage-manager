--[[
  hooks/weight_hooks.lua — F2 wiring.

  Strategy: register a return-value override hook on the game's max-weight
  query (candidates in CONFIG.api.weight.max_weight_hooks). UE4SS hooks run
  after the original function; returning a value from the callback replaces
  the return value (pwmodding.wiki, hooking-functions). While the player is
  outside their base the callback returns nothing, so vanilla wins — that IS
  the restore path, no state to write back.

  A poll loop (LoopAsync) drives the inside/outside state so the hook
  callback itself stays cheap (reads a cached boolean).

  Multiplayer caveat: the hook fires for every player's inventory data, but
  the inside-base state tracks the LOCAL player only. Correct for the
  primary target (Game Pass client, SP/local coop). TODO(VERIFY): per-player
  state before recommending this on shared servers.
]]

local log = require("util.log")
local ue = require("util.ue")
local weight_feature = require("features.weight_in_base")

local M = {}

function M.register(cfg)
  if not cfg.weight.enabled then
    log.info("F2 weight-in-base: disabled by config")
    return false
  end

  local hooked_path = nil
  for _, path in ipairs(cfg.api.weight.max_weight_hooks) do
    local ok, err = ue.register_hook(path, function()
      local ok_cb, override = pcall(weight_feature.max_weight_override)
      if ok_cb and override ~= nil then
        return override
      end
    end)
    if ok then
      hooked_path = path
      break
    end
    log.debug("weight hook candidate rejected: %s (%s)", path, tostring(err))
  end

  if hooked_path == nil then
    log.error("F2 weight-in-base DISABLED: no max-weight hook resolved. " ..
      "TODO(VERIFY): confirm the 1.0 path (candidate: /Script/Pal.PalPlayerInventoryData:GetMaxInventoryWeight) " ..
      "via research/notes/verified-hooks.md workflow, then set api.weight.max_weight_hooks in user config.")
    return false
  end

  weight_feature.set_hook_available(true)
  log.info("F2 weight hook active: %s", hooked_path)

  local looping = ue.loop_async(cfg.weight.poll_interval_sec * 1000, function()
    if not cfg.weight.enabled then return true end -- stop loop
    local ok, err = pcall(weight_feature.update)
    if not ok then
      log.once("weight-update-error", "error", "F2 poll tick failed: %s", tostring(err))
    end
    return false -- keep looping (LoopAsync stops on true)
  end)

  if not looping then
    -- Without the poll the inside-state never updates; the hook would then
    -- never override (fails closed, i.e. vanilla behavior — no cheat leak).
    log.error("F2: LoopAsync unavailable — inside-base state cannot update; feature effectively off")
    weight_feature.set_hook_available(false)
    return false
  end

  return true
end

return M
