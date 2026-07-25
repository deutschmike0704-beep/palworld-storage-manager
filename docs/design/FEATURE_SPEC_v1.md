# Feature Spec v1 — PalStorageManager (Palworld 1.0)

**Target:** Palworld **1.0** + **UE4SS** (Lua)  
**Status:** Spec + Pseudocode only — no implementation  
**Audience:** Implementer (e.g. Claude) working from this document

---

## 1. Goals

| ID | Feature | Behavior |
| --- | --- | --- |
| **F1** | Unified Craft Storage | An einer Werkbank (und verwandten Craft-Stationen) zählen **alle Items aus allen Lagern der aktuellen Base** als verfügbare Craft-Materialien — unabhängig davon, in welcher Kiste sie liegen. |
| **F2** | Unlimited Weight In Base | Solange der Spieler **im Base-Camp-Bereich (Lager)** steht, gilt **unbegrenztes** (praktisch: sehr hohes) Tragelimit. Beim Verlassen: Vanilla-Limit zurück. |

### Explizit out of scope (v1)

- Items zwischen Bases physisch „teleportieren“ / mergen
- Inventar-Sortierung, Auto-Deposit, UI-Rework
- Server-Cheats außerhalb der eigenen Guild-Bases
- Ändern der Kisten-Slot-Anzahl

### Scope-Entscheidung F1 (v1)

```
SCOPE_STORAGE = CURRENT_BASE_ONLY   -- empfohlen für v1
-- später optional:
-- SCOPE_STORAGE = ALL_GUILD_BASES
```

**v1 = alle Container der Base, in der die Werkbank steht.**  
Guild-weite Integration (andere Bases) ist im Pseudocode als Erweiterung vorgesehen, aber default aus.

---

## 2. Vanilla-Kontext (Palworld 1.0)

### Crafting / Lager

- Vanilla nutzt typischerweise **Spieler-Inventar + verknüpfte / nahe Lager** der aktuellen Base.
- Craft-Flow (vereinfacht):
  1. UI fragt: *„Wie viele Einheiten Item X sind verfügbar?“*
  2. Spieler startet Craft → Server/Authority **zieht** Materialien ab
  3. Fertiges Item landet im Output / Inventar
- Eine robuste Mod muss **beide** Pfade abdecken:
  - **Availability / Count** (UI zeigt grün / erreichbare Menge)
  - **Consume / Spend** (beim Craft wirklich aus den richtigen Kisten abziehen)

### Gewicht

- Spieler hat `currentWeight` vs `maxWeight` (Carry Capacity).
- Übergewicht → langsam, kein Sprint/Jump/Glide.
- Base-Camp hat einen **Radius / Area**-Check („ist Spieler in Base X?“).
- Max-Weight sollte **authority-seitig** gesetzt werden und replizieren (Multiplayer-sicher).

---

## 3. High-level Architektur

```
main.lua
  ├── config          # Feature-Flags, Werte
  ├── util/log        # Logging
  ├── core/storage_index     # Index: ItemId → [{container, slot, count}]
  ├── core/item_ops          # Count / Consume über Index
  ├── core/base_context      # Aktuelle Base, Spieler in Base?
  ├── features/unified_craft # F1
  ├── features/weight_in_base# F2
  └── hooks/*                # UE4SS RegisterHook / NotifyOnNewObject
```

```
┌─────────────────────────────────────────────────────────┐
│                     Game Loop / Events                  │
└────────────┬────────────────────────────┬───────────────┘
             │                            │
     [F1 Craft Hooks]              [F2 Tick / Zone Hooks]
             │                            │
             v                            v
   StorageIndex.refresh()        BaseContext.isInsideBase()
             │                            │
             v                            v
   Count materials (all chests)  Set MaxWeight = INFINITE
   Consume across chests         Restore MaxWeight on leave
```

---

## 4. Konfiguration (v1)

Datei: `src/PalStorageManager/config/config.lua` (oder `.json`)

