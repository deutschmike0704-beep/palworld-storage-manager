# Manueller Testplan — Game Pass (WinGDK)

Ziel: PalStorageManager v0.1.0 auf der **Xbox PC Game Pass**-Version von
Palworld 1.0 verifizieren. Ergebnis bitte je Test mit ✅/❌ + `UE4SS.log`-
Ausschnitt festhalten (Log liegt neben der Shipping-EXE unter
`Pal/Binaries/WinGDK/` bzw. im `ue4ss/`-Unterordner).

## 0) Installation

1. UE4SS (Palworld-kompatible/experimental Build) **manuell** nach
   `<Root>/Pal/Binaries/WinGDK/` installieren (`dwmapi.dll` + `ue4ss/`).
   Typischer Root: `C:\XboxGames\Palworld\Content`.
2. Mod deployen — entweder `tools/deploy/deploy.ps1` (liest `.env`,
   erkennt `ue4ss\Mods` vs. `Mods` automatisch) oder Zip aus
   `tools/packaging/package.sh` in den Mods-Ordner entpacken.
3. Spiel über die Xbox App starten, Spielstand laden.

**Erwartete Log-Zeilen (Smoke-Test, immer):**

```
[PalStorageManager][info] PalStorageManager v0.1.0 bootstrap (Palworld 1.0, Game Pass/WinGDK primary)
[PalStorageManager][info] init complete
```

Kein `[error]`-Spam, kein Crash-Loop. Je nach Hook-Verifikationsstand außerdem:

- `F2 weight hook active: …` **oder** `F2 weight-in-base DISABLED: … TODO(VERIFY) …`
- `F1 unified craft storage SOFT-DISABLED: unverified hook paths …` (erwartet in 0.1.0)

❗ Wenn gar nichts loggt: falscher Mods-Pfad (WinGDK vs. Win64, `ue4ss/Mods`
vs. `Mods`) oder UE4SS lädt nicht — siehe README Troubleshooting.

## 1) F2 — Unlimited Weight in Base

Voraussetzung: `F2 weight hook active` im Log. Falls DISABLED → erst Hook
per API-Dump verifizieren (Abschnitt 3).

| # | Schritt | Erwartung |
| --- | --- | --- |
| W1 | Inventar deutlich über Vanilla-Limit füllen, eigene Base betreten | Log `F2: entered own base`; kein Overweight (Sprinten/Springen geht) |
| W2 | Base verlassen | Log `F2: left base`; Overweight-Penalty wieder aktiv |
| W3 | In der Base Statuspunkt auf Gewicht setzen | Buff bleibt aktiv (kein Flackern) |
| W4 | Aus der Base heraus teleportieren (Fast Travel) | Vanilla-Limit spätestens nach ~0.25 s (Poll-Intervall) |
| W5 | `weight.enabled = false` in user.lua, Neustart | Kein F2-Log, Vanilla-Verhalten überall |

Randfall: Fremde Base betreten (Multiplayer/Koop) → **kein** Buff, sofern
Gruppen-APIs aufgelöst sind; sonst greift `assume_own_base_when_unverified`
(Standard true — für Singleplayer korrekt, Log-Hinweis erscheint einmalig).

## 2) F1 — Unified Craft Storage

In 0.1.0 ist F1 **absichtlich soft-disabled**, bis `count_hook`/`consume_hook`
aus dem eigenen 1.0-Dump verifiziert sind (keine geratenen Pfade, CLAUDE.md
Regel 1). Reihenfolge:

### 2a) Container-Discovery prüfen (ohne Hooks, gefahrlos)

1. `debug.log_index_summary = true` in `Scripts/config/user.lua`.
2. In der Base stehen, Log beobachten:
   `F1[log-only]: unified pool = N item type(s), M stack(s), U unit(s) across K container(s)`
3. K muss der Kistenzahl der Base entsprechen; Kisten einer **anderen** Base
   dürfen nicht mitzählen (C5). Zählt K = 0 → Container-Modellklasse per
   API-Dump (Abschnitt 3) korrigieren (`api.craft.container_model_classes`).

### 2b) Nach Hook-Verifikation (user.lua: `api.craft.count_hook/consume_hook`)

| # | Szenario | Erwartung |
| --- | --- | --- |
| C1 | Wood nur in weit entfernter Kiste der Base | Craft-UI zeigt Menge, Craft läuft |
| C2 | Material über 3 Kisten verteilt | Abzüge korrekt über alle Kisten, Summen stimmen |
| C3 | Insgesamt zu wenig Material | Craft blockiert; **keine** Teilabzüge |
| C4 | 10× hintereinander craften | Kein Doppelabzug; Bestände exakt |
| C5 | Kiste in fremder/entfernter Base | Wird nicht einbezogen |
| C6 | Material liegt in Reichweite der Werkbank (Vanilla hätte es gefunden) | Genau EIN Abzug (Vanilla zahlt, Mod steht still — `vanilla_fallback`) |

C6 ist der Doppel-Consume-Kerntest: vorher/nachher Bestände exakt zählen.

## 3) API-Dump fahren (Verifikations-Workflow)

1. In der Base stehen, **F6** drücken (oder `debug.dump_apis_on_init = true`).
2. `UE4SS.log` → alle `DUMP …`-Zeilen kopieren nach
   `research/notes/verified-hooks.md`.
3. Kandidaten für F1 im Dump/CXXHeaderDump suchen:
   `Craft`, `Product`, `Material`, `Ingredient`, `RequiredItem`, `Convert`,
   `ItemContainer`, `RemainNum`.
4. Verifizierte Pfade in `user.lua` eintragen, Spiel neu starten, 2b testen.

## 4) Regression / Stabilität

- 15 Minuten normal spielen (Base-Arbeit, Craften, Kämpfen): kein
  `[PalStorageManager][error]`-Spam, keine FPS-Auffälligkeit (Index ist
  gecacht, 0.5 s TTL; Weight-Poll 0.25 s).
- Spiel beenden/neu laden: Mod initialisiert erneut sauber.
- Nach Game-Pass-Update: Mods-Ordner prüfen (Updates können UE4SS/Mods
  entfernen) und ggf. neu deployen.
