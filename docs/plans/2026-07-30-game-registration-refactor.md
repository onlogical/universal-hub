# Game Registration Architecture Refactor Implementation Plan

**Goal:** Replace Universal Hub's duplicated game-registration and remote-source inventories with a validated, deterministic game-definition catalog while preserving all current game behavior and keeping Limn and Hydroxide behind their stable seams.

**Architecture:** `games/Catalog.lua` is the single ordered inventory of pure game-definition modules. `modules/Registry.lua` validates and resolves those definitions, `init.lua` composes only the selected definition, and `hub.lua` performs a staged catalog/definition/source fetch without inventing a plugin framework. Limn remains the drawing/input runtime and Hydroxide remains the Targeting/Closure/Lifecycle runtime; Universal Hub retains all panels, state, persistence, game behavior, and presentation ownership.

**Tech Stack:** Luau, Lune contract tests, luau-lsp strict analysis, Limn packaged runtime, Hydroxide Targeting/Closure/Lifecycle, Git.

---

## Non-negotiable seams

### Limn

- Limn owns retained/immediate drawing primitives, Canvas/Element lifetimes, primitive probing, hit testing, Z-order, pointer capture, processed-input policy, coordinate mapping, signals, and cleanup.
- Universal Hub owns shell and game panels, controls, themes, layout, state, persistence, feature registration, and game views.
- Universal Hub may receive a narrow Limn runtime or presentation host but must not reach into Limn internals, depend directly on raw `Drawing`, or add a Limn panel/control registration system.
- The packaged `vendor/Limn.lua` must match the clean Limn distribution supplied through `LIMN_ROOT`; it is never reconstructed from another worktree.

### Hydroxide

- The supported Universal Hub dependency surface is Hydroxide Targeting, Closure, and Lifecycle.
- Load those modules only through the published `modules/Helpers.lua` `Helpers.load` surface, using a Universal Hub-owned cache and namespace.
- Local loading gives `Helpers.load` an importer rooted at `UniversalHubConfig.HydroxideRoot`. Packaged remote loading gives it an independent importer backed by a deterministic, pinned Hydroxide source map.
- Never execute `hydroxide/init.lua`, install or replace `environment.oh`, route Hydroxide paths through the Universal Hub importer, or load Hydroxide Drawing, controls, methods, Remote, or game helpers.
- Shared use is limited to observation/projection/bounds/visibility, `nearestObservation` and default selection, `getCharacterHitboxParts`, `predictIntercept`, generic closure introspection, and lifecycle cleanup.
- Hydroxide Drawing and controls are unsupported and must disappear from Universal Hub composition.
- Game/place registration, opponent eligibility, non-player enumeration, observation decoration, sticky/custom targeting, hitbox revalidation, remotes, effects, movement, cosmetics, and game-specific raycast-ignore contents stay game-local.

### Existing `raycastIgnore` behavior

Do not add a new Universal Hub dependency on an unpublished Hydroxide `raycastIgnore` change. Preserve these existing call sites and their current tests unchanged unless the manager provides a published stable requirement:

- `games/Counterblox.lua:502`: spectator character ignore list passed to targeting selection.
- `games/Counterblox.lua:1258`: spectator character ignore list passed to observation.
- `games/rivals/Adapter.lua:814`: smoke-effect ignore list passed to targeting selection.
- `tests/counterblox_adapter_contracts.luau:929` and `tests/rivals_adapter_contracts.luau:2367`: current behavior contracts.

If the stable Hydroxide surface cannot honor the already-present option, stop before changing behavior and report the missing cross-project requirement.

### Scope

- Keep the interface explicit and small. Do not add a plugin framework, schema language, dependency-injection container, or Limn widget library.
- Preserve RIVALS Gun Game, Town resumable checkpoint/copy behavior, loader/site behavior, README/icon content, adapter ids, config paths and keys, `environment.UniversalHubSettings`, `UniversalHubSession`, Town checkpoint schema, capability gating, and `overlay.controls`.
- Do not begin Phase 4 until the manager explicitly approves it after reviewing this plan.
- Interpret "definition owns ordered UI panel registration" as a final-state requirement completed in Phase 4. Phase 2 may name a presentation module path only when that module exists and is used; it must not move or duplicate panel registration before the UI gate.

## Target interfaces

### Pure catalog

`games/Catalog.lua` returns the only ordered list of definition module paths:

```lua
return {
    "games/counterblox/Definition",
    "games/rivals/Definition",
    "games/town/Definition",
}
```

The order is stable for discovery and diagnostics, not a hidden tie-breaker. `Registry:Resolve` rejects an equal highest score explicitly.

### GameDefinition

Each pure `Definition.lua` returns data with this narrow shape:

