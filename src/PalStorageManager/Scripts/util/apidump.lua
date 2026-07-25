--[[
  util/apidump.lua — in-game API discovery dump (STEP 3 helper).

  Purpose: generate the evidence needed to promote TODO(VERIFY) candidates
  into verified paths WITHOUT guessing. Trigger via debug.dump_key (default
  F6) or debug.dump_apis_on_init; output lands in the UE4SS console/log with
  the normal [PalStorageManager] prefix — copy it into
  research/notes/verified-hooks.md.

  Dumps, all keyword-filtered to stay readable:
    * player pawn / player state / inventory-data members  (Weight, Inventory, Group)
    * base camp models: class, AreaRange, transform/guid probe results
    * map-object model classes present in the world + members matching
      Container/Craft/Convert/Material/Product/Ingredient
]]

local log = require("util.log")
local ue = require("util.ue")

local M = { cfg = nil }

local function contains_any(name, keywords)
  local lower = string.lower(name)
  for _, kw in ipairs(keywords) do
    if string.find(lower, string.lower(kw), 1, true) then return true end
  end
  return false
end

-- Collect "fn Name" / "prop Name" strings across the class hierarchy.
local function member_names(obj)
  local names = {}
  pcall(function()
    local cls = obj:GetClass()
    local depth = 0
    while cls ~= nil and depth < 12 do
      pcall(function()
        cls:ForEachFunction(function(fn)
          pcall(function() table.insert(names, "fn   " .. fn:GetName()) end)
        end)
      end)
      pcall(function()
        cls:ForEachProperty(function(prop)
          pcall(function() table.insert(names, "prop " .. prop:GetName()) end)
        end)
      end)
      local ok, super = pcall(function() return cls:GetSuperStruct() end)
      cls = ok and super or nil
      depth = depth + 1
    end
  end)
  return names
end

local function dump_members(label, obj, keywords)
  if obj == nil then
    log.info("DUMP %s: <unresolved>", label)
    return
  end
  log.info("DUMP %s: class=%s", label, ue.class_name(obj))
  local names = member_names(obj)
  local shown = 0
  for _, n in ipairs(names) do
    if contains_any(n, keywords) then
      log.info("DUMP   %s", n)
      shown = shown + 1
    end
  end
  log.info("DUMP %s: %d/%d members matched %s", label, shown, #names, table.concat(keywords, "|"))
end

local function dump_player()
  local pawn = ue.get_player_pawn()
  if pawn == nil then
    log.info("DUMP player: no pawn (not in-world yet?)")
    return
  end
  dump_members("player-pawn", pawn, { "weight", "inventory", "base", "craft" })

  local _n, ps = ue.probe_call(pawn, M.cfg.api.base.player_state_getters)
  if not ue.is_valid(ps) then ps = ue.try_get(pawn, "PlayerState") end
  dump_members("player-state", ps, { "weight", "inventory", "group", "guild" })

  if ps ~= nil then
    local _g, inv = ue.probe_call(ps, M.cfg.api.craft.inventory_data_getters)
    if inv == nil then _g, inv = ue.probe_get(ps, M.cfg.api.craft.inventory_data_properties) end
    dump_members("inventory-data", inv, { "weight", "container", "inventor" })
  end
end

local function dump_bases()
  local found = ue.find_all_of(M.cfg.api.base.short_class)
  if found == nil then
    log.info("DUMP bases: FindAllOf(%s) -> none", M.cfg.api.base.short_class)
    return
  end
  log.info("DUMP bases: %d model(s)", #found)
  for i, model in ipairs(found) do
    if ue.is_valid(model) then
      local range = ue.try_get(model, M.cfg.api.base.area_range_property)
      local tf_prop = select(1, ue.probe_get(model, M.cfg.api.base.transform_properties))
      local tf_fn = select(1, ue.probe_call(model, M.cfg.api.base.transform_getters))
      local gid_prop = select(1, ue.probe_get(model, M.cfg.api.base.group_id_properties))
      log.info("DUMP   base[%d] AreaRange=%s transform-prop=%s transform-fn=%s groupid-prop=%s",
        i, tostring(range), tostring(tf_prop), tostring(tf_fn), tostring(gid_prop))
      if i == 1 then
        dump_members("base-model", model, { "transform", "group", "guid", "id", "range", "point" })
      end
    end
  end
end

local function dump_map_objects()
  -- Broad sweep: try the configured container candidates plus generic names.
  local candidates = {}
  for _, c in ipairs(M.cfg.api.craft.container_model_classes) do
    table.insert(candidates, c)
  end
  for _, c in ipairs({ "PalMapObjectModel", "PalMapObjectConcreteModelBase", "PalItemContainer" }) do
    table.insert(candidates, c)
  end

  local seen_classes = {}
  for _, short in ipairs(candidates) do
    local found = ue.find_all_of(short)
    if found == nil then
      log.info("DUMP map-objects: FindAllOf(%s) -> none", short)
    else
      log.info("DUMP map-objects: FindAllOf(%s) -> %d instance(s)", short, #found)
      for _, obj in ipairs(found) do
        if ue.is_valid(obj) then
          local cls = ue.class_name(obj)
          if not seen_classes[cls] then
            seen_classes[cls] = true
            dump_members("map-object " .. cls, obj,
              { "container", "craft", "convert", "material", "product", "ingredient", "item" })
          end
        end
      end
    end
  end
end

function M.run()
  log.info("========== API DISCOVERY DUMP begin ==========")
  local ok, err = pcall(function()
    dump_player()
    dump_bases()
    dump_map_objects()
  end)
  if not ok then
    log.error("API dump aborted: %s", tostring(err))
  end
  log.info("========== API DISCOVERY DUMP end ==========")
  log.info("Copy the DUMP lines from UE4SS.log into research/notes/verified-hooks.md")
end

function M.setup(cfg)
  M.cfg = cfg
  if cfg.debug.dump_key then
    local bound = ue.register_key_bind(cfg.debug.dump_key, function()
      pcall(M.run)
    end)
    if bound then
      log.info("API dump bound to key %s", tostring(cfg.debug.dump_key))
    else
      log.debug("API dump keybind %s not registered (RegisterKeyBind/Key unavailable?)",
        tostring(cfg.debug.dump_key))
    end
  end
  if cfg.debug.dump_apis_on_init then
    -- Give the world a moment to settle after ready-state.
    if not ue.execute_with_delay(5000, function() pcall(M.run) end) then
      pcall(M.run)
    end
  end
end

return M