```
CONFIG:
  enabled: true
  log_level: "info"              # debug | info | warn | error

  craft:
    enabled: true
    scope: "current_base"        # "current_base" | "all_guild_bases"
    refresh_interval_sec: 0.5    # Index-Throttle
    include_player_inventory: true
    include_storage_containers: true
    include_guild_chest: true    # falls vorhanden / erwünscht
    exclude_container_types: []  # z.B. Personal Locker, falls problematisch

  weight:
    enabled: true
    infinite_max_weight: 1000000 # „unbegrenzt“ fürs Gameplay
    restore_on_leave: true
    poll_interval_sec: 0.25      # Zone-Check-Throttle
```

---

## 5. Kern-Datentypen (Pseudocode)

```
type ItemId        = string | FName | int   -- je nach UE4SS-Binding
type ContainerRef  = opaque handle          -- UPalItemContainer / MapObject Model
type SlotIndex     = int

type ItemStack =
  item_id: ItemId
  count: int

type StackLocation =
  container: ContainerRef
  slot: SlotIndex
  item_id: ItemId
  count: int

type StorageIndex =
  -- map ItemId -> list of StackLocation (nur stacks mit count > 0)
  by_item: Map<ItemId, List<StackLocation>>
  last_built_at: timestamp
  base_id: BaseId | null

type PlayerWeightState =
  is_buff_active: bool
  vanilla_max_cached: float | null   -- optional; oft besser neu berechnen lassen
```

---

## 6. Feature F1 — Unified Craft Storage

### 6.1 Intent

Wenn der Spieler an einer **Werkbank / Craft-Station** craftet (oder die Craft-UI Materialverfügbarkeit abfragt):

1. Sammle alle relevanten **Item-Container der aktuellen Base**.
2. Baue (gecached) einen **StorageIndex**.
3. **Count(itemId)** = Summe über alle Container (+ optional Spieler-Inventar).
4. **Consume(itemId, amount)** = ziehe der Reihe nach aus Containern ab (deterministische Reihenfolge).

### 6.2 Container-Discovery

```
FUNCTION DiscoverBaseContainers(base) -> List<ContainerRef>:
  containers = []

  FOR each map_object IN base.GetMapObjects() OR world.EnumerateMapObjectsInBase(base):
    IF NOT IsOwnedByGuildOrPlayer(map_object, local_player):
      CONTINUE
    IF IsStorageContainer(map_object):          -- Chest, Box, Barrel, Fridge, Guild Chest, ...
      container = map_object.GetItemContainer()
      IF container != null AND NOT IsExcluded(container):
        containers.APPEND(container)

  IF CONFIG.craft.include_player_inventory:
    containers.APPEND(player.GetInventoryContainer())  -- je nach API: mehrere Container (Common/Essential/...)

  RETURN containers
```

**Hinweise für Implementer:**

- Palworld 1.0 Klassennamen aus **CXXHeaderDump / UE4SS live view** verifizieren, z.B. Kandidaten:
  - Base: `UPalBaseCampModel`, `APalBaseCampManager` / subsystem
  - Storage MapObjects: `UPalMapObject*`, concrete storage models
  - Items: `UPalItemContainer`, `UPalItemSlot`, `FPalItemId`
- „Ist Storage?“ über Class-Name-Whitelist **oder** Interface/Tag (robuster als harte Class-Liste).
- Nur **geladene** Bases/MapObjects sind erreichbar — das ist normal.

### 6.3 Index bauen

```
FUNCTION BuildStorageIndex(base, player) -> StorageIndex:
  index = new StorageIndex
  index.by_item = empty map
  index.base_id = base.id
  index.last_built_at = NOW()

  FOR container IN DiscoverBaseContainers(base):
    FOR slot_index, slot IN container.GetSlots():
      IF slot.IsEmpty(): CONTINUE
      item_id = slot.GetItemId()
      count   = slot.GetStackCount()
      IF count <= 0: CONTINUE

      loc = StackLocation{container, slot_index, item_id, count}
      index.by_item[item_id].APPEND(loc)

  RETURN index
```