```lua
export type GameDefinition = {
    id: string,
    label: string,
    manifest: {
        gameIds: { number }?,
        placeIds: { number }?,
    },
    module: string?,
    factory: ((context: any) -> any)?,
    sources: { string },
    defaults: { [string]: any },
    initialState: { [string]: any },
    features: {
        capabilities: { string },
        cosmetics: boolean?,
        exclusions: { [string]: { string } }?,
        optionLabels: { [string]: string }?,
    },
    hydroxide: {
        Targeting: boolean?,
        Closure: boolean?,
        Lifecycle: boolean?,
    },
    presentation: string?,
}
```

Rules:

- `id` and `label` are non-empty stable strings.
- `manifest` is a table containing at least one numeric `gameIds` or `placeIds` entry.
- Exactly one of `module` or `factory` is present. Production definitions use `module`; contract tests may use `factory`.
- `sources` is an ordered, duplicate-free list of import paths without `.lua`. For a production definition it includes `module` and every game-local module imported by that adapter. Callers actually use it for remote discovery.
- `defaults`, `initialState`, `features`, and `hydroxide` are tables. Existing values move from `init.lua` or adapter headers without semantic changes.
- `presentation` is absent until its Phase 4 module exists and is registered through the Universal Hub presentation host.
- Definitions contain no services, callbacks, raw `Drawing`, Limn objects, remote instances, or behavior.

`Registry:Register(definition)` validates the definition, rejects a duplicate id, preserves insertion order for diagnostics, and returns the definition. `Registry:Resolve(context)` preserves place score `200` over universe score `100`; a custom numeric/boolean `match` remains supported only for compatibility. If two definitions share the highest positive score, it raises an error naming the score and sorted ids. `Registry:List()` remains id-sorted for compatibility.

## Commit map

1. `Document game registration refactor plan`
2. `Integrate Limn consumer runtime`
3. `Validate game definitions in registry`
4. `Move game metadata into catalog definitions`
5. `Drive remote sources from game catalog`
6. `Move game panels behind presentation host` — manager-gated Phase 4 only.
7. `Close packaged game source scopes` — independent-review correction.
8. `Replace the presentation host monolith` — independent-review correction.
9. `Compose sparse game definitions locally` — independent-review correction.
10. `Split game lifecycles along owned boundaries` — only after screenshot parity and only where failing contracts prove it is needed.

Each commit must contain its direct tests and must pass its phase checks before the next commit begins. Do not push, open a PR, merge, publish, or mutate Roblox without explicit manager follow-up.

## Task 0: Confirm the isolated starting gate

**Files:** none.

**Step 1: Verify branch and worktree isolation**

Run:

```bash
git status --short
git branch --show-current
git rev-parse HEAD
git rev-parse origin/main
git merge-base --is-ancestor acdeb9e93027e708b21342ca96ffac6ce3ec21da origin/main
git merge-base --is-ancestor origin/main HEAD
```

Expected:

- Worktree is clean.
- Branch is `codex/game-registration-refactor`.
- `origin/main` is `acdeb9e93027e708b21342ca96ffac6ce3ec21da` or a newer descendant.
- Both ancestry checks exit `0`.

Stop if any condition fails. Do not source files from `C:\git\universal-hub`, its `local/` junction, or another worktree.

## Task 1: Integrate Limn and scoped Hydroxide helpers semantically

**Files:**

- Import unchanged from `9ab0176c54d85945012e6d53ab3bc16e26675f1a`: `.gitattributes`
- Import unchanged from `9ab0176c54d85945012e6d53ab3bc16e26675f1a`: `vendor/Limn.lua`
- Modify semantically from `9ab0176c54d85945012e6d53ab3bc16e26675f1a`: `DESIGN.md`
- Preserve current-main content and update only runtime wording when necessary: `README.md`
- Preserve current-main nested guidance and update only the runtime seam: `games/rivals/AGENTS.md`
- Modify semantically: `games/Counterblox.lua`
- Modify semantically while retaining Gun Game/pickup behavior: `games/rivals/Adapter.lua`
- Modify semantically: `games/rivals/Effects.lua`
- Modify semantically: `games/Town.lua`
- Modify semantically: `hub.lua`
- Modify semantically: `init.lua`
- Preserve current loader UX unless a contract requires a scoped change: `loader.lua`
- Modify semantically while preserving fresh cached Universal Hub imports and Town nested imports: `local.lua`
- Modify semantically from the Limn consumer implementation: `modules/Overlay.lua`
- Modify semantically: `modules/Session.lua`
- Modify: `scripts/check.sh`
- Modify failing-first: `tests/hub_loader_contracts.luau`
- Create failing-first from the Limn contract intent: `tests/limn_consumer_contracts.luau`
- Modify failing-first: `tests/local_loader_contracts.luau`
- Modify failing-first: `tests/overlay_contracts.luau`
- Modify only for preserved packaged-loader behavior: `tests/remote_loader_contracts.luau`
- Modify only for Limn canvas/runtime injection: `tests/counterblox_adapter_contracts.luau`
- Modify only for Limn canvas/runtime injection while preserving Gun Game tests: `tests/rivals_adapter_contracts.luau`
- Modify only for Limn canvas/runtime injection: `tests/town_adapter_contracts.luau`
- Modify failing-first: `tests/session_contracts.luau`

