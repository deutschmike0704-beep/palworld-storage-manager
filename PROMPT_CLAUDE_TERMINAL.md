# Claude Terminal — Full Development Prompt

> **Usage:** Open this repo in Claude Terminal / Claude Code.  
> Paste **everything inside the box below** as the first user message  
> (or: `Read PROMPT_CLAUDE_TERMINAL.md and execute the prompt in § PASTE`).

---

## PASTE (copy from here)

```
# Mission: Ship PalStorageManager v1 end-to-end

You are a senior Palworld / UE4SS Lua modder and systems engineer with full agency in this repository. Your job is not a partial scaffold — you own the **complete development loop** for v1: implement → run/verify → debug → fix → retest → document → (commit when stable).

Work until v1 is **actually done** or you hit a hard external blocker (missing game install, no dump access, etc.). Do not stop at "here's what you should do next" unless blocked by something only the human can provide.

---

## 0) Read first (mandatory, in order)

1. `CLAUDE.md`                          ← authority: platform, rules, DoD, order
2. `docs/design/PSEUDOCODE_v1.md`       ← module layout + algorithms
3. `docs/design/FEATURE_SPEC_v1.md`     ← full spec, hooks strategy, test matrix
4. `docs/architecture/overview.md`      ← repo map
5. Existing tree under `src/PalStorageManager/`

Treat `CLAUDE.md` as law for process and platform. Treat Spec + Pseudocode as product law. If anything conflicts: **CLAUDE.md (platform/process) > FEATURE_SPEC > PSEUDOCODE > older scaffold comments**.

---

## 1) Product target (do not renegotiate)

### Platform
- **PRIMARY:** Palworld **1.0** on **Xbox PC Game Pass / Microsoft Store (WinGDK)**
- Binary dir: `Pal/Binaries/WinGDK/` (NOT Steam `Win64` as default)
- UE4SS: **manual** install; no Steam Workshop packaging
- Deploy: `src/PalStorageManager/` → `…/WinGDK/ue4ss/Mods/PalStorageManager/`  
  (also document fallback `…/WinGDK/Mods/` if UE4SS layout differs)
- Steam compatibility is nice-to-have only — never block on it

### Features (v1 only — no scope creep)
| ID | Feature | Required behavior |
|----|---------|-------------------|
| **F1** | Unified craft storage | At workbenches/craft stations, materials from **all storage containers of the current base** (+ optional player inventory) are counted **and consumed** from those containers |
| **F2** | Unlimited weight in base | While player is **inside own base camp**, max carry weight ≈ `1_000_000`; restore vanilla on leave |

Out of scope: inventory sort, auto-deposit, UI rewrites, guild-wide multi-base (only config hook, default off), chest slot multipliers, shipping UE4SS in-repo, cheats outside base.

### Non-negotiable engineering rules
1. Never invent final UFunction/class paths — verify via dump/live introspection OR mark `TODO(VERIFY)` and fail-soft (disable feature + clear log).
2. F1 requires **both** availability count **and** consume; after our consume, **prevent vanilla double-consume**.
3. Fail-soft: missing API → log `[PalStorageManager][error|warn]…`, disable feature, **no crash loops**.
4. Modular files per pseudocode — no 2k-line `main.lua`.
5. Code identifiers/comments English; user docs may be German.
6. Respect `.gitignore` — no dumps, paks, game binaries, secrets.
7. Game Pass first in all paths, README, `.env.example`, deploy notes.

---

## 2) How you must work (use full capacity)

### Agency
- You may create/edit any project files needed under this repo.
- Prefer implementing over proposing. Prefer diagnosing with evidence over guessing.
- Use the full tool surface: read, search, edit, run shell, multi-file refactors, iterative test cycles.
- Parallelize independent work when useful (e.g. F2 weight + config/logger scaffolding).
- Keep a living checklist (todo) and mark steps complete as you go.

### Implementation order (strict)
```
STEP 1  Bootstrap: main.lua, config loader, logger — loads clean, prints init
STEP 2  F2 weight-in-base (smoke test that UE4SS pathing works)
STEP 3  Debug: list containers in base (logged)
STEP 4  StorageIndex + CountAvailable (log-only first)
STEP 5  Craft availability hooks → UI combined counts
STEP 6  Craft consume hooks + double-consume prevention
STEP 7  Config flags, hardening, mod.json ≥ 0.1.0, README Game Pass install
STEP 8  Test matrix from FEATURE_SPEC §11 — document results / known gaps
```

After each step the mod must remain **loadable** (fail-soft if incomplete).

### Target module layout
```
src/PalStorageManager/
  enabled.txt
  mod.json
  config/                    # optional user overrides
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

### API verification protocol
If no SDK dump is in the workspace:
1. Search public knowledge + any local notes carefully; still treat names as hypotheses.
2. Implement behind thin adapter modules (`core/*`, `hooks/*`) so paths are easy to swap.
3. Prefer log-only hooks first, then behavior change.
4. Write verified findings to `research/notes/verified-hooks.md` (paths, why chosen, risk).
5. Unverified paths stay `TODO(VERIFY)` and features soft-disable rather than hard-crash.

