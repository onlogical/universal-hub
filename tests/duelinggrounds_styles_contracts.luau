local Styles = require("../games/duelinggrounds/features/combat/Styles")
local Definition = require("../games/duelinggrounds/Definition")
local fs = require("@lune/fs")

assert(Styles.preferences("offensive").counterAllowed == true)
local tele = Styles.preferences("tele")
assert(tele.teleAttack == true, "Tele style must enable its teleport attack loop")
assert(tele.counterAllowed == false, "Tele style must not start dodge counters")
assert(Styles.preferences("defensive").counterAllowed == false)
local baby = Styles.preferences("baby")
assert(baby.allowOffense == false, "Baby mode must not initiate attacks")
assert(baby.counterAllowed == false, "Baby mode must not convert dodges into counters")
assert(baby.escapeCorners == true, "Baby mode must escape laterally when retreat is blocked")
assert(
    baby.movement.retreatDistance >= 18
        and baby.movement.orbitDistance > baby.movement.retreatDistance
        and baby.movement.approachDistance > baby.movement.orbitDistance,
    "Baby mode must maintain a wide, stable spacing band"
)
assert(Styles.preferences("dynamic", nil, { mode = "defensive" }).counterAllowed == false)
assert(Styles.preferences("dynamic", nil, { mode = "offensive" }).counterAllowed == true)
assert(Styles.preferences("flashy", {
    health = 900,
    maximumHealth = 1100,
    posture = 100,
    maximumPosture = 125,
    defenseReady = true,
}).counterAllowed == true)

assert(
    table.find(Definition.sources, "games/duelinggrounds/features/combat/BabyStyle"),
    "BabyStyle must be staged by the Dueling Grounds definition"
)
assert(
    table.find(Definition.sources, "games/duelinggrounds/features/combat/TeleStyle"),
    "TeleStyle must be staged by the Dueling Grounds definition"
)
assert(Definition.defaults.duelEscapeKey == "End", "Duel Escape must default to End")
assert(
    table.find(Definition.sources, "games/duelinggrounds/features/DuelEscape"),
    "DuelEscape must be staged by the Dueling Grounds definition"
)
local presentationSource = fs.readFile("games/duelinggrounds/Presentation.lua")
assert(presentationSource:find('value = "baby"', 1, true), "Prism must expose Baby mode")
assert(presentationSource:find('value = "tele"', 1, true), "Prism must expose Tele mode")
assert(
    presentationSource:find('"duelEscapeKey", "Duel Escape"', 1, true),
    "Prism must expose the Duel Escape keybind"
)
local adapterSource = fs.readFile("games/DuelingGrounds.lua")
assert(
    adapterSource:find('settings.combatStyle == "baby"', 1, true),
    "Baby mode must suppress proactive offense"
)
assert(
    adapterSource:find("movement.approachDistance", 1, true)
        and adapterSource:find("movement.orbitDistance", 1, true)
        and adapterSource:find("movement.retreatDistance", 1, true),
    "Movement preferences must support explicit Baby spacing distances"
)

print("duelinggrounds-styles-contracts-ok")