```
FUNCTION GetOrRefreshIndex(base, player) -> StorageIndex:
  IF cached_index exists
     AND cached_index.base_id == base.id
     AND (NOW() - cached_index.last_built_at) < CONFIG.craft.refresh_interval_sec:
    RETURN cached_index

  cached_index = BuildStorageIndex(base, player)
  RETURN cached_index
```

**Invalidierung** (zusätzlich zum Throttle):

- Nach erfolgreichem Consume
- Beim Öffnen der Craft-UI
- Optional: wenn Container-Inventory-Changed-Event verfügbar

### 6.4 Count & Consume

```
FUNCTION CountAvailable(index, item_id) -> int:
  total = 0
  FOR loc IN index.by_item[item_id] OR []:
    total += loc.count   -- oder live aus Slot lesen (genauer)
  RETURN total
```

```
FUNCTION CanCraft(index, recipe) -> bool:
  FOR each (item_id, needed) IN recipe.ingredients:
    IF CountAvailable(index, item_id) < needed:
      RETURN false
  RETURN true
```

```
FUNCTION ConsumeItems(index, requirements: List<ItemStack>) -> bool:
  -- 1) Pre-check (atomar wirken)
  FOR req IN requirements:
    IF CountAvailable(index, req.item_id) < req.count:
      LogError("Not enough", req)
      RETURN false

  -- 2) Abziehen — deterministische Order (Container-Stabilität)
  FOR req IN requirements:
    remaining = req.count
    locations = index.by_item[req.item_id]  -- sorted by container id, then slot

    FOR loc IN locations:
      IF remaining <= 0: BREAK

      live_count = loc.container.GetSlot(loc.slot).GetStackCount()
      take = MIN(live_count, remaining)

      IF take > 0:
        SUCCESS = loc.container.RemoveItem(loc.slot, take)
        -- ODER: generic inventory API: DecreaseStack / DisposeItem
        IF NOT SUCCESS:
          LogError("Remove failed", loc)
          -- Rollback-Strategie: siehe 6.6
          RETURN false
        remaining -= take

    IF remaining > 0:
      LogError("Consume incomplete after pre-check", req)
      RETURN false

  InvalidateIndex(index)
  RETURN true
```

**Consume-Reihenfolge (empfohlen):**

1. Zuerst **Spieler-Inventar** (optional, weniger „magisch“)
2. Dann Storage-Container (sortiert nach MapObject-ID)

Oder umgekehrt — **konfigurierbar**. Wichtig: **immer dieselbe Order**, damit Verhalten reproduzierbar ist.

### 6.5 Hooks (F1) — wo andocken

Implementer muss im **1.0 SDK-Dump** die echten Function-Paths finden. Strategie:

```
STRATEGY FindCraftHooks:
  SEARCH headers / live objects for keywords:
    - "Craft"
    - "Product"
    - "RemainProduct"
    - "Material"
    - "Ingredient"
    - "ItemContainer"
    - "Workbench"
    - "MapObjectConcreteModel"
    - "ConvertItem" / "CreateItem"

  TYPICAL HOOK POINTS (names illustrative — VERIFY IN DUMP):

  A) Availability (UI / can-craft):
     Hook: GetAvailableItemCount(itemId) OR CollectMaterialInfos(...)
     REPLACE/POST: return CountAvailable(index, itemId)
                    instead of vanilla nearby-only count

  B) Spend materials on craft start / each craft tick:
     Hook: OnCraftExecute / ConsumeMaterials / DisposeMaterialsForProduct
     REPLACE: call ConsumeItems(index, recipe.requirements)
               skip or no-op vanilla partial consume if we fully handled it

  C) Optional: Building/construction materials
     -- v1 optional; same index can feed build menu later
```

