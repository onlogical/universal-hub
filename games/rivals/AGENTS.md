# RIVALS Adapter Guide

This directory owns Universal Hub's RIVALS integration. Read this file before
opening the implementation. Start with the module named for the behavior you
need; read `Adapter.lua` only when changing orchestration or a cross-module
flow. New features take injected libraries from Adapter. Do not copy
`importDependency` into a feature.

## Runtime shape

`games/rivals/Definition.lua` declares every RIVALS source. The packaged
loader validates and prefetches that closed source set, then `init.lua`
imports only the selected adapter and presentation. Add, rename, or remove
RIVALS modules through the definition rather than a second bootstrap list.
RIVALS has no composition module because it owns no custom startup or overlay
actions.

The adapter receives the selected scoped Hydroxide helper namespace plus a
Limn runtime. It must not read `environment.oh`, raw `Drawing`, or a Limn
filesystem path. Retained trajectory lines belong to a game-owned Limn canvas
that is destroyed with the adapter.

The per-frame flow is:

1. `Adapter` reads the live RIVALS controllers and combat state.
2. It publishes player and utility observations to the shared store/overlay.
3. `Targeting` selects or retains a target and applies head/miss policy.
4. `ProjectileAim` optionally replaces the direct aim point with a trajectory.
5. Camera Aim updates the logical camera immediately. Silent Aim promotes the
   target only after `ShotPresentation` has staged the matching native camera
   frame.
6. `ScopedAccuracy` optionally reports eligible native Gun shots as scoped
   without changing the user's ADS/FOV state.
7. Trigger Bot evaluates that same target, then `WeaponPolicy` decides whether
   and how the equipped weapon may act.
8. `Movement` and `Effects` update independently under the same combat gates.

## Module map

Root is the integration surface only: `Adapter.lua`, `Definition.lua`,
`Presentation.lua`, `Session.lua`. Everything else lives in `features/`,
`libraries/`, `tasks/`, or `world/`. New features take injected libraries
from Adapter. Do not copy `importDependency` into a feature.

- `Adapter.lua`
  - RIVALS manifest and capabilities.
  - Live controller discovery and dependency wiring.
  - Observation refresh, target retention, per-frame orchestration, input
    dispatch, and weapon-specific coordination.
- `Session.lua`
  - One per-frame snapshot. Features read it; each field has one writer.
  - `aligned` is the aim-plan target. `presented` is Silent Aim's promoted target.
- `features/CameraAim.lua`
  - Writes the aim-plan value that Adapter stores on `session.aligned`.
  - User-facing Camera Aim (`settings.silentAim`). Does not write `presented`.
  - Prefers a visible target inside the Camera FOV, then falls back to a
    blocked target inside that same FOV. Through-wall unrestricted acquisition
    belongs to Silent Aim and task combat.
- `features/SilentAim.lua`
  - Reads `session.aligned` and writes `session.presented`.
  - Owns `features/ShotPresentation.lua`.
- `features/TeleportBehind.lua`
  - User-facing Warp (`settings.teleportBehind`) on the Rage page.
    Irregular hops around the selected target at hitscan height
    with line of sight. From a sky slot, aim at the torso so the
    downward shot hits the body, not over the head. If the sky
    slot is blocked, fall in to a close pocket. A sniper or knife
    holds a one-shot angle instead of hopping; other guns keep
    the barrage. Do not
    walk a sequential ring. Hold the first grounded focus Y so
    two teleporters do not stack into the lid. Pull a slot in if
    it clips a tagged OOB part. Do not engage during a ForceField
    or entity invincibility.
  - Rewrites the hold after physics (`Heartbeat`). Do not Anchor the
    root — that stops CFrame from replicating. Zero velocity instead.
  - Once engaged, keep holding if combat/camera flickers or the menu
    opens. Release only on setting off or death.
