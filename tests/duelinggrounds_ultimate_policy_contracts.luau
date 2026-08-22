local UltimatePolicy = require("../games/duelinggrounds/features/combat/UltimatePolicy")

local allowed, reason = UltimatePolicy.shouldUseNeutral({
    targetHealth = 100,
    ultimateDamage = 120,
})
assert(allowed and reason == "lethal")

allowed, reason = UltimatePolicy.shouldUseNeutral({
    targetHealth = 500,
    ultimateDamage = 120,
    punishWindow = 0.8,
    impactTime = 0.5,
    networkMargin = 0.1,
})
assert(allowed and reason == "confirmedPunish")

allowed, reason = UltimatePolicy.shouldUseNeutral({
    targetHealth = 500,
    ultimateDamage = 120,
    punishWindow = 0.2,
    impactTime = 0.5,
    networkMargin = 0.1,
})
assert(not allowed and reason == "reserveForCritical")

allowed, reason = UltimatePolicy.shouldUseNeutral({
    targetHealth = 100,
    ultimateDamage = 120,
    targetParrying = true,
})
assert(not allowed and reason == "targetInvulnerable")

print("duelinggrounds-ultimate-policy-contracts-ok")