**Resolved integration evidence**

The wholesale `9ab0176` cherry-pick was rejected because it conflicts with current-main behavior:

- `local.lua`: current main installs a fresh path-validated cached `UniversalHubConfig.Import`; `9ab0176` cleared it.
- `tests/local_loader_contracts.luau`: current main proves nested Town imports and full-Hydroxide reload behavior; `9ab0176` expected Targeting-only loading and no unrelated session exit.
- `tests/hub_loader_contracts.luau`: current main and `9ab0176` encode different dependency inventories.
- `README.md`: current main owns the showcase/site/icon/loader UX while `9ab0176` carried older raw-loader copy.

The manager resolved these conflicts as the composition below. Do not cherry-pick `9ab0176` again.

**Step 1: Write failing local-loader contracts**

Update `tests/local_loader_contracts.luau` to assert:

- every bootstrap overwrites a stale Universal Hub `configuration.Import` with the current-main path-validated cached local importer;
- nested Town imports resolve through that Universal Hub importer exactly once;
- `configuration.LimnPath` defaults to `limn/dist/Limn.lua`;
- local Hydroxide loading reads `modules/Helpers.lua` and only the selected definition's stable Targeting/Closure/Lifecycle leaf modules from `HydroxideRoot`;
- `Helpers.load` receives its own importer/cache/namespace and never receives the Universal Hub importer;
- `hydroxide/init.lua` is never read or executed and `environment.oh` is neither installed nor replaced;
- unrelated `oh.Resources` sessions are never exited;
- a legacy bridge exits only a provably matching old Universal Hub session and has a separate unrelated-`oh` no-exit contract;
- duplicate bootstraps coalesce without duplicated dependency or hub loads.

Run:

```bash
lune run tests/local_loader_contracts.luau
```

Expected: FAIL because current `local.lua` executes `hydroxide/init.lua`, does not load Limn, and does not use scoped `Helpers.load`.

**Step 2: Write failing packaged-loader and session contracts**

Update `tests/hub_loader_contracts.luau`, `tests/session_contracts.luau`, and `tests/limn_consumer_contracts.luau` to assert:

- packaged remote fetches the pinned vendored Limn source, pinned `modules/Helpers.lua`, and pinned Targeting/Closure/Lifecycle leaves deterministically before `init.lua`;
- the Hydroxide source-map importer is independent of `configuration.Import` and cannot resolve Universal Hub paths;
- packaged loading never fetches or executes `hydroxide/init.lua` or Drawing/controls/methods/Remote;
- dependencies are compiled and validated before the existing `UniversalHubSession` is stopped;
- the previous Universal Hub session stops before any new Limn/UI/game resource is created;
- `UniversalHubSession` owns Limn, adapter, overlay, store, input, and loaded Lifecycle scope stops;
- startup failure unwinds new resources in reverse order without exiting an unrelated Hydroxide session;
- Limn is the only drawing/input runtime and game packages receive only the runtime/canvas seam, never raw `Drawing` or `LimnPath`;
- existing `raycastIgnore` values are passed through unchanged.

Run:

```bash
lune run tests/hub_loader_contracts.luau
lune run tests/session_contracts.luau
lune run tests/limn_consumer_contracts.luau
```

Expected: FAIL on missing pinned Limn/Helpers loading, scoped session ownership, or Limn consumer behavior.

**Step 3: Implement local and packaged dependency staging**

In `local.lua`:

- retain current-main `configuration.Import` validation, cache, and nested game-module behavior;
- overwrite a stale importer on each accepted bootstrap and never clear it;
- load Limn from `configuration.LimnPath`;
- load `modules/Helpers.lua` from `configuration.HydroxideRoot`;
- give `Helpers.load` an independent Hydroxide-root importer, cache, and Universal Hub namespace;
- stage and validate Limn plus required stable helpers without setting `environment.oh`.

In `hub.lua`:

- fetch pinned `vendor/Limn.lua`;
- prefetch pinned Hydroxide `modules/Helpers.lua`, Targeting, Closure, and Lifecycle into a separate source map;
- give `Helpers.load` a source-map importer that cannot resolve Universal Hub paths;
- keep the existing eager Universal Hub/game source list in Phase 0; catalog-driven source discovery remains Task 4;
- stage and validate all dependency chunks before executing `init.lua`.

Do not add network-lazy game fetching in Phase 0.

**Step 4: Integrate the Limn consumer runtime**

