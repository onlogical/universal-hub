local roblox = require("@lune/roblox")
CFrame = roblox.CFrame
Vector3 = roblox.Vector3
typeof = roblox.typeof

local Attacks = require("../games/duelinggrounds/features/combat/Attacks")

local function impact(time, z, depth, results)
    return {
        markerTime = time,
        impactInfo = {
            hitboxCFrame = CFrame.new(0, 0, z),
            hitboxSize = Vector3.new(4, 4, depth),
            impactResults = results,
        },
    }
end

local attack = {
    animation = { AnimationId = "attack://light" },
    impacts = {
        impact(0.5, -3, 4, {
            GetHit = { healthDamage = 55 },
            Block = { postureDamage = 10 },
            Parry = {},
        }),
        impact(0.8, -6, 2, { GetHit = { triggerUltimate = true } }),
    },
    timeMarkers = { canCancel = 0.9 },
}

assert(Attacks.sameAnimation(attack.animation, { AnimationId = "attack://light" }))
local found, name = Attacks.findByAnimation({ Light1 = attack }, {
    AnimationId = "attack://light",
})
assert(found == attack and name == "Light1")
assert(Attacks.firstImpactTime(attack) == 0.5)
assert(Attacks.lastImpactTime(attack) == 0.8)
assert(Attacks.marker(attack, "canCancel") == 0.9)
assert(Attacks.isHeavy("Light1", attack))
assert(Attacks.isMultiHit(attack))
assert(Attacks.isParryable(attack.impacts[1]))
assert(Attacks.triggersUltimateDamage(attack))
assert(Attacks.geometricReach(attack) == 7)

local attacker = { CFrame = CFrame.new(), Position = Vector3.zero }
local defender = { Position = Vector3.new(0, 0, -4) }
assert(Attacks.impactCanReach(attacker, defender, attack.impacts[1], { strict = true }))
assert(not Attacks.impactCanReach(
    attacker,
    { Position = Vector3.new(20, 0, 0) },
    attack.impacts[1],
    {}
))

print("duelinggrounds-attacks-policy-contracts-ok")
