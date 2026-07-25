--[[
  features/weight_in_base.lua — F2: effectively unlimited carry weight while
  the player stands inside their own base camp.

  Mechanism: hooks/weight_hooks.lua overrides the return value of the game's
  max-weight query while `inside own base` is true. Because vanilla keeps
  computing its own value every call, leaving the base restores the vanilla
  limit automatically (restore_on_leave). This module only maintains the
  inside/outside state via the poll loop and answers the override question.

  Authority note (spec §7 / CLAUDE.md rule 4): on the primary target
  (Game Pass client, singleplayer / local coop host) the local process is
  the authority, so the override is effective. On a dedicated server the
  mod must run server-side for the value to replicate.
]]

local log = require("util.log")
local base_context = require("core.base_context")

local M = {
  cfg = nil,
  hook_available = false, -- set by weight_hooks once a hook registered
  inside = false,
  was_inside_once = false,
}

function M.init(cfg)
  M.cfg = cfg
end

function M.set_hook_available(available)
  M.hook_available = available == true
end

-- Poll tick: recompute inside-own-base state, log transitions.
function M.update()
  local pawn = base_context.get_player_pawn()
  local inside = false
  if pawn ~= nil then
    inside = base_context.is_player_inside_own_base(pawn)
  end

  if inside ~= M.inside then
    M.inside = inside
    if inside then
      M.was_inside_once = true
      log.info("F2: entered own base — max carry weight -> %d", M.cfg.weight.infinite_max_weight)
    else
      if M.cfg.weight.restore_on_leave then
        log.info("F2: left base — vanilla max carry weight restored")
      else
        log.info("F2: left base — keeping buff (restore_on_leave=false)")
      end
    end
  end
end

-- Called from the max-weight hook. Returns the override value, or nil to
-- leave the vanilla return value untouched.
function M.max_weight_override()
  if M.cfg == nil or not M.cfg.weight.enabled or not M.hook_available then
    return nil
  end
  if M.inside then
    return M.cfg.weight.infinite_max_weight
  end
  if not M.cfg.weight.restore_on_leave and M.was_inside_once then
    return M.cfg.weight.infinite_max_weight
  end
  return nil
end

return M
