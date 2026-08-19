local Planner = require("../games/duelinggrounds/features/combat/defense/Planner")

local impacts = {
    { parryable = false, timeUntilImpact = 0.08 },
    { parryable = true, timeUntilImpact = 0.15 },
    { parryable = true, timeUntilImpact = 0.24 },
}
local reachable = { true, true, true }
local plan = Planner.plan({
    attackName = "HeavyChain",
    impacts = impacts,
    isHeavy = true,
    canParry = true,
    canDodge = true,
    canReach = function(_, index)
        return reachable[index]
    end,
})
assert(plan.kind == "parry")
assert(plan.impactIndex == 2, "multi-hit chains prefer the first reachable parryable impact")
assert(plan.reachableImpactCount == 3)
assert(plan.reason == "interrupt multi-hit chain")

reachable = { true, false, false }
plan = Planner.plan({
    attackName = "HeavySingleReach",
    impacts = impacts,
    isHeavy = true,
    canParry = true,
    canDodge = true,
    canReach = function(_, index)
        return reachable[index]
    end,
})
assert(plan.kind == "dodge" and plan.impactIndex == 1)

assert(Planner.plan({
    impacts = { { parryable = true } },
    canParry = false,
    canDodge = false,
}) == nil, "planner must not invent an unavailable defense")
assert(Planner.fallback({ kind = "parry", parryable = true }, {
    canDodge = false,
}) == nil)
assert(Planner.fallback({ kind = "dodge", parryable = false }, {
    canParry = true,
}) == nil)
assert(Planner.fallback({ kind = "dodge", parryable = true }, {
    canParry = true,
}) == "parry")

print("duelinggrounds-defense-planner-contracts-ok")