Semantically port the Limn Canvas/Element, probing, input mapping/processed policy, pointer capture, render, and cleanup behavior from `9ab0176` into `modules/Overlay.lua`, adapter canvas use, and `init.lua`.

Composition order:

1. resolve the current adapter definition without creating resources;
2. load only the stable Hydroxide modules declared by that definition;
3. validate Limn and helper surfaces;
4. stop the previous exact Universal Hub session;
5. create Limn, UI, store, adapter, and session resources;
6. register Lifecycle scope stops with the Universal Hub session;
7. on failure, unwind newly created resources in reverse order.

Do not pass raw `Drawing`, `DrawingImmediate`, or `LimnPath` to game packages. Only the composition root may use executor drawing globals to construct Limn.

**Step 5: Preserve merged-main behavior and documentation**

Verify:

- RIVALS Gun Game place support, pickups, priority, and final-knife behavior/tests remain.
- Town checkpoint, resumable large-copy, nested imports, and second-review behavior/tests remain.
- `site/`, README showcase/icon/bootstrap UX, loader UX, and nested `games/rivals/AGENTS.md` guidance are retained.
- no code executes `hydroxide/init.lua`, replaces `environment.oh`, or reaches Hydroxide Drawing/controls.
- existing `raycastIgnore` call sites and tests are unchanged in meaning.

**Step 6: Run the baseline validation**

```bash
lune run tests/local_loader_contracts.luau
lune run tests/hub_loader_contracts.luau
lune run tests/session_contracts.luau
lune run tests/limn_consumer_contracts.luau
lune run tests/overlay_contracts.luau
lune run tests/counterblox_adapter_contracts.luau
lune run tests/rivals_adapter_contracts.luau
lune run tests/town_adapter_contracts.luau
HYDROXIDE_ROOT=C:/git/hydroxide LIMN_ROOT=C:/git/limn ./scripts/check.sh
git diff --check
```

Expected: focused contracts and full validation pass, packaged Limn matches the pinned distribution, and `git diff --check` exits `0`. Roblox live QA remains deferred because this phase has no authorization to mutate Roblox.

**Step 7: Commit**

```bash
git add .gitattributes DESIGN.md README.md games/rivals/AGENTS.md games/Counterblox.lua games/rivals/Adapter.lua games/rivals/Effects.lua games/Town.lua hub.lua init.lua loader.lua local.lua modules/Overlay.lua modules/Session.lua scripts/check.sh tests/hub_loader_contracts.luau tests/limn_consumer_contracts.luau tests/local_loader_contracts.luau tests/overlay_contracts.luau tests/remote_loader_contracts.luau tests/counterblox_adapter_contracts.luau tests/rivals_adapter_contracts.luau tests/town_adapter_contracts.luau tests/session_contracts.luau vendor/Limn.lua
git commit -m "Integrate Limn consumer runtime"
```

Expected: one semantic integration commit with no registry/catalog refactor and no panel ownership move.

## Task 2: Add failing-first GameDefinition registry contracts

**Files:**

- Modify: `tests/registry_contracts.luau`
- Modify: `modules/Registry.lua`
- Modify: `scripts/check.sh` only if the test command is not already present.

**Step 1: Write failing contracts**

Add table-driven assertions that `Registry:Register` rejects:

- non-table values;
- missing, empty, or non-string `id`;
- missing, empty, or non-string `label`;
- missing/non-table manifests;
- manifests without a numeric game or place id;
- definitions with neither or both `module` and `factory`;
- production `module` definitions with missing, non-table, duplicate, non-string, or `.lua`-suffixed `sources`;
- a `module` not included in `sources`;
- missing/non-table `defaults`, `initialState`, `features`, or `hydroxide`;
- duplicate ids without overwriting the first definition.

Also assert:

- place score `200` beats universe score `100`;
- `true`, `false`, and numeric custom `match` compatibility;
- unsupported contexts return `nil, 0`;
- `List()` remains id-sorted;
- equal highest scores raise a deterministic error containing the score and sorted ids, independent of registration order.

**Step 2: Run the focused test and prove red**

```bash
lune run tests/registry_contracts.luau
```

Expected: FAIL on the first new validation or ambiguity contract.

**Step 3: Implement the minimum registry change**

In `modules/Registry.lua`:

- add local validation helpers;
- store definitions by id and preserve a registration-order array;
- reject duplicates rather than overwriting;
- collect all highest-scoring matches;
- sort tied ids only for the diagnostic and raise explicitly;
- preserve the existing `Resolve` return and id-sorted `List` behavior.

Do not import modules or know about Limn/Hydroxide in Registry.

**Step 4: Run focused and full checks**

```bash
lune run tests/registry_contracts.luau
HYDROXIDE_ROOT=C:/git/hydroxide LIMN_ROOT=C:/git/limn ./scripts/check.sh
git diff --check
```

Expected: focused contract prints `registry-contracts-ok`; full check prints `universal-hub-check-ok`.

