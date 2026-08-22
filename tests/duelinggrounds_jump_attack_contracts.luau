local JumpAttackPolicy = require("../games/duelinggrounds/features/combat/JumpAttackPolicy")

local shouldJump, reason = JumpAttackPolicy.shouldJump({
    available = true,
    jumpReady = true,
    cooldownReady = true,
    canQueue = true,
    targetBlocking = true,
    targetPosture = 40,
    postureDamage = 60,
    inRange = false,
    canLunge = true,
})
assert(shouldJump and reason == "postureBreak")

shouldJump, reason = JumpAttackPolicy.shouldJump({
    available = true,
    jumpReady = true,
    cooldownReady = true,
    canQueue = true,
    targetStaggered = true,
    staggerRemaining = 1,
    healthDamage = 80,
    heavyHealthDamage = 60,
    inRange = true,
})
assert(shouldJump and reason == "staggerPunish")

assert(not JumpAttackPolicy.shouldJump({
    available = true,
    jumpReady = false,
    cooldownReady = true,
    canQueue = true,
    targetBlocking = true,
    targetPosture = 20,
    postureDamage = 60,
    inRange = true,
}))

print("duelinggrounds-jump-attack-contracts-ok")
