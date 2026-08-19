local WeaponPolicy = require("../games/hoodrivals/WeaponPolicy")

local function weapon(name, gunType, shots, fireRate)
    local values = {
        GunType = { Value = gunType },
        Shots = { Value = shots },
        FireRate = { Value = fireRate },
    }
    return {
        Name = name,
        FindFirstChild = function(_self, child)
            if child == "Stats" then
                return {
                    FindFirstChild = function(_stats, value)
                        return values[value]
                    end,
                }
            end
        end,
    }
end

local sniper = WeaponPolicy.profile(weapon("R700", "Semi", 1, 0.85), {
    DamageRadius = 0.5,
})
assert(sniper.scoped and sniper.manualFire)
assert(sniper.damageRadius == 0.5)

local rifle = WeaponPolicy.profile(weapon("AK74U", "Auto", 1, 0.11), {})
assert(not rifle.scoped and not rifle.manualFire)
assert(rifle.nativeFireRate == 0.11)

local shotgun = WeaponPolicy.profile(weapon("PumpShotgun", "Semi", 8, 0.7), {})
assert(shotgun.manualFire and shotgun.pelletCount == 8)

print("hood-rivals-weapon-policy-contracts-ok")
