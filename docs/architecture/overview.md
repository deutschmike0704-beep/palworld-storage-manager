# Architecture overview (scaffold)

## Runtime model

```
Palworld 1.0 — Xbox PC Game Pass (WinGDK)
  └── Pal/Binaries/WinGDK/
        └── UE4SS
              └── Mods/PalStorageManager
                    ├── enabled.txt
                    ├── config/          # defaults shipped with mod
                    └── Scripts/
                          ├── main.lua   # bootstrap / require graph
                          ├── core/      # storage + inventory domain logic
                          ├── features/  # F1 craft storage, F2 weight
                          ├── hooks/     # Bind/Hook registrations
                          ├── util/      # pure helpers
                          └── config/    # load / validate user config
```

Primary platform: **Game Pass / Microsoft Store (WinGDK)**. Steam `Win64` is secondary only.

## Module responsibilities (v1)

| Module | Responsibility |
| --- | --- |
| `core` | Storage index, item count/consume, base-context (inside camp?) |
| `features` | **F1** unified craft storage · **F2** infinite weight in base |
| `hooks` | UE4SS craft material hooks + weight poll / recalculate hooks |
| `ui` | (v1 unused) |
| `util` | Logging, throttle |
| `config` | Defaults merge, feature flags |

Design source of truth:

- [`docs/design/FEATURE_SPEC_v1.md`](../design/FEATURE_SPEC_v1.md)
- [`docs/design/PSEUDOCODE_v1.md`](../design/PSEUDOCODE_v1.md)

## Optional content layer

If Lua alone is insufficient (DataTables, custom widgets):

```
content/Pal/Content/Pal/
  ├── DataTable/   # balance / item metadata overrides
  ├── Blueprint/   # BP mods if needed
  └── UI/          # widget assets
```

Packaged as a companion `.pak` under `dist/`.

## Non-goals (for now)

- Full inventory rewrite
- Server authority bypass / cheating tools
- Shipping UE4SS itself inside this repo
