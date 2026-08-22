local fs = require("@lune/fs")

local source = fs.readFile("games/DuelingGrounds.lua")
local comboWindow = source:find('currentAction.ActionType == "BasicAttack"', 1, true)
local comboPermission = source:find("currentAction.CanQueueBasicAttacks", 1, true)
local queueLight = source:find('actionManager:TryQueueBasicAttack("Light")', comboPermission, true)
local threatGuard = source:find("not hasIncomingThreat(true)", comboPermission, true)

assert(comboWindow and comboPermission and queueLight)
assert(threatGuard and threatGuard < queueLight, "combos must remain subordinate to incoming threats")
assert(
    source:find("not targetIsDodging()", comboPermission, true)
        and source:find("not targetIsParrying()", comboPermission, true),
    "combos must not continue into target invulnerability"
)

print("duelinggrounds-combo-contracts-ok")
