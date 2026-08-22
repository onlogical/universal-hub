local Skill = require("../games/duelinggrounds/features/combat/Skill")

local low = Skill.profile(0)
local high = Skill.profile(100)
assert(low.reactionDelay > high.reactionDelay)
assert(low.reactionJitter > high.reactionJitter)
assert(low.defenseAccuracy < high.defenseAccuracy)
assert(low.punishAccuracy < high.punishAccuracy)
assert(Skill.profile(nil).level == 85)
assert(Skill.profile(-10).level == 0)
assert(Skill.profile(120).level == 100)

local alwaysLow = { NextNumber = function() return 0 end }
local alwaysHigh = { NextNumber = function() return 1 end }
assert(Skill.shouldAct(low, alwaysLow) == true)
assert(Skill.shouldAct(low, alwaysHigh) == false)
assert(Skill.shouldAct(high, alwaysHigh) == true)

print("duelinggrounds-skill-contracts-ok")
