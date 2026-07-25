# Architecture overview (scaffold)

## Runtime model

```
Palworld (UE5)
  └── UE4SS
        └── Mods/PalStorageManager
              ├── enabled.txt
              ├── config/          # defaults shipped with mod
              └── Scripts/
                    ├── main.lua   # bootstrap / require graph
                    ├── core/      # storage + inventory domain logic
                    ├── features/  # discrete player-facing features
                    ├── hooks/     # Bind/Hook registrations
                    ├── ui/        # optional UI glue
                    ├── util/      # pure helpers
                    └── config/    # load / validate user config
```

## Module responsibilities (planned)

| Module | Responsibility |
| --- | --- |
| `core` | Item stacks, containers, transfer rules, safety checks |
| `features` | Sort, deposit, withdraw, search, filters, hotkeys |
| `hooks` | Intercept relevant gameplay / UI events |
| `ui` | Any custom widgets or HUD hooks |
| `util` | Logging, tables, path helpers, debouncing |
| `config` | Defaults merge, validation, hot-reload (if feasible) |

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
