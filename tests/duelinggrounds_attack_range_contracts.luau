local fs = require("@lune/fs")

local AttackRange = require("../games/duelinggrounds/features/combat/AttackRange")
local Definition = require("../games/duelinggrounds/Definition")

local profile = {
    approachDistance = 8,
    orbitDistance = 7,
    retreatDistance = 6,
    maximumNeutralAttackDistance = 10,
    neutralAttack = "Light",
    neutralCadence = 0.2,
    safeRangeBuffer = 0.5,
}

local close = AttackRange.apply(profile, "close", 12)
local medium = AttackRange.apply(profile, "medium", 12)
local far = AttackRange.apply(profile, "far", 12)
assert(close.maximumNeutralAttackDistance < medium.maximumNeutralAttackDistance)
assert(medium.maximumNeutralAttackDistance < far.maximumNeutralAttackDistance)
assert(far.maximumNeutralAttackDistance == 10, "Far must use the weapon's capped hit reach")
assert(far.orbitDistance < far.maximumNeutralAttackDistance, "Far must retain an impact margin")
assert(AttackRange.normalize("invalid") == "medium")

local random = {}
function random:NextNumber()
    return 0.05
end
assert(AttackRange.choose(random, true) == "close")
assert(AttackRange.choose(random, false) == "far", "Unsafe random spacing must fall back to far")
random.NextNumber = function()
    return 0.4
end
assert(AttackRange.choose(random, true) == "medium")
random.NextNumber = function()
    return 0.9
end
assert(AttackRange.choose(random, true) == "far")

assert(Definition.defaults.attackRange == "medium")
assert(Definition.defaults.randomAttackRange == false)
assert(table.find(Definition.sources, "games/duelinggrounds/features/combat/AttackRange"))

local source = fs.readFile("games/DuelingGrounds.lua")
local criticalTarget = source:find("local criticalTarget", 1, true)
local shieldBreakChoice = source:find('choice = queued and "shieldBreakUltimate"', criticalTarget, true)
local ultimateQueue = source:find('TryQueueBasicAttack("Ultimate")', criticalTarget, true)
local criticalFallback = source:find("Request.CriticalStrike:FireServer", criticalTarget, true)
assert(criticalTarget and shieldBreakChoice and ultimateQueue and criticalFallback)
assert(ultimateQueue < criticalFallback, "Shield-break Ult must run before the normal critical")
assert(
    source:find("actionManager:_clearQueuedAction()", criticalTarget, true) < ultimateQueue
        and source:find("actionManager:SwitchToAction(nil)", criticalTarget, true) < ultimateQueue,
    "Shield-break Ult must interrupt ordinary queued or cancelable attacks"
)
assert(source:find("ULTIMATE_SHIELD_BREAK_RESERVE", 1, true))

local presentation = fs.readFile("games/duelinggrounds/Presentation.lua")
assert(presentation:find('id = "attackRange"', 1, true))
assert(presentation:find('"randomAttackRange", "Random Range"', 1, true))
assert(
    presentation:find("disabledWhen = { randomAttackRange = true }", 1, true),
    "Random Range must disable the fixed range selector"
)

local catalog = fs.readFile("ui/presentation/Catalog.lua")
assert(catalog:find("disabled = settingsMatch(segment.disabledWhen, settings)", 1, true))
assert(
    source:find("predictedDistance <= maximumReach", 1, true),
    "Locked-target attacks must use predicted weapon reach without requiring pre-attack facing"
)

print("duelinggrounds-attack-range-contracts-ok")
