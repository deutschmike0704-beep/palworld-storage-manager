--[[
  util/ue.lua — thin fail-soft adapter over UE4SS globals and UObject access.

  Every game-facing access goes through pcall so a missing/renamed API
  degrades to nil / false instead of a hard error (CLAUDE.md fail-soft rule).
  All engine paths used by callers live in CONFIG.api so they can be swapped
  after dump verification without touching feature code.
]]

local M = {}

-- UEHelpers ships with UE4SS under Mods/shared; optional.
M.UEHelpers = nil
do
  local ok, helpers = pcall(require, "UEHelpers")
  if ok and type(helpers) == "table" then M.UEHelpers = helpers end
end

function M.is_valid(obj)
  if obj == nil then return false end
  local ok, valid = pcall(function() return obj:IsValid() end)
  return ok and valid == true
end

function M.find_all_of(short_class_name)
  if type(FindAllOf) ~= "function" then return nil end
  local ok, list = pcall(FindAllOf, short_class_name)
  if not ok then return nil end
  return list
end

function M.find_first_of(short_class_name)
  if type(FindFirstOf) ~= "function" then return nil end
  local ok, obj = pcall(FindFirstOf, short_class_name)
  if not ok then return nil end
  return obj
end

function M.static_find(path)
  if type(StaticFindObject) ~= "function" then return nil end
  local ok, obj = pcall(StaticFindObject, path)
  if not ok or not M.is_valid(obj) then return nil end
  return obj
end

-- Read obj.<name>; nil when missing or inaccessible.
function M.try_get(obj, name)
  if obj == nil then return nil end
  local ok, value = pcall(function() return obj[name] end)
  if not ok then return nil end
  return value
end

-- Call obj:<name>(...) defensively. Returns ok, result.
function M.try_call(obj, name, ...)
  if obj == nil then return false, nil end
  local ok_index, fn = pcall(function() return obj[name] end)
  if not ok_index or fn == nil then return false, nil end
  local args = table.pack(...)
  local ok_call, result = pcall(function()
    return obj[name](obj, table.unpack(args, 1, args.n))
  end)
  if not ok_call then return false, nil end
  return true, result
end

-- First name in `names` whose method call succeeds. Returns name, result.
function M.probe_call(obj, names, ...)
  for _, name in ipairs(names or {}) do
    local ok, result = M.try_call(obj, name, ...)
    if ok then return name, result end
  end
  return nil, nil
end

-- First name in `names` whose property read yields non-nil. Returns name, value.
function M.probe_get(obj, names)
  for _, name in ipairs(names or {}) do
    local v = M.try_get(obj, name)
    if v ~= nil then return name, v end
  end
  return nil, nil
end

function M.register_hook(path, callback)
  if type(RegisterHook) ~= "function" then
    return false, "RegisterHook unavailable"
  end
  local ok, err = pcall(RegisterHook, path, callback)
  if not ok then return false, tostring(err) end
  return true, nil
end

function M.notify_new(class_path, callback)
  if type(NotifyOnNewObject) ~= "function" then return false end
  local ok = pcall(NotifyOnNewObject, class_path, callback)
  return ok == true
end

-- NOTE: UE4SS LoopAsync STOPS the loop when the callback returns true
-- (the design pseudocode had this inverted — verified against UE4SS docs).
function M.loop_async(interval_ms, callback)
  if type(LoopAsync) ~= "function" then return false end
  local ok = pcall(LoopAsync, math.floor(interval_ms), callback)
  return ok == true
end

function M.execute_with_delay(delay_ms, callback)
  if type(ExecuteWithDelay) ~= "function" then return false end
  local ok = pcall(ExecuteWithDelay, math.floor(delay_ms), callback)
  return ok == true
end

function M.register_key_bind(key_name, callback)
  if type(RegisterKeyBind) ~= "function" or type(Key) ~= "table" then
    return false
  end
  local key = Key[key_name]
  if key == nil then return false end
  local ok = pcall(RegisterKeyBind, key, callback)
  return ok == true
end

-- FVector-ish userdata/table -> { x, y, z } numbers, or nil.
function M.to_xyz(v)
  if v == nil then return nil end
  local ok, t = pcall(function() return { x = v.X, y = v.Y, z = v.Z } end)
  if not ok or type(t.x) ~= "number" or type(t.y) ~= "number" then return nil end
  return t
end

function M.dist2d(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

-- FGuid-ish -> stable string key, or nil if unreadable.
function M.guid_str(guid)
  if guid == nil then return nil end
  local ok, s = pcall(function()
    return string.format("%08X-%08X-%08X-%08X", guid.A, guid.B, guid.C, guid.D)
  end)
  if ok then return s end
  local ok2, s2 = pcall(tostring, guid)
  if ok2 then return s2 end
  return nil
end

function M.class_name(obj)
  local ok, name = pcall(function() return obj:GetClass():GetFullName() end)
  if ok and type(name) == "string" then return name end
  return "<unknown-class>"
end

-- Stable identity string for dedup/sorting (UObject full name).
function M.object_key(obj)
  local ok, name = pcall(function() return obj:GetFullName() end)
  if ok and type(name) == "string" then return name end
  local ok2, s = pcall(tostring, obj)
  if ok2 then return s end
  return "<unknown-object>"
end

function M.get_player_controller()
  if M.UEHelpers then
    local ok, pc = pcall(function() return M.UEHelpers.GetPlayerController() end)
    if ok and M.is_valid(pc) then return pc end
  end
  local pc = M.find_first_of("PlayerController")
  if M.is_valid(pc) then return pc end
  return nil
end

function M.get_player_pawn()
  local pc = M.get_player_controller()
  if pc then
    local ok, pawn = M.try_call(pc, "K2_GetPawn")
    if ok and M.is_valid(pawn) then return pawn end
    local p = M.try_get(pc, "Pawn")
    if M.is_valid(p) then return p end
  end
  -- Community-verified fallback: the local player pawn class is PalPlayerCharacter.
  local pawn = M.find_first_of("PalPlayerCharacter")
  if M.is_valid(pawn) then return pawn end
  return nil
end

return M
