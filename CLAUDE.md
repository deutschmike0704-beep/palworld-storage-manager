# CLAUDE.md — Implementierungsauftrag PalStorageManager

> **Lies diese Datei zuerst.** Danach die verlinkten Specs.  
> Du setzt den Mod um — Struktur und Pseudocode existieren bereits.

---

## Rolle

Du bist ein erfahrener **Palworld / UE4SS Lua-Modder**. Du implementierst einen funktionsfähigen Mod für **Palworld 1.0** auf der **Xbox PC Game Pass / Microsoft Store-Version** (WinGDK). Du rätst keine Engine-Pfade; du verifizierst sie gegen Dumps / Live-Introspection oder markierst sie klar als `TODO(VERIFY)`.

---

## Zielplattform (WICHTIG — zuerst lesen)

**Primäres Ziel: Xbox PC Game Pass (Microsoft Store / WinGDK), Palworld 1.0.**

Das ist **nicht** die Steam-Version. Viele Guides, Workshop-Mods und Pfade im Internet beziehen sich auf Steam (`Win64`) — die gelten hier nur analog.

| Aspekt | Game Pass (dieses Projekt) | Steam (nicht Primärziel) |
| --- | --- | --- |
| Vertrieb | Xbox App / Microsoft Store | Steam |
| Binary-Ordner | **`Pal/Binaries/WinGDK/`** | `Pal/Binaries/Win64/` |
| Shipping-EXE (typisch) | `Palworld-WinGDK-Shipping.exe` | `Palworld-Win64-Shipping.exe` |
| Typischer Root | `…/XboxGames/Palworld/Content/` (kann abweichen) | `…/steamapps/common/Palworld/` |
| Steam Workshop | **nicht verfügbar** | verfügbar |
| UE4SS | **manuell** installieren (Palworld-kompatible Build) | Workshop oder manuell |

### UE4SS-Installziel (Game Pass)

```
<Palworld Game Pass Root>/
  Pal/
    Binaries/
      WinGDK/                          ← HIER UE4SS + dwmapi.dll
        Palworld-WinGDK-Shipping.exe
        dwmapi.dll                     ← UE4SS loader (Name je nach Build)
        ue4ss/                         ← oder flache UE4SS-Struktur je nach Version
          Mods/
            PalStorageManager/         ← unser Deploy-Ziel
              Scripts/main.lua
              enabled.txt
              config/
              mod.json
```

**Hinweis:** Je nach UE4SS-Build liegt `Mods/` direkt unter `WinGDK/` oder unter `WinGDK/ue4ss/Mods/`. Beides kann vorkommen — Deploy-Scripts und README müssen **beide** Varianten erwähnen; Default-Annahme für dieses Projekt: **`WinGDK/ue4ss/Mods/PalStorageManager/`**, mit Fallback-Doku für `WinGDK/Mods/`.

### Regeln speziell Game Pass

1. **Keine Steam-only-Annahmen:** Kein Workshop, kein `steamapps`, kein `Win64` als Default-Pfad in Docs/Scripts.  
2. **Pfade parametrisieren:** `PALWORLD_ROOT` + `BINARIES_DIR=WinGDK` (siehe `.env.example`).  
3. **Executable-Namen:** Logs, Process-Checks, Deploy-Hinweise → `WinGDK` / `Palworld-WinGDK-Shipping`, nicht `Win64-Shipping`.  
4. **Game Pass kann Ordner-Updates zurücksetzen:** README kurz erwähnen (nach Game-Update UE4SS/Mod ggf. neu legen).  
5. **MS Store Sandbox / Rechte:** Falls Deploy scheitert, dokumentieren — nicht still annehmen, dass Schreiben immer klappt.  
6. **Steam-Kompatibilität ist Nice-to-have, nicht DoD:** Lua-Logik ist i. d. R. gleich; abweichend sind vor allem **Install-/Binary-Pfade**. Code nicht an Steam-Workshop koppeln.  
7. **Dedicated Server** ist für den User-Fokus sekundär (Game Pass = Client). F1/F2 sollen im **Singleplayer / lokalem Coop-Client** der Game-Pass-Build laufen. Server-Hinweise optional in README, nicht blockierend.

### Deploy-Root (kanonisch für dieses Repo)

```
src/PalStorageManager/
  →  <GamePass>/Pal/Binaries/WinGDK/ue4ss/Mods/PalStorageManager/
```

---

## Pflichtlektüre (in dieser Reihenfolge)

1. **Diese Datei** (`CLAUDE.md`) — Auftrag, **Game Pass**, Constraints, Definition of Done  
2. [`docs/design/PSEUDOCODE_v1.md`](docs/design/PSEUDOCODE_v1.md) — Modul-Pseudocode, Dateilayout  
3. [`docs/design/FEATURE_SPEC_v1.md`](docs/design/FEATURE_SPEC_v1.md) — Spec, Hooks, Tests, Risiken  
4. [`docs/architecture/overview.md`](docs/architecture/overview.md) — Repo-Layout  

