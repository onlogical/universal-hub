local ItemPolicy = {}

local ENABLED = {
    cameraAim = true,
    silentAim = true,
    triggerBot = true,
}
local DISABLED = {
    cameraAim = false,
    silentAim = false,
    triggerBot = false,
}

local function info(item)
    return type(item) == "table" and type(item.Info) == "table" and item.Info or nil
end

local function positive(value)
    return type(value) == "number" and value > 0
end

function ItemPolicy.isThrowable(item)
    local itemInfo = info(item)
    return itemInfo ~= nil
        and positive(itemInfo.ThrowMaxChargeTime)
        and positive(itemInfo.ThrowForceMax)
        and type(item.StartShooting) == "function"
        and type(item.FinishShooting) == "function"
end

function ItemPolicy.isBackstab(item)
    local itemInfo = info(item)
    return itemInfo ~= nil
        and type(item._backstab_hash) == "number"
        and positive(itemInfo.CriticalDamage)
        and positive(itemInfo.HeavyAttackReach)
        and positive(itemInfo.HeavyAttackCooldown)
end

function ItemPolicy.isDualModeBlade(item)
    local itemInfo = info(item)
    return itemInfo ~= nil
        and type(item.GetMobileInputSettings) == "function"
        and type(itemInfo.BladeModeMobileInputSettings) == "table"
        and type(itemInfo.MobileInputSettings) == "table"
        and positive(itemInfo.BladeReach)
        and positive(itemInfo.DashSpeed)
        and positive(itemInfo.DashDuration)
end

function ItemPolicy.isScoped(item)
    local itemInfo = info(item)
    return itemInfo ~= nil and positive(itemInfo.AimScopePercent)
end

function ItemPolicy.isBurst(item)
    local itemInfo = info(item)
    return itemInfo ~= nil and type(itemInfo.BurstCount) == "number" and itemInfo.BurstCount > 1
end

function ItemPolicy.hasDeflectCapability(item)
    local itemInfo = info(item)
    return itemInfo ~= nil
        and positive(itemInfo.DeflectDuration)
        and positive(itemInfo.DeflectCooldown)
end

function ItemPolicy.isDeflector(item)
    return ItemPolicy.hasDeflectCapability(item)
        and type(item._deflect_hash) == "number"
end

function ItemPolicy.isActivelyDeflecting(item)
    if not ItemPolicy.hasDeflectCapability(item) then
        return false
    end
    if type(item.Get) == "function" then
        local succeeded, value = pcall(item.Get, item, "FOVOffset")
        if succeeded and value == 5 then
            return true
        end
    end
    local data = item.Data
    return type(data) == "table" and data.FOVOffset == 5
end

function ItemPolicy.isRicochetWeapon(item)
    local itemInfo = info(item)
    return itemInfo ~= nil
        and type(itemInfo.RaycastBounceCount) == "number"
        and itemInfo.RaycastBounceCount > 0
end

function ItemPolicy.isBouncingProjectile(item)
    local itemInfo = info(item)
    return itemInfo ~= nil
        and itemInfo.IsProjectile == true
        and positive(itemInfo.ProjectileSpeed)
        and type(itemInfo.ProjectileMaxHits) == "number"
        and itemInfo.ProjectileMaxHits > 1
end

function ItemPolicy.isFanFirearm(item)
    local itemInfo = info(item)
    return itemInfo ~= nil
        and positive(itemInfo.QuickShotCooldown)
        and positive(itemInfo.QuickShotSpread)
        and positive(itemInfo.ShootCooldown)
end

function ItemPolicy.isChargedBow(item)
    local itemInfo = info(item)
    return itemInfo ~= nil
        and itemInfo.IsProjectile == true
        and positive(itemInfo.ChargeReleaseCooldown)
        and type(itemInfo.ChargeLevelTimestamps) == "table"
        and type(itemInfo.ChargeLevelDamageMultipliers) == "table"
end

function ItemPolicy.isTrueDamage(item)
    local itemInfo = info(item)
    return itemInfo ~= nil and itemInfo.DealsTrueDamage == true
end

function ItemPolicy.isAbsorber(item)
    local itemInfo = info(item)
    return itemInfo ~= nil and positive(itemInfo.MaxAbsorption)
end

function ItemPolicy.isRevolver(item)
    return ItemPolicy.isFanFirearm(item)
end

function ItemPolicy.isChargedProjectile(item)
    return ItemPolicy.isChargedBow(item)
end

function ItemPolicy.isTrueDamageBurst(item)
    return ItemPolicy.isTrueDamage(item) and ItemPolicy.isBurst(item)
end

function ItemPolicy.isContinuous(item)
    local itemInfo = info(item)
    return itemInfo ~= nil and positive(itemInfo.InternalUseCooldown)
end

function ItemPolicy.hasTargetedDamage(item)
    local itemInfo = info(item)
    if not itemInfo or ItemPolicy.isThrowable(item) then
        return false
    end
    return positive(itemInfo.ShootDamage)
        or positive(itemInfo.AttackDamage)
        or positive(itemInfo.CriticalDamage)
        or ItemPolicy.isDualModeBlade(item)
        or ItemPolicy.isContinuous(item)
end

function ItemPolicy.automationPolicy(item)
    return ItemPolicy.hasTargetedDamage(item) and ENABLED or DISABLED
end

return ItemPolicy
