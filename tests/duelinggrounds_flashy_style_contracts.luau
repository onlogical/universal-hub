local FlashyStyle = require("../games/duelinggrounds/features/combat/FlashyStyle")

local confident = FlashyStyle.preferences({
    health = 900,
    maximumHealth = 1100,
    posture = 100,
    maximumPosture = 125,
    defenseReady = true,
})
assert(confident.counterAllowed == true)
assert(confident.aggressiveCombos == true)
assert(confident.proactiveDashCounter == true)
assert(confident.movement.orbitInterval < 1)
assert(confident.movement.orbitDistanceScale < 1)
assert(confident.suppressTraversalDodge == true)
assert(confident.punishOnly == true)

local pressured = FlashyStyle.preferences({
    health = 300,
    maximumHealth = 1100,
    posture = 20,
    maximumPosture = 125,
    defenseReady = false,
})
assert(pressured.counterAllowed == false)
assert(pressured.aggressiveCombos == true)
assert(pressured.proactiveDashCounter == false)
assert(pressured.movement.orbitDistanceScale > 1)
assert(pressured.movement.orbitInterval > confident.movement.orbitInterval)

print("duelinggrounds-flashy-style-contracts-ok")