**Source of Truth:** Spec + Pseudocode. Bei Widerspruch gilt die Spec; diese Datei hat Vorrang bei Prozess-/Sicherheitsregeln **und Zielplattform (Game Pass / WinGDK)**.

---

## Ziel (nur v1)

Zwei Features, nichts anderes — lauffähig auf **Palworld 1.0 Game Pass (WinGDK)**:

| ID | Feature | Verhalten |
| --- | --- | --- |
| **F1** | Unified Craft Storage | An Werkbank / Craft-Stationen: Materialien aus **allen Storage-Containern der aktuellen Base** (+ optional Spieler-Inventar) zählen und werden beim Craft **von dort abgezogen**. |
| **F2** | Unlimited Weight in Base | Solange der Spieler **im eigenen Base-Camp-Bereich** ist: praktisch unbegrenztes Tragelimit (`~1_000_000`). Beim Verlassen: Vanilla-Limit zurück. |

### Explizit NICHT in v1

- Inventar-Sortierung, Auto-Deposit, Such-UI  
- Guild-weite Storage über mehrere Bases (nur Config-Hook vorbereiten, Default = current base)  
- Kisten-Slot-Erweiterung  
- UE4SS selbst ins Repo packen  
- Cheats außerhalb Base-Kontext  
- Steam-Workshop-Packaging / Steam-only Tooling  

---

## Tech-Stack & Pfade

| Was | Wert |
| --- | --- |
| Game | Palworld **1.0** |
| **Plattform** | **Xbox PC Game Pass / Microsoft Store (WinGDK)** — Primärziel |
| Runtime | **UE4SS** Lua (Palworld-kompatible / experimental build, manuell) |
| Binary-Dir | **`Pal/Binaries/WinGDK/`** (nicht Win64) |
| Deploy-Root | `src/PalStorageManager/` → `…/WinGDK/ue4ss/Mods/PalStorageManager/` |
| Entry | `src/PalStorageManager/Scripts/main.lua` |
| Enable | `src/PalStorageManager/enabled.txt` (existiert) |
| Meta | `src/PalStorageManager/mod.json` (Version bei Fortschritt anheben) |

### Ziel-Dateistruktur (anlegen / befüllen)

```
src/PalStorageManager/
  enabled.txt
  mod.json
  config/                 # optionale User-Config (Defaults im Code ok)
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

Halte dich an dieses Layout aus dem Pseudocode. Keine monolitische 2000-Zeilen-`main.lua`.

---

## Harte Regeln (nicht verhandelbar)

1. **Keine geratenen UFunction-/Class-Pfade als „fertig“.**  
   - Entweder aus Dump/Live-View verifiziert  
   - Oder als `TODO(VERIFY): <reason>` + log-only Hook / Feature-Flag soft-disable  

2. **F1 braucht Count UND Consume.**  
   Nur UI-Zahlen patchen ohne Consume → Craft schlägt fehl oder wird inkonsistent.  
   Nach eigenem Consume: **Vanilla-Consume unterbinden** (kein Doppel-Abzug).

3. **Fail-soft.**  
   Fehlende API → Feature deaktivieren, klar loggen (`[PalStorageManager]`), **kein Crash-Loop**.

4. **Authority / MP-bewusst.**  
   Item-Consume und MaxWeight idealerweise authority-seitig.  
   Primärtest: **Game Pass Client / Singleplayer**. Dedicated-Server-Hinweise optional.

5. **Scope F1 = `current_base` default.**  
   `all_guild_bases` nur vorbereiten, nicht als Default aktiv.

6. **Keine Secrets, keine Game-Binaries, keine SDK-Dumps committen.**  
   `.gitignore` beachten (`research/sdk-dump`, `*.pak`, logs, …).

7. **Kein Scope-Creep.**  
   Nur F1 + F2 + nötige Infra (config, log, hooks).

8. **Code-Sprache:** Lua-Identifier & Kommentare **Englisch**; User-facing docs dürfen Deutsch bleiben.

9. **Game Pass first.**  
   Docs, `.env.example`, Deploy-Hinweise und README gehen von **WinGDK** aus.  
   Steam/`Win64` höchstens als Nebenbemerkung („analog, anderer Ordner“).

---

## Implementierungsreihenfolge (einhalten)

```
STEP 1  Bootstrap: main.lua, config, logger — Mod lädt, loggt Init
STEP 2  F2 Weight first (einfacher Smoke-Test)
        - MaxWeight Property finden/verifizieren
        - Inside-Base Check
        - Poll-Loop + Restore on leave
