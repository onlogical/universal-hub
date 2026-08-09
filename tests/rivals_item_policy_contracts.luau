local fs = require("@lune/fs")
local ItemPolicy = require("../games/rivals/ItemPolicy")

local policySources = fs.readFile("games/rivals/WeaponPolicy.lua")
    .. fs.readFile("games/rivals/ProjectileAim.lua")
    .. fs.readFile("games/rivals/Adapter.lua")
for _, displayName in ipairs({ "Energy Rifle", "Slingshot", "Gunblade", "Sniper", "Burst Rifle", "Glast Shard", "Katana" }) do
    assert(not policySources:find('"' .. displayName .. '"', 1, true), displayName .. " must not select runtime behavior")
end

local throwable = {
    Info = { ThrowMaxChargeTime = 1, ThrowForceMax = 80, ShootDamage = 100 },
    StartShooting = function() end,
    FinishShooting = function() end,
}
assert(ItemPolicy.isThrowable(throwable))
assert(ItemPolicy.automationPolicy(throwable).triggerBot == false)

local firearm = { Info = { ShootDamage = 25 } }
assert(ItemPolicy.hasTargetedDamage(firearm))
assert(ItemPolicy.automationPolicy(firearm).silentAim == true)

local backstab = {
    _backstab_hash = 12,
    Info = { CriticalDamage = 150, HeavyAttackReach = 6, HeavyAttackCooldown = 1 },
}
assert(ItemPolicy.isBackstab(backstab))
backstab._backstab_hash = nil
assert(not ItemPolicy.isBackstab(backstab), "display identity must not classify a backstab item")

local dualMode = {
    GetMobileInputSettings = function() end,
    Info = {
        BladeModeMobileInputSettings = {},
        MobileInputSettings = {},
        BladeReach = 7,
        DashSpeed = 30,
        DashDuration = 0.4,
    },
}
assert(ItemPolicy.isDualModeBlade(dualMode))
assert(ItemPolicy.hasTargetedDamage(dualMode))
assert(ItemPolicy.isScoped({ Info = { AimScopePercent = 0.5 } }))
assert(ItemPolicy.isBurst({ Info = { BurstCount = 3 } }))
assert(not ItemPolicy.isBurst({ Name = "Burst Rifle", Info = {} }))
assert(ItemPolicy.automationPolicy({ Name = "Grenade", Info = {} }).cameraAim == false)

print("rivals-item-policy-contracts-ok")
