--[[
  util/throttle.lua — interval gates for poll loops and cache TTLs.
  Uses os.clock(); on Windows this is wall-clock-ish and monotonic enough
  for sub-second gating.
]]

local M = {}

function M.now()
  return os.clock()
end

-- Gate whose :ready() returns true at most once per interval_sec.
function M.gate(interval_sec)
  local g = { interval = interval_sec or 0, last = nil }

  function g:ready()
    local t = M.now()
    if self.last == nil or (t - self.last) >= self.interval then
      self.last = t
      return true
    end
    return false
  end

  function g:reset()
    self.last = nil
  end

  return g
end

-- Age-based expiry helper for cached values.
function M.expired(built_at, ttl_sec)
  if built_at == nil then return true end
  return (M.now() - built_at) >= ttl_sec
end

return M