**Step 5: Commit**

```bash
git add modules/Registry.lua tests/registry_contracts.luau scripts/check.sh
git commit -m "Validate game definitions in registry"
```

## Task 3: Move game metadata into pure definitions and one catalog

**Files:**

- Create: `games/Catalog.lua`
- Create: `games/counterblox/Definition.lua`
- Create: `games/rivals/Definition.lua`
- Create: `games/town/Definition.lua`
- Create: `tests/catalog_contracts.luau`
- Modify: `games/Counterblox.lua`
- Modify: `games/rivals/Adapter.lua`
- Modify: `games/Town.lua`
- Modify: `init.lua`
- Modify: `scripts/check.sh`
- Modify only when required to preserve existing metadata contracts: `tests/counterblox_adapter_contracts.luau`
- Modify only when required to preserve existing metadata contracts: `tests/rivals_adapter_contracts.luau`
- Modify only when required to preserve existing metadata contracts: `tests/town_adapter_contracts.luau`

**Step 1: Write failing catalog contracts**

`tests/catalog_contracts.luau` must load the pure catalog and definitions without Roblox globals and assert:

- catalog order is exactly Counterblox, RIVALS, Town;
- ids/labels/manifests still resolve the current three games and RIVALS Gun Game place;
- production definitions name their current adapter module;
- each declared source is unique and every adapter game-local import is declared;
- Counterblox, RIVALS, and Town capability lists, option labels, exclusions, cosmetics flag, defaults, and initial state equal current behavior;
- Town config/checkpoint roots and state schema remain unchanged;
- Hydroxide requirements contain only Targeting/Closure/Lifecycle;
- definitions do not contain functions, Roblox instances/services, Limn values, raw Drawing, or undeclared module paths.

Add a current-three-game selection block to `tests/registry_contracts.luau` or this catalog test using the real definitions.

**Step 2: Run focused tests and prove red**

```bash
lune run tests/catalog_contracts.luau
lune run tests/registry_contracts.luau
```

Expected: FAIL because `games/Catalog.lua` and definition files do not exist.

**Step 3: Create the pure catalog and definitions**

Move only metadata from `init.lua` and adapter table headers. Keep behavior and constructors in:

- `games/Counterblox.lua`
- `games/rivals/Adapter.lua`
- `games/Town.lua`

Adapter modules return behavior/factory surfaces without duplicating definition metadata. The definition's `sources` list declares:

- Counterblox: `games/Counterblox`
- RIVALS: `games/rivals/Adapter`, `Targeting`, `ProjectileAim`, `ShotPresentation`, `ScopedAccuracy`, `WeaponPolicy`, `Effects`, `Movement`, and `CombatState`
- Town: `games/Town`, `games/town/Canonical`, `CheckpointStore`, `CopyEngine`, `CopyPlan`, and `ExecutionPlan`

Keep `games/town/CheckpointStore` available to composition without changing its schema.

**Step 4: Compose from the catalog**

Change `init.lua` to:

- import `games/Catalog`;
- import and register each definition path;
- resolve the current game;
- import only the selected definition's `module`;
- use definition-owned defaults, initial state, feature metadata, and Hydroxide requirements;
- keep adapter context construction, `environment.UniversalHubSettings`, `UniversalHubSession`, registry/store/session inspection, config path, and Town checkpoint behavior compatible.

Do not move panel construction, callbacks, or layout in this phase.

**Step 5: Validate**

```bash
lune run tests/catalog_contracts.luau
lune run tests/registry_contracts.luau
lune run tests/counterblox_adapter_contracts.luau
lune run tests/rivals_adapter_contracts.luau
lune run tests/town_adapter_contracts.luau
HYDROXIDE_ROOT=C:/git/hydroxide LIMN_ROOT=C:/git/limn ./scripts/check.sh
git diff --check
```

Expected: all focused tests and the full check pass with unchanged adapter behavior.

**Step 6: Commit**

```bash
git add games/Catalog.lua games/counterblox/Definition.lua games/rivals/Definition.lua games/town/Definition.lua games/Counterblox.lua games/rivals/Adapter.lua games/Town.lua init.lua scripts/check.sh tests/catalog_contracts.luau tests/registry_contracts.luau tests/counterblox_adapter_contracts.luau tests/rivals_adapter_contracts.luau tests/town_adapter_contracts.luau
git commit -m "Move game metadata into catalog definitions"
```

## Task 4: Drive remote source discovery from the catalog

**Files:**

- Modify: `hub.lua`
- Modify: `tests/hub_loader_contracts.luau`
- Create: `tests/source_inventory_contracts.luau`
- Modify: `scripts/check.sh`
- Modify only if the loader surface requires it: `tests/remote_loader_contracts.luau`
- Modify only if the local loader surface requires it: `tests/local_loader_contracts.luau`

