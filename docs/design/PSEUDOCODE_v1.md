# PSEUDOCODE v1 — PalStorageManager

> Kompakter Implementierungs-Blueprint für Palworld **1.0** / UE4SS Lua.  
> Volle Spec: [`FEATURE_SPEC_v1.md`](./FEATURE_SPEC_v1.md)

**Features**

1. **F1** Craft an Werkbank nutzt Items aus **allen Lagern der aktuellen Base**
2. **F2** **Unbegrenztes Gewicht**, solange Spieler **im Base-Lager** ist

Alle Class-/Function-Namen unten sind **Platzhalter** → im 1.0-SDK-Dump verifizieren.

---

## File layout (target)

```
Scripts/
  main.lua
  config/defaults.lua
  config/loader.lua
  util/log.lua
  util/throttle.lua
  core/base_context.lua
  core/storage_index.lua
  core/item_ops.lua
  features/unified_craft.lua
  features/weight_in_base.lua
  hooks/craft_hooks.lua
  hooks/weight_hooks.lua
```

---

## config/defaults.lua

```
DEFAULTS = {
  enabled = true,
  log_level = "info",

  craft = {
    enabled = true,
    scope = "current_base",          -- later: "all_guild_bases"
    refresh_interval_sec = 0.5,
    include_player_inventory = true,
    include_storage_containers = true,
    include_guild_chest = true,
    prefer_consume_order = "player_first",  -- or "storage_first"
    exclude_class_substrings = {
      -- examples after dump review:
      -- "Personal", "Locker", "PalBox"
    },
  },

  weight = {
    enabled = true,
    infinite_max_weight = 1000000,
    poll_interval_sec = 0.25,
    restore_on_leave = true,
  },
}
```

---

## util/log.lua

```
LEVELS = { debug=10, info=20, warn=30, error=40 }
current_level = LEVELS.info

function set_level(name): current_level = LEVELS[name] or 20

function log(level, msg, ...):
  if LEVELS[level] < current_level: return
  print(f"[PalStorageManager][{level}] " .. format(msg, ...))

function debug(...): log("debug", ...)
function info(...):  log("info", ...)
function warn(...):  log("warn", ...)
function error(...): log("error", ...)
```

---

## core/base_context.lua

```
function get_local_player():
  -- VERIFY: path to controlled PalCharacter / PlayerState
  pc = UEHelpers.GetPlayerController()
  if not pc: return null
  return pc:K2_GetPawn()  -- or game-specific getter

function get_player_location(player):
  return player:K2_GetActorLocation()

function get_base_at_location(location):
  -- VERIFY 1.0 API candidates:
  --   PalBaseCampManager:GetBaseCampIdBelongingToPoint(location)
  --   or iterate bases and check radius
  base = BaseCampManager.FindBaseContainingPoint(location)
  return base  -- null if wild

function get_base_for_workbench(workbench):
  -- preferred: workbench belongs to a base model
  base = workbench.GetOwnerBaseCamp()
      or get_base_at_location(workbench.GetLocation())
  return base

function player_may_use_base(player, base):
  -- own base or same guild
  return base.IsPlayerAllowed(player)

function is_player_inside_own_base(player):
  base = get_base_at_location(get_player_location(player))
  if base == null: return false
  return player_may_use_base(player, base)

function get_craft_context_base(workbench_or_null, player):
  if workbench_or_null:
    base = get_base_for_workbench(workbench_or_null)
    if base: return base
  return get_base_at_location(get_player_location(player))
```

---

## core/storage_index.lua