If the human's game path is available via `.env` / env vars, use it for deploy scripts. If not, implement deploy tooling + document exact Game Pass steps anyway.

---

## 3) Testing, debugging, fixing (mandatory loop)

You own QA for this module as far as the environment allows.

### A) Static / repo checks (always)
- File structure matches layout
- `enabled.txt` present
- `mod.json` valid JSON, version bumped when features land
- No syntax-obvious Lua errors (balanced blocks, requires resolve)
- Config defaults match CLAUDE.md
- README install path is **WinGDK / Game Pass**

### B) Runtime strategy (when game + UE4SS available)
1. Deploy mod to Game Pass `WinGDK` Mods path
2. Launch game, capture `UE4SS.log` / mod prints
3. Smoke:
   - Mod init line appears
   - F2: enter base → overweight gone; leave → vanilla returns
   - F1: materials only in distant chest still craftable; stacks decrease correctly; no double drain
4. On failure: binary-search — disable F1/F2 via config, isolate hook, add debug logs, fix, retest
5. Never "fix" by deleting safety checks or silencing errors without root cause

### C) When game is NOT available in this environment
Still complete:
- Full implementation skeleton + best-effort real hooks with adapters
- `docs/guides/TESTING_GAMEPASS.md` with exact click-path + expected logs
- `research/notes/verified-hooks.md` OR honest `TODO(VERIFY)` list
- Self-review pass: re-read your own code for double-consume, nil guards, throttle, authority notes
- Dry-run any packaging/deploy scripts you add

### D) Debug discipline
- Structured logs: `[PalStorageManager][debug|info|warn|error]`
- Temporary debug must be toggleable via `log_level` or removed before "done"
- Reproduce → hypothesize → instrument → fix → confirm → remove noise
- Track regressions: if F2 breaks while doing F1, fix F2 before continuing

### E) Error fixing bar
You do not leave known broken states. For every failure you introduce or find:
1. State the symptom
2. Find root cause
3. Patch
4. Re-verify the surrounding test cases
5. Note residual risk if any

---

## 4) Documentation deliverables (part of Done)

Update as you implement:
- `README.md` — Game Pass install, features, config, troubleshooting (UE4SS not loading, wrong Mods path, post-update reinstall)
- `mod.json` — version ≥ `0.1.0` when F1+F2 code exists
- `research/notes/verified-hooks.md` — real paths / TODOs
- `docs/guides/TESTING_GAMEPASS.md` — manual test script for the human
- Optional: short `docs/changelog/` entry for 0.1.0

---

## 5) Definition of Done (all must pass or be explicitly blocked)

- [ ] Loads under UE4SS on Game Pass/WinGDK path design without error spam
- [ ] F2 behavior implemented + restore on leave
- [ ] F1 count + consume across all current-base storages
- [ ] No double-consume design (vanilla path skipped/neutralized after our consume)
- [ ] Insufficient materials → fail cleanly, no partial mess when preventable
- [ ] F1/F2 independently disableable via config
- [ ] Fail-soft on missing APIs
- [ ] README + testing guide are Game Pass correct
- [ ] `TODO(VERIFY)` items listed, not hidden
- [ ] Self-review completed; obvious bugs fixed

If blocked (e.g. cannot run game here): implement everything possible, leave a crisp **BLOCKED** section with exact human steps to unblock, and still finish code + docs + test plan.

---

## 6) Git hygiene

- Prefer small logical commits when you finish a STEP (English commit messages OK)
- Do **not** force-push
- Do **not** commit dumps, binaries, secrets, `UE4SS.log`, `.env`
- If push credentials/network fail, leave commits local and report

---

## 7) Communication style while working

- Be concise in status updates: what you did, what broke, what you fixed next
- Do not ask permission for routine edits inside the repo
- Ask the human only when you need something external:
  - actual Game Pass install path on their machine
  - UE4SS.log after a test run
  - confirmation of crash after a specific step
- When finished: summary of files changed, how to install on Game Pass, how to test F1/F2, remaining TODOs

---

## 8) Start now

1. Read the mandatory docs
2. Create the todo checklist from STEPs 1–8
3. Begin STEP 1 immediately
4. Continue autonomously through the loop until DoD or hard block

Go.
```

---

## PASTE end

### Optional one-liner follow-ups (after first run)

**If Claude stops early:**
```
Continue. Do not summarize a plan — execute remaining STEPs until DoD or hard block. Fix any regressions you introduced.
```

**If human provides a test log:**
```
Here is UE4SS.log / behavior from Game Pass. Diagnose root cause, patch, re-check F1/F2, update research/notes if hook paths change.
<paste log>
```

**If only F2 should ship first:**
```
Prioritize F2 to fully Done (including tests/docs), then continue F1. Keep F1 fail-soft disabled until consume path is safe.
```
