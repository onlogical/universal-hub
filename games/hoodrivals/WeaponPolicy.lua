local WeaponPolicy = {}

local SCOPED = {
    R700 = true,
    ["223Rifle"] = true,
}

local MANUAL_FIRE = {
    R700 = true,
    Sawedoff = true,
    PumpShotgun = true,
    Killtec = true,
}

function WeaponPolicy.profile(weapon, data)
    local stats = weapon and weapon:FindFirstChild("Stats")
    local gunType = stats and stats:FindFirstChild("GunType")
    local shots = stats and stats:FindFirstChild("Shots")
    local fireRate = stats and stats:FindFirstChild("FireRate")
    return {
        scoped = weapon ~= nil and SCOPED[weapon.Name] == true,
        manualFire = weapon ~= nil and MANUAL_FIRE[weapon.Name] == true,
        binary = gunType ~= nil and gunType.Value == "Binary",
        pelletCount = shots and shots.Value or 1,
        nativeFireRate = fireRate and fireRate.Value or data and data.FireRate or 0.1,
        damageRadius = data and data.DamageRadius or 1.15,
    }
end

return WeaponPolicy