**Step 1: Write failing source-set contracts**

Replace the `#requested == 25` style assertion in `tests/hub_loader_contracts.luau` with exact set contracts:

- Limn and required Hydroxide modules are fetched once.
- `init.lua`, `games/Catalog.lua`, and every catalog definition are fetched once.
- the union of shared sources plus every definition's `sources` is fetched exactly once;
- request order is not asserted after the staged catalog/definition bootstrap;
- unexpected and duplicate source URLs fail with a sorted diagnostic.

`tests/source_inventory_contracts.luau` must independently assert:

- catalog definition paths exist;
- every declared source path exists;
- no game adapter/helper source is absent from the catalog union;
- the catalog/definition/shared union has no duplicates;
- `hub.lua`, `init.lua`, and `scripts/check.sh` contain no duplicated three-game source inventory.

**Step 2: Run focused tests and prove red**

```bash
lune run tests/hub_loader_contracts.luau
lune run tests/source_inventory_contracts.luau
```

Expected: FAIL because `hub.lua` still contains a hard-coded game-source list and the old exact-count assertion.

**Step 3: Implement staged discovery**

In `hub.lua`:

1. fetch and validate Limn and stable Hydroxide modules;
2. fetch and execute `games/Catalog.lua`;
3. validate its ordered definition-path list;
4. fetch and execute each pure definition;
5. validate definitions with the same public Registry validation contract or a shared pure validator;
6. build an ordered de-duplicated union of shared module paths, definition paths, and declared game sources;
7. fetch each source exactly once;
8. install `configuration.Import`;
9. fetch and execute `init.lua`.

Keep the source inventory visible as pure catalog/definition data. Do not introduce recursive fetching, arbitrary remote dependencies, or a generic module resolver.

**Security stop condition:** If staged execution requires granting broader trust than the existing same-repository `loadstring` model, stop and ask the manager to choose the audit/security policy before implementation.

Update `scripts/check.sh` to derive the strict-analysis file set from tracked Luau source files or the tested catalog inventory instead of another hand-maintained game list.

**Step 4: Validate**

```bash
lune run tests/hub_loader_contracts.luau
lune run tests/source_inventory_contracts.luau
lune run tests/remote_loader_contracts.luau
lune run tests/local_loader_contracts.luau
HYDROXIDE_ROOT=C:/git/hydroxide LIMN_ROOT=C:/git/limn ./scripts/check.sh
git diff --check
```

Expected: exact source-set/uniqueness contracts pass and full validation prints `universal-hub-check-ok`.

Perform clean local-loader read-only QA in all three games before committing if the manager has authorized Roblox access.

**Step 5: Commit**

```bash
git add hub.lua scripts/check.sh tests/hub_loader_contracts.luau tests/source_inventory_contracts.luau tests/remote_loader_contracts.luau tests/local_loader_contracts.luau
git commit -m "Drive remote sources from game catalog"
```

## Task 5: Add the manager-gated presentation host

**Gate:** Do not edit any file in this task until the manager explicitly follows up after plan review.

**Expected files after approval:**

- Create: `modules/PresentationHost.lua`
- Create: `games/rivals/Presentation.lua`
- Create: `games/counterblox/Presentation.lua`
- Create: `games/town/Presentation.lua`
- Modify: `games/rivals/Definition.lua`
- Modify: `games/counterblox/Definition.lua`
- Modify: `games/town/Definition.lua`
- Modify: `modules/Overlay.lua`
- Modify: `init.lua`
- Create: `tests/presentation_host_contracts.luau`
- Modify: `tests/overlay_contracts.luau`
- Modify: `tests/catalog_contracts.luau`
- Modify: `scripts/check.sh`

**Step 1: Capture failing ownership and parity contracts**

Tests must assert:

- shared Overlay owns shell, theme, generic player/utility rendering, and the Limn Canvas/Element runtime;
- presentation modules receive only a narrow host (`panel`, generic option controls, action registration, state read/patch) and never Limn internals or raw `Drawing`;
- game definitions register presentation modules in deterministic order;
- RIVALS generic panels, then Counterblox panels, then Town recovery/copy panels are game-owned;
- `overlay.controls` remains available with current keys;
- labels, copy/status strings, panel order, bounds, control geometry, and visibility/capability gating remain byte-for-byte or screenshot-equivalent.

Run focused tests before implementation and expect them to fail on missing host/presentation modules.

**Step 2: Implement the smallest presentation host**

`modules/PresentationHost.lua` adapts the existing Overlay control constructors. It does not create a widget framework and exposes no Limn Canvas/Element internals.

Migrate in this fixed order:

1. RIVALS generic panels.
2. Counterblox panels.
3. Town recovery/copy panels last, after confirming no active Town task overlap.

Stop immediately for any copy/status/layout decision or uncertain Town overlap.

