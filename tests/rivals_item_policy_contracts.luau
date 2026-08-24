local fs = require("@lune/fs")
local ItemPolicy = require("../games/rivals/libraries/ItemPolicy")

local policySources = fs.readFile("games/rivals/libraries/WeaponPolicy.lua")
    .. fs.readFile("games/rivals/libraries/ProjectileAim.lua")
    .. fs.readFile("games/rivals/Adapter.lua")
for _, displayName in ipairs({
    "Energy Rifle",
    "Slingshot",
    "Gunblade",
    "Sniper",
    "Burst Rifle",
    "Glast Shard",
    "Katana",
    "Revolver",
    "Bow",
    "Riot Shield",
}) do
    assert(
        not policySources:find('"' .. displayName .. '"', 1, true),
        displayName .. " must not select runtime behavior"
    )
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

local continuous = { Info = { InternalUseCooldown = 0.25, MaxAmmo = 100 } }
assert(ItemPolicy.isContinuous(continuous))
assert(
    ItemPolicy.hasTargetedDamage(continuous),
    "A stream weapon must be triggerable without a per-shot damage field"
)
assert(ItemPolicy.automationPolicy(continuous).triggerBot == true)
assert(not ItemPolicy.isContinuous({ Info = { ShootDamage = 12 } }))

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

assert(ItemPolicy.isFanFirearm({
    Info = { QuickShotCooldown = 0.15, QuickShotSpread = 10, ShootCooldown = 0.4 },
}))
assert(not ItemPolicy.isFanFirearm({ Name = "Revolver", Info = { ShootCooldown = 0.4 } }))
assert(ItemPolicy.isChargedBow({
    Info = {
        ChargeLevelDamageMultipliers = { 1, 2 },
        ChargeLevelTimestamps = { 0, 1 },
        ChargeReleaseCooldown = 1,
        IsProjectile = true,
    },
}))
assert(not ItemPolicy.isChargedBow({ Name = "Bow", Info = { ChargeReleaseCooldown = 1 } }))
assert(ItemPolicy.isTrueDamage({ Info = { DealsTrueDamage = true } }))
assert(not ItemPolicy.isTrueDamage({ Name = "Spray", Info = {} }))
local sprayCapabilities = ItemPolicy.capabilities({
    Info = { Type = "Gun", Class = "Secondary", DealsTrueDamage = true, ShootDamage = 8 },
})
assert(sprayCapabilities.attack == "gun")
assert(sprayCapabilities.bypassesDeflection == true)
assert(sprayCapabilities.maxDoubleJumps == 0)
local fistCapabilities = ItemPolicy.capabilities({
    _attack_hash = 3,
    Info = {
        Type = "Melee",
        Class = "Melee",
        AttackDamage = 30,
        AttackCooldown = 0.35,
        MaxDoubleJumps = 1,
    },
})
assert(fistCapabilities.attack == "melee")
assert(fistCapabilities.bypassesDeflection == true)
assert(fistCapabilities.maxDoubleJumps == 1)
assert(ItemPolicy.capabilities({
    Info = { Type = "Gun", Class = "Primary", ShootDamage = 12 },
}).bypassesDeflection == false)
assert(ItemPolicy.isAbsorber({ Info = { MaxAbsorption = 500 } }))
assert(not ItemPolicy.isAbsorber({ Name = "Riot Shield", Info = {} }))
local deflectInfo = { DeflectDuration = 1, DeflectCooldown = 4 }
assert(ItemPolicy.hasDeflectCapability({ Info = deflectInfo }))
assert(ItemPolicy.isDeflector({ _deflect_hash = 0, Info = deflectInfo }))
assert(
    not ItemPolicy.isDeflector({ Info = deflectInfo }),
    "A catalog-shaped deflector must still require a live deflect hash"
)
assert(
    ItemPolicy.isActivelyDeflecting({
        Info = deflectInfo,
        Get = function()
            return 0
        end,
        Data = { FOVOffset = 5 },
    }),
    "A default Get must not hide a replicated block FOV"
)
assert(ItemPolicy.isActivelyDeflecting({
    Info = deflectInfo,
    Get = function()
        return 5
    end,
    Data = { FOVOffset = 0 },
}))
assert(not ItemPolicy.isActivelyDeflecting({
    Info = deflectInfo,
    Get = function()
        return 0
    end,
    Data = { FOVOffset = 0 },
}))
assert(
    policySources:find("FighterController.GetFighter", 1, true),
    "fighter lookup must prefer the public GetFighter seam"
)
assert(
    policySources:find("CameraController.GetCurrentSubject", 1, true),
    "active-subject checks must prefer GetCurrentSubject"
)
assert(
    policySources:find("WeaponPolicy.isFanFirearm", 1, true),
    "Revolver trigger must use the fan-firearm policy"
)
assert(
    policySources:find("WeaponPolicy.isChargedBow", 1, true),
    "Bow trigger must use the charged-projectile policy"
)

print("rivals-item-policy-contracts-ok")