```
PSEUDO RegisterCraftHooks:
  ON CraftUI_Opened OR Workbench_Interact:
    base = ResolveBaseForWorkbench(workbench) OR GetPlayerCurrentBase()
    index = GetOrRefreshIndex(base, player)

  HOOK material_count_function(item_id):
    base = GetContextBase()
    index = GetOrRefreshIndex(base, player)
    RETURN CountAvailable(index, item_id)

  HOOK material_consume_function(requirements):
    base = GetContextBase()
    index = GetOrRefreshIndex(base, player)
    IF ConsumeItems(index, requirements):
      MARK handled  -- prevent double-consume by vanilla
      RETURN success
    ELSE:
      RETURN failure  -- craft should not proceed
```

### 6.6 Doppel-Consume & Rollback

**Gefahr:** Hook läuft und Vanilla zieht **auch** ab → Items verschwinden doppelt.

```
RULE DoubleConsumePrevention:
  IF our hook fully consumes:
    PREVENT vanilla consume path (skip original / return early)
  ELSE IF we only PATCH the count (availability):
    leave vanilla consume BUT vanilla must see same container set
    -- pure count-patch without consume-patch is UNSAFE if vanilla
    -- still only looks at nearby chests → craft may fail mid-way
    -- THEREFORE: v1 MUST implement BOTH count + consume
```

```
RULE Rollback (best effort):
  IF multi-item consume fails mid-way:
    -- Ideal: transactional inventory API
    -- Reality: often unavailable →
    LogError + optional refund of already taken stacks (track taken[])
    Disable further crafts until index refresh
```

### 6.7 Multiplayer / Authority

```
RULE Authority:
  Material consume MUST run on Authority (server / host).
  Client-only count display is OK for SP / listen host,
  but dedicated server needs server-side mod install.

  IF IsDedicatedServerClient AND NOT ServerHasMod:
    Feature F1 unreliable → LogWarn once
```

---

## 7. Feature F2 — Unlimited Weight im Lager (Base)

### 7.1 Intent

```
WHILE player is inside ANY owned/allowed base camp area:
  player.MaxCarryWeight = CONFIG.weight.infinite_max_weight
ELSE:
  restore normal max weight calculation
```

### 7.2 Zone-Detection

```
FUNCTION IsPlayerInsideBase(player) -> bool:
  -- Preferred API (verify in dump):
  --   player.IsInBaseCamp()
  --   OR BaseCampManager.GetBaseCampBelongingToPlayerPosition(player.location)
  --   OR distance check vs base camp locations + radius

  base = GetBaseCampAtLocation(player.GetLocation())
  IF base == null:
    RETURN false
  IF NOT PlayerMayUseBase(player, base):   -- own / guild
    RETURN false
  RETURN true
```

### 7.3 Weight apply / restore

```
STATE weight_state:
  active = false

FUNCTION ApplyInfiniteWeight(player):
  inv = player.GetInventoryData()   -- e.g. UPalPlayerInventoryData
  -- VERIFY property name in 1.0:
  --   MaxInventoryWeight / MaxWeight / CarryWeightMax / similar
  inv.SetMaxInventoryWeight(CONFIG.weight.infinite_max_weight)
  -- OR write property + call MarkDirty / replicate
  weight_state.active = true
  LogDebug("Weight buff ON")

FUNCTION RestoreWeight(player):
  inv = player.GetInventoryData()
  -- Preferred: force game to recompute from stats/passives/equipment
  inv.RecalculateMaxInventoryWeight()
  -- Fallback: if no recompute API, store previous value on enter
  weight_state.active = false
  LogDebug("Weight buff OFF")

FUNCTION UpdateWeightForPlayer(player):
  inside = IsPlayerInsideBase(player)

  IF inside AND NOT weight_state.active:
    ApplyInfiniteWeight(player)
  ELSE IF inside AND weight_state.active:
    -- re-assert periodically (stats may recompute and overwrite)
    IF inv.GetMaxInventoryWeight() < CONFIG.weight.infinite_max_weight:
      ApplyInfiniteWeight(player)
  ELSE IF NOT inside AND weight_state.active:
    RestoreWeight(player)
```

### 7.4 Hooks / Tick (F2)