- `features/TriggerBot.lua`
  - Reads `presented` when Silent Aim is on, otherwise `aligned`. Does not reselect.
  - Fires on the equipped weapon's native cooldown. Do not add a
    0.1s floor. Keep a hold-to-fire press through one-frame path
    flicker. Native automatic guns repeat `StartShooting` without a
    release gap; continuous InternalUse weapons keep one held press and
    may re-press only after their native cooldown stays expired for a
    full fire interval. Do not restart because ammo replicas are stale.
    Compare `item._shoot_cooldown` with `tick`, never `os.clock`. With both
    aim modes off, use the native mouse ray hit instead of a screen-radius
    heuristic or nearest full-screen target. Release when the target is deflecting, even if the
    blade blocks line of sight. Do not keep a hold through that.
    `settings.triggerDelay` is a first-shot wait in milliseconds; do
    not add it to the native cooldown after the hold starts. Only multi-pellet
    shotguns may gate severe falloff; low-damage poke from other weapons is intentional.
- `features/RapidFire.lua`
  - User-facing Rapid Fire. Reversibly scales native `ShootCooldown`, melee
    `AttackCooldown`, and Bow `ChargeReleaseCooldown`; repeats normal primary-fire
    input for held semi-automatic and burst-input weapons. Restore every patched
    item when disabled, unequipped, or stopped.
- `features/QuickReload.lua`
  - User-facing Quick Reload. Ends normal and empty reloads at their native ammo
    insertion timestamps, removing only the post-ammo animation lockout. Restore
    every patched length when disabled, unequipped, or stopped.
- `features/MeleeReach.lua`
  - User-facing Melee Reach. Reversibly scales native `AttackReach`,
    `HeavyAttackReach`, and `BladeReach` while leaving native input and hit
    registration untouched. Restore every patched item on disable, switch, or stop.
- `features/SkipBlocks.lua`
  - User-facing Katana Stop (`settings.skipDeflect`). Hooks fighter input's
    `StartShooting` action so a manual click does not fire into a deflect
    unless true-damage spray applies. Same gate as Trigger Bot.
- `features/AutoDeflect.lua`
  - User-facing Auto Katana (`settings.autoDeflect`). Pre-blocks with
    the equipped deflector when an opponent is looking at us and that
    shot would be lethal. Katana reflect does not require ADS. Hitscan
    plus ping means do not wait for the shot. Do not invent latency
    compensation.
- `features/AutoCounter.lua`
  - Detect-and-shoot only. Must not write fighter `CFrame`.
- `features/NoScope.lua`
  - User-facing Always Scoped. Stored setting stays `alwaysScoped`.
- `features/Pickup.lua`
  - Gates Gun Game pickup behind `settings.autoPickup`. Keep the
    Tools capability even when execute is not already in Gun Game.
- `features/ScopedAccuracy.lua`
  - No Scope guts.
- `tasks/TaskLoadout.lua`
  - Native `PickWeapon` + `Finish` poll while task farming is armed.
    Private/paused matches leave the picker to the player.
- `libraries/CombatState.lua`
  - Practice range is eligible only while its loadout picker is closed.
  - Duels are eligible only at `Status == "RoundStarted"`.
- `libraries/Targeting.lua`
  - Nearest/retained observation selection, humanized rotation, head/miss policy.
- `libraries/ProjectileAim.lua`
  - Direct projectile lead/gravity, splash, ricochet, and Slingshot helpers.
- `libraries/WeaponPolicy.lua` / `libraries/ItemPolicy.lua`
  - Item labels, damage/falloff, ADS, hold-to-fire, Bow, Revolver, Knife, Gunblade.
    Continuous InternalUse weapons (no ShootDamage) still get Trigger Bot.
- `libraries/Movement.lua`
  - Bunny hop and slide behind active/combat/input-capture gates.
- `tasks/TaskPolicy.lua`
  - Pure normalization and selection for native task records.
- `tasks/TaskFarmRuntime.lua`
  - Signal-driven inherent task detection. Owns no frame loop.
- `world/Effects.lua`
  - Utility discovery, visibility suppression, and trajectory drawing.

## Names that are easy to misread

The persisted setting names predate the current UI labels:

- `settings.silentAim` is user-facing **Camera Aim**.
- `settings.shotAim` is user-facing **Silent Aim**.

Use the setting names in code and the user-facing names in UI copy. Never
infer behavior from the setting name alone.

