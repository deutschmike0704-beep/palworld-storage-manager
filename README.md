# Palworld Storage Manager

UE4SS-based storage management mod for **Palworld**.

> Status: **Scaffold only** — folder structure and repo bootstrap. Implementation follows next.

---

## Overview

This repository hosts the development workspace for **PalStorageManager**, a client/server-compatible storage quality-of-life mod.

Primary stack (planned):

| Layer | Tech |
| --- | --- |
| Runtime | [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) (Lua) |
| Optional assets | Unreal `.pak` / DataTable overrides |
| Game | Palworld (`Pal`) |

---

## Repository layout

```
.
├── src/PalStorageManager/     # Deployable UE4SS mod root
│   ├── Scripts/               # Lua entry + modules
│   │   ├── core/              # Inventory / storage primitives
│   │   ├── features/          # User-facing features
│   │   ├── hooks/             # Game-hook bindings
│   │   ├── ui/                # UI helpers (if any)
│   │   ├── util/              # Shared helpers
│   │   └── config/            # Runtime config loaders
│   ├── config/                # Shipped default config files
│   └── enabled.txt            # UE4SS enable flag
│
├── content/                   # Unreal content for future pak mods
│   └── Pal/Content/Pal/       # Mirrors in-game content tree
│
├── assets/                    # Source art (icons, UI, branding)
├── config/                    # Repo-level config templates / examples
├── docs/                      # Design, architecture, guides
├── research/                  # Local dumps, FModel notes (gitignored bulk)
├── tools/                     # Packaging, deploy, SDK helpers
├── tests/                     # Script / fixture tests
└── dist/                      # Build artefacts (gitignored contents)
```

### Why this layout?

- **`src/PalStorageManager`** matches the folder you drop into  
  `Pal/Binaries/Win64/ue4ss/Mods/` (or legacy `Mods/`).
- **`Scripts/` modules** keep `main.lua` thin once implementation starts.
- **`content/`** is ready if we need DataTable / Blueprint / UI pak overrides later.
- **`research/`** holds dumps and reverse-engineering notes without polluting source.
- **`tools/`** isolates packaging so release zips stay reproducible.

---

## Install target (game side)

```
<Palworld>/Pal/Binaries/Win64/ue4ss/Mods/PalStorageManager/
├── Scripts/
│   └── main.lua
├── config/
└── enabled.txt
```

Exact UE4SS path can vary by UE4SS version / install method; packaging scripts will normalize this later.

---

## Development status

| Area | State |
| --- | --- |
| Folder structure | Done |
| GitHub private repo | Done |
| Lua implementation | Pending |
| Config schema | Pending |
| Packaging / release | Pending |
| Docs / design | Pending |

---

## License

MIT — see [LICENSE](./LICENSE).

Palworld is a trademark of Pocketpair, Inc. This project is unofficial and not affiliated with Pocketpair.