**Step 3: Validate automated and visual parity**

```bash
lune run tests/presentation_host_contracts.luau
lune run tests/overlay_contracts.luau
lune run tests/catalog_contracts.luau
HYDROXIDE_ROOT=C:/git/hydroxide LIMN_ROOT=C:/git/limn ./scripts/check.sh
git diff --check
```

Capture before/after screenshots in RIVALS, Counterblox, and Town at the same viewport/inset and compare panel positions, control bounds, copy/status text, visibility, and z-order.

**Step 4: Commit**

```bash
git add modules/PresentationHost.lua modules/Overlay.lua init.lua games/rivals/Presentation.lua games/counterblox/Presentation.lua games/town/Presentation.lua games/rivals/Definition.lua games/counterblox/Definition.lua games/town/Definition.lua tests/presentation_host_contracts.luau tests/overlay_contracts.luau tests/catalog_contracts.luau scripts/check.sh
git commit -m "Move game panels behind presentation host"
```

## Independent review FIX: closed source scopes

**Files:**

- Create failing-first: `tests/source_inventory_contracts.luau`
- Modify failing-first: `tests/hub_loader_contracts.luau`
- Modify: `hub.lua`
- Modify: `scripts/check.sh`
- Modify: this plan

**Contracts and implementation:**

1. Prove red for cross-definition duplicate ownership, missing/undeclared sources, order-independent ownership diagnostics, selected-game import denial, invalid definitions before any game fetch, and eager deterministic/no-lazy loading.
2. Build a complete core/definition source-owner map after every definition validates and before any declared game source is fetched. Each path has exactly one owner; only an explicit core/shared declaration may be shared.
3. Continue eager pinned prefetch of the validated source union, but install `configuration.Import` with a closed allowlist containing core/shared modules, catalog/definition modules required by init, and only the resolved definition's declared sources.
4. Run the two focused loader/inventory contracts, strict analysis, full `scripts/check.sh`, and `git diff --check`.
5. Commit as `Close packaged game source scopes`.

Stop before implementation if closed scoping requires network-lazy loading, broader remote trust, or a new Hydroxide dependency.

## Independent review FIX: thin presentation host

**Files:**

- Rewrite failing-first: `tests/presentation_host_contracts.luau`
- Modify failing-first: `tests/overlay_contracts.luau`
- Replace: `modules/PresentationHost.lua`
- Create cohesive generic UH presentation modules under `modules/presentation/`
- Modify: `modules/Overlay.lua`
- Rewrite composition: `games/counterblox/Presentation.lua`
- Rewrite composition: `games/rivals/Presentation.lua`
- Rewrite composition: `games/town/Presentation.lua`

**Contracts and implementation:**

1. Prove red that the host receives only a generic UH facade; contains no `surface`, `create`, Limn/Canvas/Element access, Town/cosmetics text, or game option labels; and supports a minimal presentation through mount/layout/render/reload/destroy without aim or cosmetics.
2. Extract small cohesive generic control/panel construction and registered layout/render behavior above Limn. Overlay retains the Limn surface and supplies a generic facade; the host only validates and mounts the selected presentation.
3. Move ordered aim/rate/option/cosmetics composition into Counterblox and RIVALS presentation modules. Move Town copy/recovery panel composition and action selection into Town presentation; Town mounts neither aim nor cosmetics.
4. Preserve supported `overlay.controls` keys, exact labels/status/copy strings, callback timing, geometry, capability gating, z-order, visibility, and cleanup.
5. Run focused presentation/overlay/Limn contracts, strict analysis, full `scripts/check.sh`, and `git diff --check`.
6. Commit as `Replace presentation host monolith`.

Stop immediately for any copy/status/layout/state choice or Town behavior overlap. Live screenshot QA remains blocked until all automated/audit fixes are green and matching baselines are available.

## Independent review FIX: sparse definitions and game-local composition

**Files:**

- Create: `games/Compatibility.lua`
- Create game-local composition modules under each game package
- Modify: `games/counterblox/Definition.lua`
- Modify: `games/rivals/Definition.lua`
- Modify: `games/town/Definition.lua`
- Modify: `modules/Registry.lua`
- Modify: `init.lua`
- Modify failing-first: `tests/catalog_contracts.luau`
- Create failing-first: `tests/game_onboarding_contracts.luau`
- Modify stale architecture wording only: `games/rivals/AGENTS.md`

**Contracts and implementation:**

