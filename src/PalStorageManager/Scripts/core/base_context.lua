--[[
  core/base_context.lua — which base is the player/workbench in, and is it theirs?

  Base camps are tracked via NotifyOnNewObject on PalBaseCampModel
  (community-verified class) plus a throttled FindAllOf rescan.
  Camp position/ownership fields are probed from CONFIG.api.base candidates
  and fail soft: a camp whose position can't be read is simply not matched.
]]

local log = require("util.log")
local ue = require("util.ue")
local throttle = require("util.throttle")

local M = {
  cfg = nil,
  bases = {},
  _rescan = nil,
}

function M.init(cfg)
  M.cfg = cfg
  M._rescan = throttle.gate(cfg.weight.base_rescan_interval_sec)
  local ok = ue.notify_new(cfg.api.base.base_camp_model_class, function(model)
    table.insert(M.bases, model)
    log.debug("base camp model registered (tracking %d)", #M.bases)
  end)
  if not ok then
    log.warn("NotifyOnNewObject(%s) unavailable; relying on periodic rescan only",
      tostring(cfg.api.base.base_camp_model_class))
  end
end

local function refresh_bases()
  if not M._rescan:ready() then return end
  local found = ue.find_all_of(M.cfg.api.base.short_class)
  if found == nil then
    log.once("no-findallof-base", "warn",
      "FindAllOf(%s) yielded nothing yet — no base camps discoverable",
      M.cfg.api.base.short_class)
    return
  end
  local fresh = {}
  for _, m in ipairs(found) do
    if ue.is_valid(m) then table.insert(fresh, m) end
  end
  M.bases = fresh
  log.debug("base rescan: %d camp model(s)", #M.bases)
end

-- TODO(VERIFY): position source on 1.0 PalBaseCampModel (Transform property
-- vs GetTransform()); probed from config candidates.
function M.base_location(model)
  local _, tf = ue.probe_get(model, M.cfg.api.base.transform_properties)
  if tf == nil then
    local _n
    _n, tf = ue.probe_call(model, M.cfg.api.base.transform_getters)
  end
  if tf == nil then return nil end
  return ue.to_xyz(ue.try_get(tf, "Translation")) or ue.to_xyz(tf)
end

function M.base_radius(model)
  local r = ue.try_get(model, M.cfg.api.base.area_range_property)
  if type(r) == "number" and r > 0 then return r end
  return M.cfg.api.base.default_area_range
end

function M.base_id(model)
  return ue.object_key(model)
end

local function player_group_id(pawn)
  local api = M.cfg.api.base
  local _, ps = ue.probe_call(pawn, api.player_state_getters)
  if not ue.is_valid(ps) then
    ps = ue.try_get(pawn, "PlayerState")
  end
  if ps == nil then return nil end
  local _n, gid = ue.probe_call(ps, api.player_group_getters)
  if gid == nil then
    _n, gid = ue.probe_get(ps, api.player_group_properties)
  end
  return ue.guid_str(gid)
end

local function base_group_id(model)
  local api = M.cfg.api.base
  local _n, gid = ue.probe_get(model, api.group_id_properties)
  if gid == nil then
    _n, gid = ue.probe_call(model, api.group_id_getters)
  end
  return ue.guid_str(gid)
end

-- Own base or same guild. When the group-id APIs are unresolved the result
-- follows weight.assume_own_base_when_unverified (true is correct for
-- singleplayer, where every camp belongs to the player).
function M.is_own_base(model, pawn)
  local bg = base_group_id(model)
  local pg = player_group_id(pawn)
  if bg ~= nil and pg ~= nil then
    return bg == pg
  end
  if M.cfg.weight.assume_own_base_when_unverified then
    log.once("own-base-unverified", "warn",
      "TODO(VERIFY): group-id APIs unresolved; assuming bases are the player's (singleplayer-safe). " ..
      "Set weight.assume_own_base_when_unverified=false to hard-require the guild check.")
    return true
  end
  log.once("own-base-strict", "warn",
    "group-id APIs unresolved and assume_own_base_when_unverified=false; treating all bases as foreign")
  return false
end

function M.get_player_pawn()
  return ue.get_player_pawn()
end

function M.get_player_location(pawn)
  local ok, vec = ue.try_call(pawn, "K2_GetActorLocation")
  if ok then return ue.to_xyz(vec) end
  return nil
end

-- Base camp model containing `location`, or nil (wilderness).
function M.get_base_at_location(location)
  if location == nil then return nil end
  refresh_bases()
  local margin = M.cfg.weight.base_radius_margin or 1.0
  for _, model in ipairs(M.bases) do
    if ue.is_valid(model) then
      local base_loc = M.base_location(model)
      if base_loc ~= nil then
        if ue.dist2d(location, base_loc) <= M.base_radius(model) * margin then
          return model
        end
      else
        log.once("base-loc-unreadable", "warn",
          "TODO(VERIFY): base camp position unreadable on %s — inside-base checks cannot match this camp",
          ue.class_name(model))
      end
    end
  end
  return nil
end

function M.is_player_inside_own_base(pawn)
  if pawn == nil then return false end
  local loc = M.get_player_location(pawn)
  if loc == nil then return false end
  local base = M.get_base_at_location(loc)
  if base == nil then return false end
  return M.is_own_base(base, pawn)
end

-- Craft context: the workbench's base if resolvable, else the base the
-- player is standing in.
function M.get_craft_context_base(workbench_or_nil, pawn)
  if workbench_or_nil ~= nil then
    local api = M.cfg.api.craft
    local _n, tf = ue.probe_get(workbench_or_nil, api.container_transform_properties)
    if tf == nil then
      _n, tf = ue.probe_call(workbench_or_nil, api.container_transform_getters)
    end
    local loc = tf and (ue.to_xyz(ue.try_get(tf, "Translation")) or ue.to_xyz(tf)) or nil
    local base = M.get_base_at_location(loc)
    if base ~= nil then return base end
  end
  if pawn == nil then return nil end
  return M.get_base_at_location(M.get_player_location(pawn))
end

-- Test/support: replace tracked bases (used by offline smoke tests).
function M._set_bases_for_test(list)
  M.bases = list or {}
  if M._rescan then M._rescan.last = throttle.now() end
end

return M
