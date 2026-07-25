--[[
  PalStorageManager — UE4SS Lua mod for Palworld 1.0.
  Primary platform: Xbox PC Game Pass / Microsoft Store (WinGDK).

  Entry point: config + logging bootstrap, then feature registration once
  the game world is ready. Every stage is fail-soft: a missing API disables
  the affected feature with a clear [PalStorageManager] log line and never
  crash-loops (CLAUDE.md hard rules 1/3).

  Features (v1):
    F1 unified craft storage  — features/unified_craft.lua + hooks/craft_hooks.lua
    F2 unlimited weight in base — features/weight_in_base.lua + hooks/weight_hooks.lua
]]

local MOD_VERSION = "0.1.0" -- keep in sync with mod.json

local boot_ok, boot_err = pcall(function()
  local log = require("util.log")
  local loader = require("config.loader")
  local ue = require("util.ue")

  local cfg = loader.load()
  log.set_level(cfg.log_level)
  log.info("PalStorageManager v%s bootstrap (Palworld 1.0, Game Pass/WinGDK primary)", MOD_VERSION)

  if not cfg.enabled then
    log.warn("mod disabled via config (enabled=false)")
    return
  end

  local base_context = require("core.base_context")
  local storage_index = require("core.storage_index")
  local item_ops = require("core.item_ops")
  local weight_feature = require("features.weight_in_base")
  local unified_craft = require("features.unified_craft")
  local weight_hooks = require("hooks.weight_hooks")
  local craft_hooks = require("hooks.craft_hooks")
  local apidump = require("util.apidump")

  base_context.init(cfg)
  storage_index.init(cfg)
  item_ops.init(cfg)
  weight_feature.init(cfg)
  unified_craft.init(cfg)

  local registered = false
  local function register_everything()
    if registered then return end
    registered = true

    local ok_w, err_w = pcall(weight_hooks.register, cfg)
    if not ok_w then
      log.error("F2 registration crashed (feature off): %s", tostring(err_w))
    elseif err_w == true then
      log.info("F2 weight-in-base: ON")
    end

    local ok_c, err_c = pcall(craft_hooks.register, cfg)
    if not ok_c then
      log.error("F1 registration crashed (feature off): %s", tostring(err_c))
    elseif err_c == true then
      log.info("F1 unified craft storage: ON")
    end

    pcall(apidump.setup, cfg)
    log.info("init complete")
  end

  -- Wait until a player controller exists before touching game state.
  local polling = ue.loop_async(250, function()
    local ready = ue.get_player_controller() ~= nil
    if ready then
      local ok, err = pcall(register_everything)
      if not ok then
        log.error("init failed: %s", tostring(err))
      end
      return true -- stop loop (LoopAsync stops on true)
    end
    return false -- keep waiting
  end)

  if not polling then
    -- No async loop available (stripped environment / offline test):
    -- register immediately; individual pieces still fail soft.
    log.warn("LoopAsync unavailable; registering hooks immediately")
    register_everything()
  end
end)

if not boot_ok then
  -- Logger may not exist if the bootstrap failed that early.
  print("[PalStorageManager][error] fatal bootstrap error: " .. tostring(boot_err) .. "\n")
end