```
-- cached_index: { base_id, built_at, by_item: map<item_id, list<loc>> }
cached_index = null

type loc = {
  container,   -- item container handle
  slot,        -- int
  item_id,
  count,       -- snapshot
  source,      -- "player" | "storage"
}

function is_storage_map_object(map_object):
  -- VERIFY: classname whitelist OR "has item container + storage tag"
  name = map_object:GetClass():GetName()
  if matches_any(name, CONFIG.craft.exclude_class_substrings):
    return false
  if map_object.HasItemContainer and map_object.IsStorageLike:
    return true
  -- fallback whitelist after dump:
  -- WoodenChest, MetalChest, RefrigeratedStorage, GuildChest, ...
  return is_in_whitelist(name)

function discover_containers(base, player) -> list:
  result = []

  if CONFIG.craft.include_storage_containers:
    for map_object in base.EnumerateMapObjects():
      if not player_may_use_base(player, base): continue
      if not is_storage_map_object(map_object): continue
      container = map_object.GetItemContainer()
      if container:
        result.append({ container = container, source = "storage" })

  if CONFIG.craft.include_player_inventory:
    for container in player.GetAllItemContainersRelevantForCraft():
      -- typically common/loadout/etc. — VERIFY which ones craft uses
      result.append({ container = container, source = "player" })

  return result

function build_index(base, player):
  index = {
    base_id = base.GetId(),
    built_at = now(),
    by_item = {},
  }

  for entry in discover_containers(base, player):
    container = entry.container
    for slot_i = 0 to container.GetSlotNum()-1:
      slot = container.GetSlot(slot_i)
      if slot.IsEmpty(): continue
      item_id = slot.GetItemId()      -- normalize to string key
      count   = slot.GetStackCount()
      if count <= 0: continue

      key = normalize_item_id(item_id)
      loc = {
        container = container,
        slot = slot_i,
        item_id = key,
        count = count,
        source = entry.source,
      }
      index.by_item[key] = index.by_item[key] or {}
      append(index.by_item[key], loc)

  -- stable order for consume
  for key, list in index.by_item:
    sort list by:
      1) source according to prefer_consume_order
      2) container stable id
      3) slot index

  return index

function invalidate_index():
  cached_index = null

function get_index(base, player):
  if cached_index
     and cached_index.base_id == base.GetId()
     and (now() - cached_index.built_at) < CONFIG.craft.refresh_interval_sec:
    return cached_index

  cached_index = build_index(base, player)
  return cached_index
```

---

## core/item_ops.lua

```
function count_available(index, item_id) -> int:
  key = normalize_item_id(item_id)
  total = 0
  for loc in (index.by_item[key] or {}):
    -- prefer LIVE read to avoid stale snapshot
    live = loc.container.GetSlot(loc.slot).GetStackCount()
    -- also verify same item still in slot
    if loc.container.GetSlot(loc.slot).GetItemId() == key:
      total += live
  return total

function can_afford(index, costs) -> bool:
  -- costs: list of { item_id, count }
  for c in costs:
    if count_available(index, c.item_id) < c.count:
      return false
  return true

function consume(index, costs) -> bool:
  if not can_afford(index, costs):
    error("consume precheck failed")
    return false

  taken = []   -- for optional refund

  for c in costs:
    remaining = c.count
    key = normalize_item_id(c.item_id)

    for loc in (index.by_item[key] or {}):
      if remaining <= 0: break

      slot = loc.container.GetSlot(loc.slot)
      if slot.IsEmpty(): continue
      if normalize_item_id(slot.GetItemId()) != key: continue

      live = slot.GetStackCount()
      take = min(live, remaining)
      if take <= 0: continue

      ok = loc.container.RemoveFromSlot(loc.slot, take)
      -- VERIFY real API: Dispose, DecreaseStackCount, RequestRemoveItem, ...
      if not ok:
        error("remove failed", loc)
        -- optional: refund(taken)
        invalidate_index()
        return false

      append(taken, { loc, take })
      remaining -= take

    if remaining > 0:
      error("incomplete consume", c)
      -- optional: refund(taken)
      invalidate_index()
      return false

  invalidate_index()
  return true
```

---

## features/unified_craft.lua

```
active_workbench = null

function on_workbench_opened(workbench):
  active_workbench = workbench
  player = get_local_player()
  base = get_craft_context_base(workbench, player)
  if base:
    get_index(base, player)  -- warm cache
    info("Craft context base=", base.GetId())

function on_workbench_closed():
  active_workbench = null
  invalidate_index()

function query_available(item_id) -> int:
  player = get_local_player()
  base = get_craft_context_base(active_workbench, player)
  if base == null:
    return vanilla_count(item_id)   -- fallback
  index = get_index(base, player)
  return count_available(index, item_id)

function try_consume(costs) -> bool:
  player = get_local_player()
  base = get_craft_context_base(active_workbench, player)
  if base == null:
    return false   -- let vanilla handle OR fail safe
  index = get_index(base, player)
  return consume(index, costs)
```

---

## features/weight_in_base.lua

```
state = {
  buff_active = false,
  -- optional: last_vanilla_max = null
}

function get_inventory_data(player):
  -- VERIFY: UPalPlayerInventoryData on player/state
  return player.GetInventoryData()

function apply_infinite_weight(player):
  inv = get_inventory_data(player)
  if not inv: return
  inv.SetMaxInventoryWeight(CONFIG.weight.infinite_max_weight)
  -- or: inv.MaxInventoryWeight = CONFIG.weight.infinite_max_weight
  state.buff_active = true
  debug("weight buff ON")

function restore_weight(player):
  inv = get_inventory_data(player)
  if not inv: return
  if inv.RecalculateMaxInventoryWeight:
    inv.RecalculateMaxInventoryWeight()
  else:
    -- fallback: restore cached vanilla if we stored it on enter
    pass
  state.buff_active = false
  debug("weight buff OFF")

function update_weight(player):
  if player == null: return
  inside = is_player_inside_own_base(player)

  if inside:
    inv = get_inventory_data(player)
    if not state.buff_active:
      apply_infinite_weight(player)
    else if inv.GetMaxInventoryWeight() < CONFIG.weight.infinite_max_weight:
      -- vanilla recomputed and overwrote us
      apply_infinite_weight(player)
  else:
    if state.buff_active:
      restore_weight(player)
```

