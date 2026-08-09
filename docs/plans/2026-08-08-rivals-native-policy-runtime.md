# RIVALS Native Policy Runtime Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove place-, weapon-name-, throwable-name-, and artificial-health heuristics from RIVALS while deepening the adapter into native-state policy and focused runtime modules.

**Architecture:** Introduce small, testable native policy modules for match mode, item classification, and utility observation. Move stateful Gun Game, observation, aim/trigger, and effects orchestration behind deep runtime interfaces so `Adapter.lua` coordinates rather than implements each behavior. Native controller/item/tag/attribute data is authoritative; unknown data disables the specialized behavior rather than falling back to guessed knowledge.

**Tech Stack:** Luau, Lune contract tests, Hydroxide Targeting, Roblox controller/item metadata, CollectionService tags and attributes.

---

### Task 1: Native match-mode policy

**Files:**
- Create: `games/rivals/ModePolicy.lua`
- Modify: `games/rivals/Definition.lua`
- Modify: `games/rivals/Adapter.lua`
- Modify: `tests/rivals_adapter_contracts.luau`
- Create: `tests/rivals_mode_policy_contracts.luau`

**Steps:**
1. Write failing contracts for resolving Gun Game solely from verified fighter/duel/controller state and returning `nil` for unknown state.
2. Run the focused contract and confirm the PlaceId behavior fails.
3. Implement `ModePolicy.resolve(context)` and `ModePolicy.isGunGame(context)` with no PlaceId fallback.
4. Replace every `Rivals.isGunGamePlace(game.PlaceId)` branch and capability gate with the native policy.
5. Run mode, registry, presentation, and adapter contracts.

### Task 2: Native item classification

**Files:**
- Create: `games/rivals/ItemPolicy.lua`
- Modify: `games/rivals/WeaponPolicy.lua`
- Modify: `games/rivals/Adapter.lua`
- Modify: `games/rivals/Definition.lua`
- Modify: `tests/rivals_adapter_contracts.luau`
- Create: `tests/rivals_item_policy_contracts.luau`

**Steps:**
1. Write failing contracts using `item.Info`, `item.Data`, callable capabilities, and native input-setting identity rather than display names.
2. Implement classification for firearm, projectile, scoped, melee/backstab, utility, burst, and gunblade-style dual mode.
3. Replace name allowlists and special-name branches in `WeaponPolicy` and `Adapter`.
4. Treat unclassifiable items conservatively; do not add name fallbacks.
5. Run item, weapon-policy, and adapter contracts.

### Task 3: Native utility descriptors

**Files:**
- Create: `games/rivals/UtilityPolicy.lua`
- Modify: `games/rivals/Effects.lua`
- Modify: `games/rivals/Definition.lua`
- Modify: `tests/rivals_effects_contracts.luau`
- Create: `tests/rivals_utility_policy_contracts.luau`

**Steps:**
1. Write failing contracts proving tags/attributes are authoritative and names/containers do not classify utilities.
2. Implement descriptor resolution from native CollectionService tags and explicit replicated attributes.
3. Remove fuzzy token matching and guessed container scanning.
4. Preserve unknown utilities as unclassified rather than guessing.
5. Run utility, effects, overlay, and adapter contracts.

### Task 4: Remove artificial practice health

**Files:**
- Modify: `games/rivals/Adapter.lua`
- Modify: `tests/rivals_adapter_contracts.luau`

**Steps:**
1. Change the contract to require native `Humanoid.Health`/`MaxHealth` values without substituting `150`.
2. Remove `PRACTICE_DUMMY_HEALTH` and the infinite-health replacement.
3. Ensure Limn safely receives infinite/unknown health without producing fabricated values.
4. Run adapter and Limn consumer contracts, documenting any pre-existing Limn failure separately.

### Task 5: Deepen RIVALS runtime modules

**Files:**
- Create: `games/rivals/ObservationRuntime.lua`
- Create: `games/rivals/GunGameRuntime.lua`
- Create: `games/rivals/AimRuntime.lua`
- Create: `games/rivals/EffectsRuntime.lua`
- Modify: `games/rivals/Adapter.lua`
- Modify: `games/rivals/Definition.lua`
- Modify: `tests/rivals_adapter_contracts.luau`
- Create: `tests/rivals_runtime_contracts.luau`

**Steps:**
1. Write interface-level contracts for each runtime, including disabled-state zero-work and idempotent cleanup.
2. Move pickup scanning and retry state behind `GunGameRuntime:update`.
3. Move player/range observation and target selection behind `ObservationRuntime:update/select`.
4. Move aim/trigger/hook coordination behind `AimRuntime:update/stop`.
5. Move utility observation, suppression, and trajectory coordination behind `EffectsRuntime:update/render/stop`.
6. Reduce `Adapter.new` to controller acquisition, runtime construction, one frame coordinator, and deterministic stop.
7. Apply the deletion test: runtime complexity must not reappear in `Adapter.lua`.
8. Run all RIVALS focused contracts and source inventory contracts.

### Task 6: Validate and package focused changes

**Files:**
- Modify only tests/contracts if failures reveal regressions.

**Steps:**
1. Run all focused RIVALS contracts with `/tmp/prism-tools/lune`.
2. Run catalog, registry, game composition, source inventory, presentation host, config, and session contracts.
3. Run `scripts/check.sh` if `luau-lsp` is available; otherwise record the existing tooling blocker.
4. Do not perform live Bloxstrike or invasive executor diagnostics.
5. Review the PowerShell Git diff and keep unrelated worktree changes unstaged.


## Execution results

- Implemented native `ClientDuel.IsGunGame` mode policy with no place fallback.
- Replaced display-name item policies with live item capability shapes.
- Replaced fuzzy utility/container discovery with native tags and `ThrowableOrientation`.
- Removed all artificial `150` health substitution from RIVALS.
- Extracted Gun Game, observation, hook, visual suppression, and trajectory runtime modules.
- Filtered hook-dependent capabilities when hook/restore seams are unavailable.
- Focused and cross-cutting contracts pass; `scripts/check.sh` remains blocked by missing `luau-lsp`.
- `limn_consumer_contracts` and `overlay_contracts` retain the pre-existing `StandardPanels.lua:1186` failure.
- `hub_loader_contracts` retains the pre-existing native Prism menu staging requirement.
