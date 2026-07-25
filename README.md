# Palworld Storage Manager

UE4SS-based storage management mod for **Palworld 1.0**.

> **Target platform: Xbox PC Game Pass / Microsoft Store (WinGDK)** — not Steam-primary.  
> Status: Design + scaffold — implementation follows.

---

## Overview

This repository hosts the development workspace for **PalStorageManager**, a storage quality-of-life mod for the **Game Pass (WinGDK)** build of Palworld.

Primary stack (planned):

| Layer | Tech |
| --- | --- |
| Game | Palworld **1.0** — **Xbox PC Game Pass / MS Store** |
| Binary folder | `Pal/Binaries/WinGDK/` (not Steam `Win64`) |
| Runtime | [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) Lua — **manual install** (no Steam Workshop) |
| Optional assets | Unreal `.pak` / DataTable overrides |

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

## Install target (Game Pass)

```
<XboxGames>/Palworld/Content/   # typical root — may vary
  Pal/Binaries/WinGDK/
    Palworld-WinGDK-Shipping.exe
    dwmapi.dll                  # UE4SS loader (per build)
    ue4ss/Mods/PalStorageManager/
      Scripts/main.lua
      config/
      enabled.txt
      mod.json
```

Some UE4SS builds use `WinGDK/Mods/` instead of `WinGDK/ue4ss/Mods/` — check your UE4SS layout.

**Not Steam:** Do not use Steam Workshop paths or `Pal/Binaries/Win64/` as the primary install target.

---

## Implementation (for AI / contributors)

| Doc | Purpose |
| --- | --- |
| **[CLAUDE.md](./CLAUDE.md)** | **Start here** — full implementer brief (Claude reads this first) |
| **[PROMPT_CLAUDE_TERMINAL.md](./PROMPT_CLAUDE_TERMINAL.md)** | **Paste-ready** full-dev prompt (implement + test + debug + fix) |
| [docs/design/PSEUDOCODE_v1.md](./docs/design/PSEUDOCODE_v1.md) | Module pseudocode |
| [docs/design/FEATURE_SPEC_v1.md](./docs/design/FEATURE_SPEC_v1.md) | Feature spec, tests, risks |

**v1 features:** (1) craft uses all base storage (2) unlimited weight inside base camp.

## Development status

| Area | State |
| --- | --- |
| Folder structure | Done |
| GitHub private repo | Done |
| Design / pseudocode / Claude brief | Done |
| Lua implementation | Pending |
| Config schema | Pending |
| Packaging / release | Pending |

---

## License

MIT — see [LICENSE](./LICENSE).

Palworld is a trademark of Pocketpair, Inc. This project is unofficial and not affiliated with Pocketpair.
