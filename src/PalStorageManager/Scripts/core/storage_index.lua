--[[
  core/storage_index.lua — discover base containers and index their stacks.

  Index shape: { base_id, built_at, by_item = { [item_key] = { loc, ... } } }
  loc = { container, slot_index, item_key, count, source ("player"|"storage"),
          container_key }

  Discovery walks CONFIG.api.craft.container_model_classes via FindAllOf and
  keeps only containers whose owning map object sits inside the current base
  (scope = current_base guarantee). Everything is probed and fails soft.
]]

local log = require("util.log")
local ue = require("util.ue")
local throttle = require("util.throttle")
local base_context = require("core.base_context")

local M = {
  cfg = nil,
  _cached = nil,
}

function M.init(cfg)
  M.cfg = cfg
end

-- Normalize an item identity (FPalItemId-ish struct, FName, or string) to a
-- stable string key. TODO(VERIFY): FPalItemId field layout on 1.0.
function M.item_key(raw_id)
  if raw_id == nil then return nil end
  if type(raw_id) == "string" then return raw_id end
  local ok, s = pcall(function() return raw_id.StaticId:ToString() end)
  if ok and type(s) == "string" and s ~= "" then return s end
  local ok2, s2 = pcall(function() return raw_id:ToString() end)
  if ok2 and type(s2) == "string" and s2 ~= "" then return s2 end
  local ok3, s3 = pcall(tostring, raw_id)
  if ok3 and s3 ~= "" then return s3 end
  return nil
end

local function matches_any(name, substrings)
  for _, sub in ipairs(substrings or {}) do
    if sub ~= "" and string.find(name, sub, 1, true) then return true end
  end
  return false
end

local function model_location(model)
  local api = M.cfg.api.craft
  local _n, tf = ue.probe_get(model, api.container_transform_properties)
  if tf == nil then
    _n, tf = ue.probe_call(model, api.container_transform_getters)
  end
  if tf == nil then return nil end
  return ue.to_xyz(ue.try_get(tf, "Translation")) or ue.to_xyz(tf)
end

local function container_of(model)
  local api = M.cfg.api.craft
  local _n, container = ue.probe_call(model, api.container_getters)
  if container == nil then
    _n, container = ue.probe_get(model, api.container_properties)
  end
  return container
end

local function discover_storage_containers(base, out, seen)
  local api = M.cfg.api.craft
  local base_loc = base_context.base_location(base)
  local radius = base_context.base_radius(base) * (M.cfg.weight.base_radius_margin or 1.0)

  for _, class_name in ipairs(api.container_model_classes) do
    local models = ue.find_all_of(class_name)
    if models == nil then
      log.once("no-container-class-" .. class_name, "debug",
        "TODO(VERIFY): no instances of container model class %q found", class_name)
    else
      for _, model in ipairs(models) do
        local cls = ue.is_valid(model) and ue.class_name(model) or nil
        -- include_guild_chest=false filters guild-chest-like classes.
        -- TODO(VERIFY): exact guild chest model class name on 1.0.
        local guild_excluded = cls ~= nil
          and not M.cfg.craft.include_guild_chest
          and string.find(cls, "Guild", 1, true) ~= nil
        if cls ~= nil
          and not guild_excluded
          and not matches_any(cls, M.cfg.craft.exclude_class_substrings) then
          local container = container_of(model)
          if container ~= nil then
            local in_base = false
            local loc = model_location(model)
            if loc ~= nil and base_loc ~= nil then
              in_base = ue.dist2d(loc, base_loc) <= radius
            elseif M.cfg.craft.include_unlocatable_containers then
              in_base = true
              log.once("unlocatable-container", "warn",
                "including container with unreadable position (include_unlocatable_containers=true)")
            end
            local key = ue.object_key(container)
            if in_base and not seen[key] then
              seen[key] = true
              table.insert(out, { container = container, source = "storage", key = key })
            end
          end
        end
      end
    end
  end
end

