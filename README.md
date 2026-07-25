# Palworld Storage Manager

UE4SS-based storage management mod for **Palworld 1.0**.

> **Target platform: Xbox PC Game Pass / Microsoft Store (WinGDK)** — not Steam-primary.
> Status: **v0.1.0 code-complete.** F2 (weight) active pending one hook check on your install; F1 (unified craft) soft-disabled until its 1.0 hook paths are verified in-game (no guessed engine paths — see below).

---

## Features (v1)

| ID | Feature | Verhalten |
| --- | --- | --- |
| **F1** | Unified Craft Storage | An Werkbänken zählen Materialien aus **allen Storage-Containern der aktuellen Base** (+ optional Spieler-Inventar) und werden beim Craft von dort abgezogen — ohne Doppelabzug. |
| **F2** | Unlimited Weight in Base | Im eigenen Base-Camp-Bereich effektiv unbegrenztes Tragelimit (1.000.000); beim Verlassen sofort wieder Vanilla. |

Beide Features sind einzeln per Config abschaltbar. Fehlende/umbenannte
Game-APIs deaktivieren das betroffene Feature sauber mit einer
`[PalStorageManager]`-Logzeile — kein Crash-Loop.

### Warum ist F1 anfangs aus?

Die Craft-Hook-Pfade der 1.0-Build sind nicht öffentlich verifiziert, und
dieses Projekt shippt **keine geratenen UFunction-Pfade**. Der Mod bringt
einen eingebauten API-Dump mit (Taste **F6**), mit dem die echten Pfade in
wenigen Minuten aus dem laufenden Spiel ermittelt und in der User-Config
eingetragen werden — Workflow: [`docs/guides/TESTING_GAMEPASS.md`](./docs/guides/TESTING_GAMEPASS.md) §3
und [`research/notes/verified-hooks.md`](./research/notes/verified-hooks.md).

---

## Install (Game Pass / WinGDK)

1. **UE4SS** (Palworld-kompatible / experimental Build) manuell installieren nach:

```
<XboxGames>/Palworld/Content/          # typischer Root, z.B. C:\XboxGames\Palworld\Content
  Pal/Binaries/WinGDK/
    Palworld-WinGDK-Shipping.exe
    dwmapi.dll                         # UE4SS loader (Name je nach Build)
    ue4ss/Mods/                        # oder direkt WinGDK/Mods/ — beides kommt vor
```

2. **Mod deployen** (eine der Varianten):
   - `tools/deploy/deploy.ps1` — liest `PALWORLD_ROOT` aus Parameter/Env/`.env`
     (siehe `.env.example`), erkennt `ue4ss\Mods` vs. `Mods` automatisch.
   - Release-Zip aus `tools/packaging/package.sh` in den Mods-Ordner entpacken.
   - Oder `src/PalStorageManager/` von Hand nach `…/WinGDK/ue4ss/Mods/PalStorageManager/` kopieren.

3. Spiel starten → `UE4SS.log` muss enthalten:

```
[PalStorageManager][info] PalStorageManager v0.1.0 bootstrap (Palworld 1.0, Game Pass/WinGDK primary)
[PalStorageManager][info] init complete
```

**Nicht Steam:** Kein Workshop, kein `steamapps`, kein `Win64` als
Default-Pfad. (Die Lua-Logik läuft auf Steam vermutlich identisch — nur die
Install-Pfade unterscheiden sich: `Win64` statt `WinGDK`.)

## Konfiguration

Defaults: `Scripts/config/defaults.lua`. Überschreiben per
`Scripts/config/user.lua` (Vorlage: `user.lua.example`) oder
`<mod root>/config/config.lua`. Wichtigste Schalter:

```lua
return {
  log_level = "info",              -- debug | info | warn | error
  craft  = { enabled = true, include_player_inventory = true,
             prefer_consume_order = "player_first" },
  weight = { enabled = true, infinite_max_weight = 1000000,
             restore_on_leave = true },
  debug  = { dump_key = "F6", log_index_summary = false },
  -- api = { craft = { count_hook = "...", consume_hook = "..." } }  -- nach Verifikation
}
```