## Invariants

- Do not fire during lobby, map voting, round countdown, or either loadout
  picker. `CanPickWeapons` is permission, not proof that the picker is open;
  use the live Pick Weapons page through `CombatState`.
- Camera Aim, Silent Aim, and Trigger Bot must consume the same selected
  target. Retain a valid target rather than switching every frame.
- Trigger Bot fires on a solved bullet path (hitscan LOS, projectile lead,
  ricochet, slingshot, or splash), not on-screen visibility alone.
- Silent Aim actions must wait for `ShotPresentation:getPresentedTarget()`.
  Never reselect inside a Silent Aim trigger branch; that bypasses the
  presentation-before-action guarantee.
- Gunblade may use its closest eligible world-space target and ignore normal
  screen FOV only when Silent Aim is off. With Silent Aim on, it uses the
  presented target. Slice on the first frame inside `BladeReach` for which
  `CanQuickAttack()` is true; do not wait for the visual dash duration.
- Revolver spread is nondeterministic client-side. Choose fan versus precise
  only when the complete configured cone fits the selected target. Do not
  claim spread removal or inverse compensation without new server-backed
  evidence.
- Bow charge changes damage, not its observed projectile speed. Direct
  projectile solving must apply the weapon's `ProjectileSpawnOffset` before
  iterating lead and gravity. Do not add speculative latency or
  shooter-velocity inheritance.
- Head preference must use live critical `HitboxHead`/`HitboxHeadSmall`
  geometry before the smaller visual Head, then test center and bounded crown
  points. A body part in front of the point is not a head hit; accept only
  target-descendant native head proxies or parts explicitly marked
  `IsCritical`.
- Always Scoped is opt-in and may only override the equipped item when it
  exposes the common native `IsFullyAiming` seam and a positive numeric
  `AimScopePercent`. Keep normal ADS readiness on the native predicate; camera
  FOV is fallback evidence only. The stored setting and capability key is
  `alwaysScoped`; the internal implementation module remains `ScopedAccuracy`.
- Utility ESP classification is tag-first and must reject held/viewmodel/local
  copies. Tripmine renders as a 12-edge wireframe cube; generic utilities keep
  their compact marker.
- Use normal client input and native controller/item methods for actions.
  Direct replication calls are discovery evidence, not an implementation
  shortcut.
- RIVALS client internals are volatile. Re-establish live paths, fields,
  cooldowns, and server acceptance before changing behavior based on them.

## Live validation

For authorized RIVALS testing:

1. Confirm the connected Roblox client before trusting runtime observations.
2. Prefer read-only status, evaluation, script inventory, and decompilation for
   discovery.
3. Stage this repo into Volt's workspace (`%LOCALAPPDATA%\Volt\workspace`) at
   `universal-hub/local`, plus Hydroxide helpers at `hydroxide/local` and Limn
   at `limn/dist/Limn.lua`. Confirm, then load with Volt `loadfile`:

   ```lua
   assert(isfile("universal-hub/local/local.lua"), "stage the hub tree first")
   loadfile("universal-hub/local/local.lua")()
   ```

4. Validate state-changing behavior through normal game/client paths against
   practice dummies or consenting players.
5. Restore temporary settings and loadouts after QA. If the live client blocks
   the observation, report the gap instead of converting a contract test into
   a live claim.

Never expose executor or MCP credentials in source, logs, artifacts, or
handoffs.

## Verification

Focused contracts:

```bash
HYDROXIDE_ROOT='C:/git/hydroxide' lune run tests/rivals_adapter_contracts.luau
HYDROXIDE_ROOT='C:/git/hydroxide' lune run tests/rivals_combat_state_contracts.luau
HYDROXIDE_ROOT='C:/git/hydroxide' lune run tests/overlay_contracts.luau
```

Full repository gate:

```bash
HYDROXIDE_ROOT='C:/git/hydroxide' ./scripts/check.sh
```

Add a behavioral contract for subtle cross-module boundaries, especially
phase gates, target presentation, projectile launch math, and weapon state
machines. A green pure contract does not replace live QA when runtime behavior
is the claim.