```
PSEUDO RegisterWeightHooks:
  -- Option A: periodic (simple, reliable)
  EVERY CONFIG.weight.poll_interval_sec:
    player = GetLocalControlledPlayer()  -- + all players on server
    IF player: UpdateWeightForPlayer(player)

  -- Option B: event-driven (better)
  HOOK OnPlayerEnterBaseCamp / OnPlayerLeaveBaseCamp:
    UpdateWeightForPlayer(player)

  -- Option C: belt-and-suspenders
  HOOK OnMaxWeightRecalculated:
    IF IsPlayerInsideBase(player):
      ApplyInfiniteWeight(player)   -- re-apply after vanilla overwrite
```

### 7.5 Edge Cases F2

| Case | Handling |
| --- | --- |
| Stat point spent while inside | Re-apply infinite OR recompute-then-reapply |
| Teleport out of base | Next poll restores weight |
| Mount / Pal weight skills | Infinite max should still dominate while inside |
| Already overweight, leave base | Vanilla penalties apply again (expected) |
| Multiplayer | Server authority sets max weight; clients see replicate |

---

## 8. Bootstrap `main.lua` (Pseudocode)

```
FUNCTION Main():
  Log("PalStorageManager v0.x — Palworld 1.0")
  cfg = LoadConfig()

  IF NOT cfg.enabled:
    Log("Mod disabled by config")
    RETURN

  WaitUntilGameReady()          -- PlayerController / World valid
  ResolveGameAPIs()             -- cache class paths, fail soft if missing

  IF cfg.craft.enabled:
    RegisterCraftHooks(cfg)
    Log("F1 Unified Craft Storage: ON")

  IF cfg.weight.enabled:
    RegisterWeightHooks(cfg)
    Log("F2 Infinite Weight In Base: ON")

  Log("Init complete")
```

```
FUNCTION WaitUntilGameReady():
  LOOP until:
    Engine.GameViewport exists
    AND LocalPlayerController exists
    AND (optional) PalGameState ready
  SLEEP 100–250ms between checks
```

---

## 9. Modul-Map für die Umsetzung

| Datei (geplant) | Inhalt |
| --- | --- |
| `Scripts/main.lua` | Bootstrap, require-graph |
| `Scripts/config/defaults.lua` | Default CONFIG |
| `Scripts/config/loader.lua` | Load/merge user config |
| `Scripts/util/log.lua` | Logger |
| `Scripts/util/throttle.lua` | Interval helpers |
| `Scripts/core/base_context.lua` | Base resolve, inside-base check |
| `Scripts/core/storage_index.lua` | Discover, build, cache index |
| `Scripts/core/item_ops.lua` | Count, CanCraft, Consume |
| `Scripts/features/unified_craft.lua` | F1 orchestration |
| `Scripts/features/weight_in_base.lua` | F2 orchestration |
| `Scripts/hooks/craft_hooks.lua` | RegisterHook paths F1 |
| `Scripts/hooks/weight_hooks.lua` | RegisterHook / tick F2 |

---

## 10. Implementierungs-Reihenfolge (für Claude)

```
STEP 1  Config + Logger + main bootstrap (safe no-op if hooks fail)
STEP 2  F2 Weight first  (simpler, good smoke test that UE4SS runs)
        - find MaxWeight property
        - find IsInBaseCamp
        - poll loop
STEP 3  Container discovery dump (debug command / log all container class names in base)
STEP 4  StorageIndex + CountAvailable (log-only mode: print totals)
STEP 5  Hook availability/count path → UI shows combined numbers
STEP 6  Hook consume path → real craft spends across chests
STEP 7  Double-consume tests + multiplayer authority check
STEP 8  Polish: config, error handling, changelog
```

---

## 11. Testplan

### F1 Craft

| # | Szenario | Erwartung |
| --- | --- | --- |
| C1 | Wood nur in Kiste A, Werkbank fern von A | Craft möglich, UI zeigt genug Wood |
| C2 | Materialien über 3 Kisten verteilt | Craft zieht korrekt ab, Summen stimmen |
| C3 | Zu wenig Material gesamt | Craft blockiert, kein Partial-Consume |
| C4 | Craft 10× hintereinander | Keine Doppel-Abzüge, Index konsistent |
| C5 | Fremde Base / nicht eigene Kiste | Nicht einbezogen |
| C6 | (Optional) zweite Base | Nur bei `all_guild_bases` einbezogen |

