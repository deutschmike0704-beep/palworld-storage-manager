# Verified hooks & API status — Palworld 1.0 (Game Pass / WinGDK)

Status date: 2026-07-25. This file is the single source of truth for which
engine paths are **verified**, which are **hypotheses**, and how to promote
one to the other. Nothing here was invented as "final" — unverified entries
are runtime-probed and fail soft (CLAUDE.md rule 1).

## Legend

- ✅ **VERIFIED** — confirmed against community-published working mods/docs;
  still re-check once on your install (game updates can rename things).
- 🟡 **HYPOTHESIS** — plausible (EA-era dumps / common patterns); probed at
  runtime, feature-gated, `TODO(VERIFY)`.
- 🔴 **UNKNOWN** — no public evidence; must come from your own dump. The
  dependent feature is soft-disabled until filled in.

## UE4SS runtime facts (Palworld build)

| Fact | Status | Source |
| --- | --- | --- |
| `RegisterHook` fires **after** the hooked function; `return X` from the callback **overrides the return value**; params are `RemoteUnrealParam` (`:get()`) | ✅ | pwmodding.wiki "Intro to Hooking Functions" |
| `NotifyOnNewObject("/Script/Pal.PalBaseCampModel", cb)` fires; `ExecuteWithDelay` works | ✅ | BetterBaseRange mod (github.com/bravo2056/palworld-better-base-range) |
| `LoopAsync(ms, cb)` — loop **stops when cb returns `true`** (the repo pseudocode had this inverted; code follows UE4SS semantics) | ✅ | RE-UE4SS Lua API docs |
| `FindFirstOf("PalPlayerCharacter")` returns the local player pawn | ✅ | Teh's Lua Modding tutorial (gist xrandox) |
| `StaticFindObject("/Script/Pal.Default__PalUtility")` resolves the PalUtility CDO | ✅ | Teh's Lua Modding tutorial |

## F2 — weight in base

| Item | Path / name | Status | Notes |
| --- | --- | --- | --- |
| Base camp model class | `/Script/Pal.PalBaseCampModel` | ✅ | NotifyOnNewObject + FindAllOf both used by public mods |
| Base build radius | `PalBaseCampModel.AreaRange` (float, ~2000 when defaulted) | ✅ | Read/write confirmed by BetterBaseRange |
| Base world position | `PalBaseCampModel.Transform` (prop) or `GetTransform()` | 🟡 | Probed via `api.base.transform_properties/getters`. If neither resolves, inside-base checks can't match and F2 logs `TODO(VERIFY)` once |
| Max weight query | `/Script/Pal.PalPlayerInventoryData:GetMaxInventoryWeight` | 🟡 | EA-era carry-weight mods hooked this; 1.0 name unconfirmed. F2 hard-disables (with error log) if it does not register |
| Base ownership (guild) | `PalBaseCampModel.GroupIdBelongTo` vs player-state group id | 🔴 | Probed; when unresolved, behavior follows `weight.assume_own_base_when_unverified` (default true = singleplayer-correct) |

## F1 — unified craft storage

| Item | Path / name | Status | Notes |
| --- | --- | --- | --- |
| Craft availability hook | `api.craft.count_hook` | 🔴 | **nil by default → F1 soft-disabled.** Find the function the craft UI uses for "owned amount" |
| Craft consume hook | `api.craft.consume_hook` | 🔴 | nil by default. Find the function that spends materials on craft start/tick |
| Storage map-object model | `PalMapObjectItemContainerModel` (FindAllOf candidate) | 🟡 | Dump keywords: `MapObject`, `ItemContainer`, `Chest` |
| Container slot APIs | `GetSlotNum` / `Get(i)` / slot `GetItemId`/`GetStackCount` | 🟡 | Probed candidate lists in `api.craft.*` |
| Item removal API | `RemoveItemAt` / `RemoveItemByIndex` / slot `RemoveItem` | 🔴 | Consume verifies every removal by re-reading the slot; with no working op, consume refuses before taking anything |
| Item id struct | `FPalItemId.StaticId` (FName) | 🟡 | `storage_index.item_key()` also handles FName/string directly |

## Double-consume prevention (design note)

UE4SS Lua hooks cannot cancel the original native call. Default mode
`craft.consume_mode = "vanilla_fallback"` therefore consumes **only when the
vanilla consume observably failed** (readable boolean result param) and
otherwise stands down — exactly one consumer can ever run. If the verified
consume hook turns out to be a pure decision point whose return value fully
controls the effect, switch to `consume_mode = "replace"` after in-game
verification. Residual risk to check during verification: whether vanilla's
consume can *partially* spend before failing (then the fallback needs the
refund path, which is also probe-gated).

## How to promote a 🟡/🔴 to ✅

1. Deploy the mod (`tools/deploy/deploy.ps1`), start the game, load into a base.
2. Press **F6** (or set `debug.dump_apis_on_init = true`) → the mod writes
   `DUMP …` lines (player state, inventory data, base models, map-object
   classes + members filtered by craft/container keywords) to `UE4SS.log`.
3. Cross-check against a CXXHeaderDump (UE4SS `Dump CXX Headers`) or Live View.
4. Put confirmed paths into `Scripts/config/user.lua` under `api.…`
   (see `user.lua.example`), retest, then record them here with evidence.
5. For F1: after filling `count_hook`/`consume_hook`, run the in-game test
   plan in `docs/guides/TESTING_GAMEPASS.md` §F1 — especially the
   double-consume checks — before switching `consume_mode`.

## Deviations from design docs (documented per CLAUDE.md)

- `LoopAsync` return semantics corrected (see table above).
- F2 uses a **return-value override** on the max-weight query instead of
  writing `SetMaxInventoryWeight` + `RecalculateMaxInventoryWeight`
  (spec §7.3). Rationale: no state to restore (leaving the base simply stops
  overriding → vanilla recomputes), no risk of persisting a modified value
  into saves, and it matches how public carry-weight mods work. The spec's
  "re-assert after vanilla recompute" concern disappears entirely.
- `weight.assume_own_base_when_unverified` added (not in spec): controls the
  ownership fallback while group-id APIs are unverified.