---

## hooks/craft_hooks.lua

```
function register_craft_hooks():
  -- ********************************************************
  -- CRITICAL: replace these paths after CXXHeaderDump review
  -- ********************************************************

  -- Example pattern only:
  RegisterHook("/Script/Pal.SomeCraftComponent:GetMaterialCount",
    function(context, item_id)
      if not CONFIG.craft.enabled: return end
      count = query_available(item_id)
      -- POST-hook: overwrite return value if UE4SS API allows
      -- OR use PreHook that short-circuits
      set_return(count)
    end
  )

  RegisterHook("/Script/Pal.SomeCraftComponent:ConsumeMaterials",
    function(context, cost_array)
      if not CONFIG.craft.enabled: return end
      costs = parse_cost_array(cost_array)
      ok = try_consume(costs)
      if ok:
        -- MUST prevent vanilla double-consume
        prevent_original_call()
        set_return(success)
      else:
        set_return(failure)
    end
  )

  -- UI open/close if available
  NotifyOnNewObject("/Game/Pal/.../Workbench...", function(wb)
    -- optional bind interact
  end)

  info("craft hooks registered (paths must be verified)")
```

**Hook-Find-Algorithmus (vor Implementierung ausführen):**

```
SEARCH dump for:
  Craft, Product, Material, Ingredient, Workbench,
  ItemContainer, RemainNum, RequiredItem, Convert

LOG candidates, then pick:
  1) function used by craft UI to show "have/need"
  2) function that removes items when craft starts/ticks

TEST with log-only hooks first (do not modify).
```

---

## hooks/weight_hooks.lua

```
function register_weight_hooks():
  -- Simple reliable approach:
  LoopAsync(CONFIG.weight.poll_interval_sec * 1000, function()
    if not CONFIG.weight.enabled: return true end  -- keep looping
    player = get_local_player()
    -- on server: foreach player controller
    update_weight(player)
    return true  -- continue
  end)

  -- Optional reinforce:
  RegisterHook("/Script/Pal.PalPlayerInventoryData:SomeRecalcMaxWeight",
    function(context)
      player = owner_of(context)
      if is_player_inside_own_base(player):
        apply_infinite_weight(player)
    end
  )

  info("weight hooks registered")
```

---

## main.lua

```
function wait_until_ready(callback):
  LoopAsync(200, function()
    if UEHelpers.GetPlayerController() ~= nil:
      callback()
      return false  -- stop
    return true
  end)

function init():
  info("PalStorageManager bootstrap (Palworld 1.0)")
  CONFIG = load_config(DEFAULTS)

  if not CONFIG.enabled:
    warn("disabled in config")
    return

  wait_until_ready(function()
    if CONFIG.weight.enabled:
      register_weight_hooks()
      info("F2 weight-in-base: ON")

    if CONFIG.craft.enabled:
      register_craft_hooks()
      info("F1 unified craft storage: ON")

    info("init complete")
  end)

init()
```

---

## Execution order for implementer

```
1. main + config + log          → mod loads, prints init
2. F2 weight only               → smoke test in base
3. debug: list all containers   → whitelist/blacklist
4. storage_index + count logs   → numbers match chests
5. hook count (UI)              → craft menu shows totals
6. hook consume + prevent double
7. playtest matrix from FEATURE_SPEC §11
```

---

## Non-negotiable rules

```
RULE 1: Never ship guessed UFunction paths without dump verification.
RULE 2: F1 requires BOTH availability count AND consume (not count-only).
RULE 3: After our consume, vanilla must not consume again.
RULE 4: Weight apply on authority; re-apply if vanilla recalculates.
RULE 5: Fail soft: missing API → log error, disable that feature, no crash.
RULE 6: v1 scope = current base only unless config says otherwise.
```

---

## Minimal end-to-end kernel

```text
INIT
  load config
  when game ready:
    start weight poll
    register craft count/consume hooks

WEIGHT_POLL:
  if player in own base: max_weight = 1_000_000
  else if buff was on: recalculate max_weight

CRAFT_COUNT(item):
  base = base of workbench or player
  return sum of item across all base storages (+ player inv)

CRAFT_CONSUME(costs):
  if cannot afford from unified pool: FAIL
  remove items across storages in stable order
  invalidate cache
  SKIP vanilla consume
  OK
```
