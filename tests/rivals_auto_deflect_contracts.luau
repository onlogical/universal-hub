local roblox = require("@lune/roblox")
Vector3 = roblox.Vector3

local Definition = require("../games/rivals/Definition")
local AutoDeflect = require("../games/rivals/features/AutoDeflect")
local WeaponPolicy = require("../games/rivals/libraries/WeaponPolicy")

assert(table.find(Definition.sources, "games/rivals/features/AutoDeflect"))

local origin = Vector3.new(0, 5, 0)
local look = Vector3.new(0, 0, -1)
local point = Vector3.new(0, 5, -20)
assert(AutoDeflect.looksAt(origin, look, point) == true)
assert(AutoDeflect.looksAt(origin, Vector3.new(1, 0, 0), point) == false)

local sniper = {
    Info = {
        AimScopePercent = 0.8,
        ShootDamage = 40,
        CriticalDamage = 120,
    },
    Get = function(_self, key)
        return key == "IsAiming"
    end,
    Data = { IsAiming = true },
}
assert(WeaponPolicy.isScoped(sniper))
assert(WeaponPolicy.isAiming(sniper))
assert(AutoDeflect.lethalShot(sniper, 100, 20, WeaponPolicy) == true)
assert(AutoDeflect.lethalShot(sniper, 200, 20, WeaponPolicy) == false)
assert(AutoDeflect.lethalShot({ Info = { ShootDamage = 12 } }, 20, 10, WeaponPolicy) == false)
assert(AutoDeflect.lethalShot({
    Info = { AimScopePercent = 0.8, ShootDamage = 40, CriticalDamage = 120 },
    Data = { IsAiming = false },
}, 100, 20, WeaponPolicy) == true, "Katana reflect must not wait for the attacker to ADS")

local ours = {
    HumanoidRootPart = { Position = Vector3.new(0, 5, -20) },
}
local opponent = {
    character = {
        Head = { CFrame = { Position = origin, LookVector = (point - origin).Unit } },
    },
    EquippedItem = sniper,
}
local katana = {
    _deflect_hash = 1,
    Info = { DeflectDuration = 1, DeflectCooldown = 4 },
}
assert(AutoDeflect.shouldBlock({ EquippedItem = katana }, opponent, {
    weaponPolicy = WeaponPolicy,
    health = 100,
    character = ours,
}) == true)
assert(AutoDeflect.shouldBlock({ EquippedItem = katana }, opponent, {
    weaponPolicy = WeaponPolicy,
    health = 100,
    character = ours,
    itemClock = function()
        return 1
    end,
}) == true)
assert(AutoDeflect.shouldBlock({
    EquippedItem = { _deflect_hash = 1, _deflect_cooldown = 2, Info = katana.Info },
}, opponent, {
    weaponPolicy = WeaponPolicy,
    health = 100,
    character = ours,
    itemClock = function()
        return 1
    end,
}) == false)
assert(AutoDeflect.ready({ _deflect_cooldown = 2 }, 1) == false)
assert(AutoDeflect.ready({ _deflect_cooldown = 1 }, 1) == true)

local clicks = 0
assert(AutoDeflect.update({ autoDeflect = true }, {
    inputCaptured = false,
    fighterActive = true,
    inCombat = true,
    getFighter = function()
        return { EquippedItem = katana }
    end,
    weaponPolicy = WeaponPolicy,
    health = 100,
    character = ours,
    opponents = { opponent },
    aimClick = function()
        clicks += 1
    end,
    taskDebug = {},
}) == true)
assert(clicks == 1)

assert(AutoDeflect.update({ autoDeflect = true }, {
    inputCaptured = true,
    fighterActive = true,
    inCombat = true,
    getFighter = function()
        return { EquippedItem = katana }
    end,
    weaponPolicy = WeaponPolicy,
    opponents = { opponent },
    aimClick = function()
        clicks += 1
    end,
}) == false)

print("rivals-auto-deflect-contracts-ok")
