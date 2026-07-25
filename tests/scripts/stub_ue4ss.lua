--[[
  stub_ue4ss.lua — minimal offline stand-in for the UE4SS Lua environment.

  Lets the mod's require-graph and fail-soft paths run under plain Lua 5.4.
  Behavior is configurable per scenario via `install(opts)`:
    opts.objects        map short-class-name -> object (FindFirstOf source)
    opts.all_objects    map short-class-name -> list   (FindAllOf source)
    opts.hooks_succeed  set of hook-path -> true (RegisterHook succeeds)
    opts.loop_iterations max times a LoopAsync callback is driven (default 3)
]]

local M = {}

M.state = nil

local GLOBALS = {
  "RegisterHook", "NotifyOnNewObject", "LoopAsync", "ExecuteWithDelay",
  "FindAllOf", "FindFirstOf", "StaticFindObject", "RegisterKeyBind", "Key",
}

function M.install(opts)
  opts = opts or {}
  local state = {
    hooks = {},        -- path -> callback
    notifies = {},     -- class path -> callback
    keybinds = {},
    loops = {},
    log_lines = {},
  }
  M.state = state

  _G.print = function(msg)
    table.insert(state.log_lines, tostring(msg))
    if opts.echo then io.write(tostring(msg)) end
  end

  if opts.bare then
    for _, name in ipairs(GLOBALS) do _G[name] = nil end
    return state
  end

  _G.RegisterHook = function(path, callback)
    if opts.hooks_succeed and opts.hooks_succeed[path] then
      state.hooks[path] = callback
      return 1, 2
    end
    error("Failed to find function by name (stub): " .. tostring(path))
  end

  _G.NotifyOnNewObject = function(class_path, callback)
    state.notifies[class_path] = callback
  end

  _G.LoopAsync = function(_ms, callback)
    -- Drive synchronously a bounded number of times (a real game loops async).
    table.insert(state.loops, callback)
    local n = opts.loop_iterations or 3
    for _ = 1, n do
      if callback() == true then break end
    end
  end

  _G.ExecuteWithDelay = function(_ms, callback)
    if not opts.defer_delays then callback() end
  end

  _G.FindAllOf = function(short)
    return (opts.all_objects or {})[short]
  end

  _G.FindFirstOf = function(short)
    return (opts.objects or {})[short]
  end

  _G.StaticFindObject = function(_path) return nil end

  _G.Key = setmetatable({}, { __index = function(_, k) return "KEY_" .. k end })
  _G.RegisterKeyBind = function(key, callback)
    state.keybinds[key] = callback
  end

  return state
end

-- Fresh module state between scenarios: drop the mod's modules from cache.
function M.reset_modules()
  for name in pairs(package.loaded) do
    if name:match("^config%.") or name:match("^core%.") or name:match("^features%.")
      or name:match("^hooks%.") or name:match("^util%.") then
      package.loaded[name] = nil
    end
  end
end

function M.log_contains(pattern)
  for _, line in ipairs(M.state.log_lines) do
    if line:find(pattern, 1, true) then return true end
  end
  return false
end

function M.dump_log()
  return table.concat(M.state.log_lines, "")
end

return M