1. Prove red for a canonical deep-copied compatibility defaults/state base, sparse per-game additions/overrides, exact final three-game state/config equality, selected-only composition import, no Town/cosmetics adapter-id branching in init, and a fourth-game fixture added with only Definition/Adapter/Presentation/Catalog/test files.
2. Compose each pure Definition from `games/Compatibility.lua` without sharing mutable tables. Definitions remain data-only and may name an optional pure composition module path.
3. Import only the selected composition binder. Give it a narrow context so it registers game-local startup patch/actions without services, Limn objects, raw Drawing, or runtime behavior in the Definition.
4. Remove game-specific startup/action maps and adapter-id branches from `init.lua` while preserving exact settings/state/config keys, startup order, and Town recovery behavior.
5. Update only stale architecture claims in `games/rivals/AGENTS.md`.
6. Run focused catalog/onboarding/adapter contracts, strict analysis, full `scripts/check.sh`, and `git diff --check`.
7. Commit as `Compose sparse game definitions locally`.

The raw-Lighting suppression included in `c66466f` is already-published Limn baseline behavior and remains unchanged by these corrective commits.

The existing `raycastIgnore` calls remain preservation-only. Do not change the current Hydroxide pin until the Hydroxide manager supplies a published generic Targeting commit; report the exact pin change required when that commit is available.

## Task 6: Split lifecycle boundaries only where required

**Gate:** Begin only after Phase 4 automated and screenshot parity is green.

**Candidate files, subject to failing evidence:**

- Modify: `games/Counterblox.lua`
- Modify: `games/rivals/Adapter.lua`
- Modify: `games/Town.lua`
- Create only if a responsibility cluster already exists: game-local lifecycle modules under the owning game directory.
- Modify: direct adapter contract tests.

**Step 1: Search references and write a failing cleanup/partial-construction regression**

Only introduce `create`/`start`/`stop` where a test proves an early callback or partial-construction cleanup risk. Preserve current cleanup order.

**Step 2: Split only existing clusters**

- Game package owns all imports.
- Shared aim-rate policy is allowed only if RIVALS and Counterblox tests prove identical semantics.
- Specialized selectors remain game-local.
- Delete dead/duplicated code only after reference search and a failing regression proves it is safe.

**Step 3: Validate and commit**

Run the changed adapter contracts, full `scripts/check.sh`, `git diff --check`, reload/stop QA in the affected game, then commit one atomic lifecycle change. Do not create a cleanup commit when no failing boundary exists.

## Local live QA gate

Roblox mutation is not authorized by this plan alone. Once the manager explicitly authorizes local live QA, use only this isolated worktree plus clean Limn/Hydroxide dependency artifacts.

For each of RIVALS, Counterblox, and Town:

1. Set `UniversalHubConfig.LocalRoot` to this isolated worktree export, `HydroxideRoot` to the stable Hydroxide dependency, and `LimnPath` to the clean Limn distribution.
2. Load `local.lua` in a clean server/session.
3. Inspect `UniversalHubSession.adapterId`, `.game`, `.registry:List()`, `.state`, and `.store:Get()`.
4. Confirm the selected adapter and config path/key compatibility.
5. Confirm capabilities and `overlay.controls` match the pre-refactor session.
6. Confirm target/observation counts, projection/visibility behavior, and raycast budgets do not increase.
7. In Town, inspect checkpoint recovery state and schema without starting a copy unless separately authorized.
8. Reload once and confirm the previous session stops, input/pointer capture releases, drawings disappear, and only one live session remains.
9. Call `UniversalHubSession:stop()` and confirm Limn elements/signals, Hydroxide lifecycle resources, adapter callbacks, and input connections are cleaned up.

Phase 4 additionally requires paired screenshots for all three games with identical viewport, inset, state, and menu visibility. No label, status, copy text, layout, bounds, z-order, or visibility drift is allowed.

## Final validation and stop conditions

Before reporting any phase complete:

```bash
HYDROXIDE_ROOT=C:/git/hydroxide LIMN_ROOT=C:/git/limn ./scripts/check.sh
git diff --check
git status --short
git log --oneline origin/main..HEAD
```

Required evidence:

- failing-first focused contracts were observed red, then green;
- strict analysis is clean;
- full check prints `universal-hub-check-ok`;
- `git diff --check` exits `0`;
- the phase is one atomic commit;
- no hidden disabled code or skipped test remains;
- authorized local live QA and screenshot parity are recorded when the phase changes runtime/UI behavior.

Stop and report to manager thread `019fab73-ada4-7f12-b23f-4bb817bdd6a0` immediately when any of these occurs:

- non-mechanical conflict applying `9ab0176c54d85945012e6d53ab3bc16e26675f1a`;
- missing Limn or stable Hydroxide feature;
- a need to rely on unpublished `raycastIgnore`;
- staged catalog execution changes the security/audit trust model;
- uncertain overlap with active Town work;
- any behavior, state schema, copy/status text, layout, or UI decision;
- Phase 4 is reached without explicit manager approval;
- Roblox mutation/live QA is required without explicit authorization.

Do not push, open a PR, merge, publish, or mutate Roblox. The final worker report must list plan path, commit hashes, validation evidence, live-QA evidence or its authorization blocker, and any pre-existing failures left unchanged.
