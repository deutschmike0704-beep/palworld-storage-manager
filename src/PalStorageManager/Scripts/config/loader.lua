--[[
  config/loader.lua — merges user overrides over shipped defaults.

  Override sources, first hit wins:
    1) Scripts/config/user.lua                       (require-able module)
    2) <mod root>/config/config.lua                  (loaded relative to the
       game CWD, which is the binaries dir: Pal/Binaries/WinGDK on Game Pass)
]]

local log = require("util.log")
local defaults = require("config.defaults")

local M = {}

-- Arrays (list-like tables) are replaced wholesale; maps merge recursively.
local function is_list(t)
  return type(t) == "table" and (t[1] ~= nil or next(t) == nil)
end

local function deep_merge(base, override)
  local out = {}
  for k, v in pairs(base) do
    if type(v) == "table" then
      out[k] = deep_merge(v, {})
    else
      out[k] = v
    end
  end
  for k, v in pairs(override or {}) do
    if type(v) == "table" and type(out[k]) == "table" and not is_list(v) then
      out[k] = deep_merge(out[k], v)
    else
      out[k] = v
    end
  end
  return out
end

local function load_user_overrides()
  local ok, user = pcall(require, "config.user")
  if ok and type(user) == "table" then
    log.info("user config loaded from Scripts/config/user.lua")
    return user
  end

  -- Relative to game CWD. Both known UE4SS layouts on Game Pass (WinGDK):
  local candidates = {
    "ue4ss/Mods/PalStorageManager/config/config.lua",
    "Mods/PalStorageManager/config/config.lua",
  }
  for _, path in ipairs(candidates) do
    local chunk = loadfile(path)
    if chunk then
      local ok_run, cfg = pcall(chunk)
      if ok_run and type(cfg) == "table" then
        log.info("user config loaded from %s", path)
        return cfg
      end
      log.warn("user config at %s failed to execute; ignoring it", path)
    end
  end
  return nil
end

local function sanitize(cfg)
  local levels = { debug = true, info = true, warn = true, error = true }
  if not levels[cfg.log_level] then
    log.warn("invalid log_level %q; falling back to 'info'", tostring(cfg.log_level))
    cfg.log_level = "info"
  end
  if type(cfg.weight.infinite_max_weight) ~= "number" or cfg.weight.infinite_max_weight <= 0 then
    cfg.weight.infinite_max_weight = 1000000
  end
  if type(cfg.weight.poll_interval_sec) ~= "number" or cfg.weight.poll_interval_sec < 0.05 then
    cfg.weight.poll_interval_sec = 0.25
  end
  if type(cfg.craft.refresh_interval_sec) ~= "number" or cfg.craft.refresh_interval_sec < 0.1 then
    cfg.craft.refresh_interval_sec = 0.5
  end
  if cfg.craft.scope ~= "current_base" then
    -- "all_guild_bases" is a prepared config value only; v1 implements
    -- current_base and refuses to silently widen the scope.
    log.warn("craft.scope %q not supported in v1; using 'current_base'", tostring(cfg.craft.scope))
    cfg.craft.scope = "current_base"
  end
  if cfg.craft.consume_mode ~= "vanilla_fallback" and cfg.craft.consume_mode ~= "replace" then
    log.warn("invalid craft.consume_mode %q; using 'vanilla_fallback'", tostring(cfg.craft.consume_mode))
    cfg.craft.consume_mode = "vanilla_fallback"
  end
  return cfg
end

function M.load()
  local overrides = load_user_overrides()
  local cfg = deep_merge(defaults, overrides or {})
  return sanitize(cfg)
end

return M
