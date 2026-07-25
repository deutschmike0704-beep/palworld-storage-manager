--[[
  util/log.lua — leveled logger.
  Output goes through print(), which UE4SS mirrors to the console and UE4SS.log.
  Convention (CLAUDE.md): [PalStorageManager][level] message
]]

local LEVELS = { debug = 10, info = 20, warn = 30, error = 40 }

local M = {
  prefix = "[PalStorageManager]",
  level = LEVELS.info,
  _once = {},
}

function M.set_level(name)
  M.level = LEVELS[name] or LEVELS.info
end

local function emit(level_name, fmt, ...)
  local level = LEVELS[level_name]
  if not level or level < M.level then return end
  local msg
  if select("#", ...) > 0 then
    local ok, formatted = pcall(string.format, fmt, ...)
    msg = ok and formatted or tostring(fmt)
  else
    msg = tostring(fmt)
  end
  print(string.format("%s[%s] %s\n", M.prefix, level_name, msg))
end

function M.debug(fmt, ...) emit("debug", fmt, ...) end
function M.info(fmt, ...)  emit("info", fmt, ...)  end
function M.warn(fmt, ...)  emit("warn", fmt, ...)  end
function M.error(fmt, ...) emit("error", fmt, ...) end

-- Log a message at most once per key. Use inside poll loops / hooks so a
-- missing API degrades to a single line instead of per-tick spam.
function M.once(key, level_name, fmt, ...)
  if M._once[key] then return end
  M._once[key] = true
  emit(level_name, fmt, ...)
end

-- Test/support helper: forget "once" keys (e.g. after config reload).
function M.reset_once()
  M._once = {}
end

return M