### F2 Weight

| # | Szenario | Erwartung |
| --- | --- | --- |
| W1 | Betritt Base mit Overweight | Max → 1e6, freies Laufen/Sprinten |
| W2 | Verlässt Base | Vanilla-Max zurück, Overweight-Penalty ggf. wieder da |
| W3 | Stat-Upgrade in Base | Bleibt „unbegrenzt“ |
| W4 | Teleport Base → Wildnis | Restore innerhalb eines Poll-Intervalls |

---

## 12. Risiken & Mitigation

| Risiko | Mitigation |
| --- | --- |
| 1.0 renames functions vs EA dumps | Immer gegen **aktuellen** CXXHeaderDump / Live-View arbeiten; keine hardcodeten alten Paths ohne Verify |
| Double consume | Beide Hooks (count+consume); early-return nach eigenem Consume |
| Client-only auf Dedicated Server | README: Server + Client install für F1 |
| Performance bei 100+ Kisten | Index-Cache + Throttle; nicht jeden Frame full scan |
| Falsche Container (Pal-Box, Hatching, …) | Whitelist / Blacklist in Config |
| Weight wird von Vanilla überschrieben | Re-apply on recalculate + periodic assert |

---

## 13. Akzeptanzkriterien v1

1. An einer Werkbank in Base B sind Materialien aus **allen** Storage-Containern von Base B craftbar.
2. Craft **zieht** Materialien aus diesen Containern ab (nicht nur UI-Anzeige).
3. Spieler-Inventar zählt weiterhin (Config).
4. Im Base-Bereich: kein Overweight-Penalty (MaxWeight effektiv unbegrenzt).
5. Außerhalb Base: Vanilla-Gewicht.
6. Keine Crashes beim Base-Enter/Leave und bei leerem Index.
7. Config kann F1/F2 einzeln deaktivieren.

---

## 14. Kurz-Pseudocode (Copy-Paste Kernel)

```text
// ========== CONFIG ==========
CRAFT_SCOPE = CURRENT_BASE
INFINITE_WEIGHT = 1_000_000
WEIGHT_POLL = 0.25s
INDEX_TTL = 0.5s

// ========== F1 ==========
on_mod_start:
  register_hooks_for_material_count(on_count)
  register_hooks_for_material_consume(on_consume)

on_count(item_id):
  base = base_of(active_workbench or player)
  idx = get_index(base)   // cached
  return sum(stacks of item_id in idx)

on_consume(recipe_costs):
  base = base_of(active_workbench or player)
  idx = get_index(base)
  if not can_pay(idx, recipe_costs): return FAIL
  for each cost:
    remaining = cost.amount
    for stack in idx.locations[cost.item_id] ordered:
      take = min(stack.count, remaining)
      stack.container.remove(stack.slot, take)
      remaining -= take
  invalidate(idx)
  return OK  // and SKIP vanilla consume

// ========== F2 ==========
every WEIGHT_POLL:
  p = local_player()
  if inside_own_base(p):
    set_max_weight(p, INFINITE_WEIGHT)
  else if weight_buff_was_active(p):
    recalculate_max_weight(p)
```

---

## 15. Nächster Schritt

Implementer (Claude):

1. Dieses Spec als Source of Truth verwenden.
2. Mit **Palworld 1.0 UE4SS dump** die echten UFunction-Pfade für Count/Consume/MaxWeight/BaseCamp befüllen.
3. Implementierungsreihenfolge aus §10 einhalten.
4. Keine Feature-Creep: nur F1 + F2.

**Nicht** raten bei Class-Namen — bei Unklarheit erst debug-loggen (`NotifyOnNewObject`, `RegisterHook` mit Print), dann hardcoden.
