local Combos = require("../games/duelinggrounds/features/combat/Combos")

for _, weaponName in ipairs({
    "BoStaff",
    "CurvedBlades",
    "Daggers",
    "Gauntlets",
    "Katana",
    "Kusarigama",
    "Naginata",
    "War Hammer",
}) do
    assert(
        type(Combos.profile(weaponName).finisherAfter) == "number",
        weaponName .. " must declare a combo profile"
    )
end

local attack, reason = Combos.nextAttack({
    weaponName = "Daggers",
    lightCount = 1,
    hasHeavy = true,
})
assert(attack == "Heavy" and reason == "comboFinisher")

attack, reason = Combos.nextAttack({
    weaponName = "Katana",
    lightCount = 2,
    hasHeavy = true,
})
assert(attack == "Light" and reason == "comboContinue")

attack, reason = Combos.nextAttack({
    weaponName = "Katana",
    lightCount = 3,
    hasHeavy = true,
})
assert(attack == "Heavy" and reason == "comboFinisher")

attack, reason = Combos.nextAttack({
    weaponName = "Kusarigama",
    lightCount = 0,
    hasHeavy = true,
    targetBlocking = true,
})
assert(attack == "Heavy" and reason == "guardPressure")

attack, reason = Combos.nextAttack({
    weaponName = "Daggers",
    lightCount = 0,
    hasHeavy = true,
    recentDeflects = 2,
})
assert(attack == nil and reason == "disengageAfterDeflects")

print("duelinggrounds-combos-contracts-ok")
