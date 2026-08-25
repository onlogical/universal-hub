local fs = require("@lune/fs")
local MeleeReach = require("../games/rivals/features/MeleeReach")

local adapterSource = fs.readFile("games/rivals/Adapter.lua")
assert(adapterSource:find('require("./features/MeleeReach")', 1, true))
assert(adapterSource:find("meleeReach:update(settings, fighter and fighter.EquippedItem)", 1, true))
assert(adapterSource:find("meleeReach:stop()", 1, true))

local meleeReach = MeleeReach.new()
local knife = {
    Info = {
        AttackReach = 6,
        HeavyAttackReach = 7,
    },
}
meleeReach:update({ meleeReach = true, meleeReachScale = 200 }, knife)
assert(knife.Info.AttackReach == 12 and knife.Info.HeavyAttackReach == 14)

local fists = { Info = { AttackReach = 6 } }
meleeReach:update({ meleeReach = true, meleeReachScale = 999 }, fists)
assert(knife.Info.AttackReach == 6 and knife.Info.HeavyAttackReach == 7)
assert(fists.Info.AttackReach == 18, "Melee Reach must clamp to the supported slider maximum")

local firearm = { Info = { ShootCooldown = 0.1 } }
meleeReach:update({ meleeReach = true, meleeReachScale = 200 }, firearm)
assert(fists.Info.AttackReach == 6, "switching items must restore the prior melee weapon")
assert(firearm.Info.AttackReach == nil, "Melee Reach must not modify firearms")

local gunblade = { Info = { BladeReach = 8 } }
meleeReach:update({ meleeReach = true, meleeReachScale = 150 }, gunblade)
assert(gunblade.Info.BladeReach == 12, "Melee Reach must support dual-mode blades")

meleeReach:update({ meleeReach = true, meleeReachScale = 100 }, knife)
assert(gunblade.Info.BladeReach == 8)
assert(knife.Info.AttackReach == 6 and knife.Info.HeavyAttackReach == 7)
meleeReach:stop()
assert(knife.Info.AttackReach == 6 and knife.Info.HeavyAttackReach == 7)

print("rivals-melee-reach-contracts-ok")