## Testen

- Offline (Repo, ohne Spiel): `lua tests/scripts/run_all.lua` — 27 Tests
  (Bootstrap-Fail-Soft, F2-Statemachine, Index/Count/Consume, Doppel-Consume-Schutz).
- Im Spiel: kompletter Testplan in [`docs/guides/TESTING_GAMEPASS.md`](./docs/guides/TESTING_GAMEPASS.md).

## Troubleshooting

| Symptom | Ursache / Fix |
| --- | --- |
| Keine `[PalStorageManager]`-Zeilen im Log | Falscher Mods-Pfad (`WinGDK` vs. `Win64`; `ue4ss/Mods` vs. `Mods`) oder UE4SS lädt nicht (`dwmapi.dll` fehlt) |
| `F2 weight-in-base DISABLED … TODO(VERIFY)` | Max-Weight-Hook-Pfad hat sich in 1.0 geändert → F6-Dump fahren, `api.weight.max_weight_hooks` in user.lua setzen |
| `F1 … SOFT-DISABLED: unverified hook paths` | Erwartet in 0.1.0 — Hook-Verifikation durchführen (Guide §3) |
| Mod nach Game-Update verschwunden | Game-Pass-Updates können UE4SS/Mods zurücksetzen → neu deployen |
| Deploy scheitert mit Access denied | MS-Store-Sandbox blockiert Schreiben → Ordnerrechte prüfen, ggf. als Admin / nach Vollinstallation über die Xbox App („erweiterte Verwaltungsfunktionen“) |

## Multiplayer-Hinweis

Konsum (F1) und MaxWeight (F2) gehören auf die Authority-Seite. Primärziel
ist der Game-Pass-Client (Singleplayer / lokaler Koop-Host) — dort ist der
lokale Prozess die Authority. Dedicated Server brauchen den Mod
**serverseitig** für F1. Für fremde Bases gibt es einen strikten
Ownership-Modus (`weight.assume_own_base_when_unverified = false`).

---

## Repository layout

```
.
├── src/PalStorageManager/     # Deploybarer UE4SS-Mod (Scripts/, config/, enabled.txt, mod.json)
├── docs/                      # Design, Guides (TESTING_GAMEPASS), Changelog
├── research/notes/            # verified-hooks.md — API-Verifikationsstand
├── tests/scripts/             # Offline-Testsuite (plain Lua 5.4)
├── tools/deploy|packaging/    # deploy.ps1 (WinGDK), package.sh (Release-Zip)
└── dist/                      # Build-Artefakte (gitignored)
```

## Implementation docs

| Doc | Purpose |
| --- | --- |
| [CLAUDE.md](./CLAUDE.md) | Implementer brief (Regeln, DoD) |
| [docs/design/FEATURE_SPEC_v1.md](./docs/design/FEATURE_SPEC_v1.md) | Feature-Spec, Testmatrix, Risiken |
| [docs/design/PSEUDOCODE_v1.md](./docs/design/PSEUDOCODE_v1.md) | Modul-Pseudocode |
| [research/notes/verified-hooks.md](./research/notes/verified-hooks.md) | Hook-Verifikationsstand + Workflow |
| [docs/changelog/0.1.0.md](./docs/changelog/0.1.0.md) | Release notes 0.1.0 |

## Development status

| Area | State |
| --- | --- |
| Lua implementation (F1+F2, fail-soft, config) | **Done (0.1.0)** |
| Offline tests | **Done — 27 passing** |
| In-game verification (Game Pass) | **Pending** — needs a machine with the game; guide ready |
| F1 hook paths | **TODO(VERIFY)** via in-game API dump |
| Packaging / deploy tooling | Done |

---

## License

MIT — see [LICENSE](./LICENSE).

Palworld is a trademark of Pocketpair, Inc. This project is unofficial and not affiliated with Pocketpair.
