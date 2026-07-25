--[[
  fakes.lua — plain-Lua doubles for the game objects the mod probes.
  They only implement the candidate APIs from config/defaults.lua, so the
  probing adapters exercise the same call shapes they will use in-game.
]]

local M = {}

local function valid(t)
  t.IsValid = function() return true end
  return t
end

function M.vec(x, y, z)
  return { X = x, Y = y, Z = z or 0 }
end

function M.slot(item, count)
  local s = valid({ _item = item, _count = count })
  function s:GetItemId()
    if self._count <= 0 then return "None" end
    return self._item
  end
  function s:GetStackCount() return self._count end
  return s
end

-- Container with container-level RemoveItemAt (verified-decrement path).
function M.container(name, stacks, opts)
  opts = opts or {}
  local c = valid({ _name = name, _slots = {} })
  for _, st in ipairs(stacks) do
    table.insert(c._slots, M.slot(st[1], st[2]))
  end
  function c:GetFullName() return "FakeContainer " .. self._name end
  function c:GetSlotNum() return #self._slots end
  function c:Get(i) return self._slots[i + 1] end -- engine side is 0-based
  if not opts.no_remove then
    function c:RemoveItemAt(slot_index, count)
      local s = self._slots[slot_index + 1]
      if s == nil then return false end
      if opts.remove_is_noop then return true end -- misbehaving API for tests
      if opts.remove_cap then count = math.min(count, opts.remove_cap) end
      s._count = math.max(0, s._count - count)
      return true
    end
  end
  return c
end

-- Chest map-object model wrapping a container, positioned in the world.
function M.chest_model(container, x, y, class_full_name)
  local m = valid({
    Transform = { Translation = M.vec(x, y) },
    _container = container,
  })
  function m:GetItemContainer() return self._container end
  function m:GetClass()
    local cls = { GetFullName = function() return class_full_name or "Class /Script/Pal.FakeChestModel" end }
    return cls
  end
  function m:GetFullName() return "FakeChestModel " .. (self._container._name or "?") end
  return m
end

function M.base_model(x, y, range)
  local b = valid({
    AreaRange = range or 2000.0,
    Transform = { Translation = M.vec(x, y) },
  })
  function b:GetFullName() return string.format("FakeBase(%d,%d)", x, y) end
  return b
end

function M.pawn(x, y, inventory_container)
  local p = valid({ _loc = M.vec(x, y) })
  function p:K2_GetActorLocation() return self._loc end
  if inventory_container then
    local inv = valid({})
    function inv:GetCommonContainer() return inventory_container end
    local ps = valid({})
    function ps:GetInventoryData() return inv end
    function p:GetPlayerState() return ps end
  end
  return p
end

function M.controller(pawn)
  local pc = valid({})
  function pc:K2_GetPawn() return pawn end
  return pc
end

-- Fake TArray-of-cost-struct param as seen by hooks: ForEach + wrapped elems.
function M.cost_array(costs) -- costs: { {"Wood", 5}, ... }
  local arr = {}
  function arr:ForEach(fn)
    for i, c in ipairs(costs) do
      local elem = { get = function() return { ItemId = c[1], Num = c[2] } end }
      fn(i, elem)
    end
  end
  return arr
end

function M.bool_param(v)
  return { get = function() return v end }
end

return M
