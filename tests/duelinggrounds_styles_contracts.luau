local Styles = require("../games/duelinggrounds/features/combat/Styles")

assert(Styles.preferences("offensive").counterAllowed == true)
assert(Styles.preferences("defensive").counterAllowed == false)
assert(Styles.preferences("dynamic", nil, { mode = "defensive" }).counterAllowed == false)
assert(Styles.preferences("dynamic", nil, { mode = "offensive" }).counterAllowed == true)
assert(Styles.preferences("flashy", {
    health = 900,
    maximumHealth = 1100,
    posture = 100,
    maximumPosture = 125,
    defenseReady = true,
}).counterAllowed == true)

print("duelinggrounds-styles-contracts-ok")