STEP 3  Debug-Hilfe: Container in Base listen (Log)
STEP 4  StorageIndex + CountAvailable (erst log-only)
STEP 5  Craft availability hook → UI zeigt kombinierte Mengen
STEP 6  Craft consume hook + Double-Consume-Prevention
STEP 7  Config-Flags, Error-Handling, mod.json Version, kurze README-Update
STEP 8  Manuellen Testplan aus FEATURE_SPEC §11 abhaken (soweit möglich dokumentieren)
```

Nach jedem Step: lauffähig halten. Lieber ein Feature solid als zwei half-baked.

---

## API-Verifikation (so gehst du vor)

Wenn kein Dump im Workspace liegt:

1. Lege unter `research/notes/` kurze Fund-Notizen an (Class/Function-Namen, warum gewählt).  
2. Nutze gängige Palworld/UE4SS-Patterns (`RegisterHook`, `NotifyOnNewObject`, `StaticFindObject`, UEHelpers falls vorhanden).  
3. Hook-Kandidaten für F1 (Keywords im Dump):  
   `Craft`, `Product`, `Material`, `Ingredient`, `Workbench`, `ItemContainer`, `RequiredItem`, `Convert`  
4. Hook-Kandidaten für F2:  
   `MaxInventoryWeight`, `InventoryWeight`, `BaseCamp`, `IsInBase`, `CarryWeight`  
5. **Log-only Hooks zuerst**, dann Verhalten ändern.

Trage verifizierte Pfade in `docs/research/` oder `research/notes/verified-hooks.md` ein, damit sie nicht verloren gehen.

---

## Logging-Konvention

```
[PalStorageManager][info] ...
[PalStorageManager][debug] ...
[PalStorageManager][warn] ...
[PalStorageManager][error] ...
```

Config: `log_level = debug | info | warn | error`.

---

## Config-Defaults (Minimum)

```lua
{
  enabled = true,
  log_level = "info",
  craft = {
    enabled = true,
    scope = "current_base",
    refresh_interval_sec = 0.5,
    include_player_inventory = true,
    include_storage_containers = true,
    include_guild_chest = true,
    prefer_consume_order = "player_first",
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

## Definition of Done (v1)

- [ ] Mod lädt unter UE4SS auf **Game Pass / WinGDK** ohne Error-Spam  
- [ ] README beschreibt **Game-Pass-Install** (`WinGDK`, kein Steam-Workshop als Pflicht)  
- [ ] Deploy-Pfade / `.env.example` nutzen **WinGDK** als Default  
- [ ] **F2:** In Base kein Overweight-Penalty; außerhalb Vanilla  
- [ ] **F1:** Craft-UI sieht Summen aus allen Base-Lagern  
- [ ] **F1:** Craft zieht Items aus diesen Lagern ab (kein Double-Consume)  
- [ ] Zu wenig Material → Craft blockiert, kein Partial-Mess  
- [ ] F1/F2 per Config einzeln abschaltbar  
- [ ] `mod.json` Version ≥ `0.1.0`  
- [ ] Offene `TODO(VERIFY)` sind gelistet, nicht versteckt  

---

## Git / Repo-Hygiene

- Kleine, sinnvolle Commits mit klarer Message (Englisch oder Deutsch, konsistent).  
- Nicht force-pushen.  
- Keine generierten Dumps/Binaries.  
- Wenn du committen sollst und unsicher bist: Änderungen staged lassen und kurz zusammenfassen.

---

## Startkommando an dich (Claude)

```
Implement PalStorageManager v1 strictly per CLAUDE.md + docs/design/PSEUDOCODE_v1.md
+ docs/design/FEATURE_SPEC_v1.md.

TARGET PLATFORM: Xbox PC Game Pass / Microsoft Store Palworld 1.0 (WinGDK).
NOT Steam-primary. Use Pal/Binaries/WinGDK for install/deploy docs and defaults.
No Steam Workshop packaging.

Order: bootstrap → F2 weight → storage index → F1 craft hooks.
Verify all UE4SS/Palworld 1.0 paths; never invent final hook paths.
Fail soft. No feature creep. Keep module file layout from the pseudocode.
```

Wenn etwas in Spec/Pseudocode unklar ist: **kleinste sinnvolle Annahme treffen, in `research/notes/` dokumentieren**, weiterbauen — nicht blockieren und nicht still raten.

---

## Kontakt zum bestehenden Scaffold

| Existiert bereits | Aktion |
| --- | --- |
| Ordnergerüst, `.gitignore`, LICENSE | Beibehalten |
| `Scripts/main.lua` (leer/Header) | Ersetzen durch echten Bootstrap |
| `enabled.txt`, `mod.json` | Behalten / Version updaten |
| Design-Docs | Nicht löschen; bei Abweichung Spec anpassen + begründen |

**Los.**