local function discover_player_containers(pawn, out, seen)
  local api = M.cfg.api.craft
  local _n, ps = ue.probe_call(pawn, M.cfg.api.base.player_state_getters)
  if not ue.is_valid(ps) then ps = ue.try_get(pawn, "PlayerState") end

  local inv = nil
  for _, holder in ipairs({ ps, pawn }) do
    if holder ~= nil then
      local _g, data = ue.probe_call(holder, api.inventory_data_getters)
      if data == nil then _g, data = ue.probe_get(holder, api.inventory_data_properties) end
      if data ~= nil then inv = data break end
    end
  end
  if inv == nil then
    log.once("no-player-inventory", "warn",
      "TODO(VERIFY): player inventory data unresolved; craft pool excludes player inventory")
    return
  end

  local _n2, container = ue.probe_call(inv, api.player_container_getters)
  if container == nil then
    _n2, container = ue.probe_get(inv, api.player_container_properties)
  end
  if container == nil then
    log.once("no-player-container", "warn",
      "TODO(VERIFY): player item container unresolved on inventory data (%s)", ue.class_name(inv))
    return
  end

  local key = ue.object_key(container)
  if not seen[key] then
    seen[key] = true
    table.insert(out, { container = container, source = "player", key = key })
  end
end

function M.discover_containers(base, pawn)
  local out, seen = {}, {}
  if M.cfg.craft.include_storage_containers then
    discover_storage_containers(base, out, seen)
  end
  if M.cfg.craft.include_player_inventory and pawn ~= nil then
    discover_player_containers(pawn, out, seen)
  end
  return out
end

function M.read_slot(container, slot_index)
  local api = M.cfg.api.craft
  local _n, slot = ue.probe_call(container, api.slot_getters, slot_index)
  if slot == nil then return nil end

  local _i, raw_id = ue.probe_call(slot, api.slot_item_id_getters)
  if raw_id == nil then _i, raw_id = ue.probe_get(slot, api.slot_item_id_properties) end
  local key = M.item_key(raw_id)
  if key == nil or key == "None" or key == "" then return nil end

  local _c, count = ue.probe_call(slot, api.slot_stack_getters)
  if count == nil then _c, count = ue.probe_get(slot, api.slot_stack_properties) end
  if type(count) ~= "number" or count <= 0 then return nil end

  return { slot = slot, item_key = key, count = count }
end

local function slot_count_of(container)
  local api = M.cfg.api.craft
  local _n, num = ue.probe_call(container, api.slot_num_getters)
  if type(num) ~= "number" or num < 0 then return 0 end
  return num
end

function M.build_index(base, pawn)
  local index = {
    base_id = base_context.base_id(base),
    built_at = throttle.now(),
    by_item = {},
    container_count = 0,
  }

  local entries = M.discover_containers(base, pawn)
  index.container_count = #entries

  for _, entry in ipairs(entries) do
    local n = slot_count_of(entry.container)
    for slot_index = 0, n - 1 do
      local slot = M.read_slot(entry.container, slot_index)
      if slot ~= nil then
        local loc = {
          container = entry.container,
          container_key = entry.key,
          slot_index = slot_index,
          item_key = slot.item_key,
          count = slot.count,
          source = entry.source,
        }
        local list = index.by_item[slot.item_key]
        if list == nil then
          list = {}
          index.by_item[slot.item_key] = list
        end
        table.insert(list, loc)
      end
    end
  end

  -- Deterministic consume order: configured source preference, then
  -- container identity, then slot index (spec §6.4).
  local player_first = (M.cfg.craft.prefer_consume_order ~= "storage_first")
  for _, list in pairs(index.by_item) do
    table.sort(list, function(a, b)
      if a.source ~= b.source then
        if player_first then return a.source == "player" end
        return a.source == "storage"
      end
      if a.container_key ~= b.container_key then
        return a.container_key < b.container_key
      end
      return a.slot_index < b.slot_index
    end)
  end

  return index
end

function M.invalidate()
  M._cached = nil
end

function M.get_index(base, pawn)
  if M._cached ~= nil
    and M._cached.base_id == base_context.base_id(base)
    and not throttle.expired(M._cached.built_at, M.cfg.craft.refresh_interval_sec) then
    return M._cached
  end
  M._cached = M.build_index(base, pawn)
  return M._cached
end

-- Log-only summary (STEP 4): distinct items / stacks / containers.
function M.summarize(index)
  local items, stacks, total = 0, 0, 0
  for _, list in pairs(index.by_item) do
    items = items + 1
    for _, loc in ipairs(list) do
      stacks = stacks + 1
      total = total + loc.count
    end
  end
  return { items = items, stacks = stacks, units = total, containers = index.container_count }
end

return M
