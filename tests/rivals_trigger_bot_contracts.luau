local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
CFrame = roblox.CFrame
Vector3 = roblox.Vector3

local Definition = require("../games/rivals/Definition")
local Session = require("../games/rivals/Session")
local TriggerBot = require("../games/rivals/features/TriggerBot")

assert(table.find(Definition.sources, "games/rivals/features/TriggerBot"))
assert(TriggerBot.INTERVAL == 0)
assert(TriggerBot.weaponReady({ _shoot_cooldown = 2 }, 1) == false)
assert(TriggerBot.weaponReady({ _shoot_cooldown = 1 }, 1) == true)
assert(TriggerBot.fireDelay({ Info = { ShootCooldown = 0.05 } }, 0.1) == 0.05)

local session = Session.new()
session.settings = { shotAim = true, triggerBot = true }
session.aligned = { id = "aligned", visible = true }
session.presented = nil
assert(
    TriggerBot.target(session, session.aligned) == nil,
    "Silent Aim Trigger Bot must not fall back to aligned when presented is missing"
)

session.presented = { id = "presented", visible = true }
assert(TriggerBot.target(session, session.aligned).id == "presented")

session.settings.shotAim = false
assert(TriggerBot.target(session, session.aligned).id == "aligned")

local released = 0
local clicked = 0
local state = {
    fireHeld = false,
    held = false,
    nextAt = 0,
}
local ctx = {
    alignedTarget = session.aligned,
    taskCombatActive = false,
    inputCaptured = false,
    fighterActive = true,
    inCombat = true,
    state = state,
    taskDebug = {},
    weaponPolicy = {
        automationPolicy = function()
            return { triggerBot = true }
        end,
        isDualModeBlade = function()
            return false
        end,
        isSplashProjectile = function()
            return false
        end,
        isBackstabKnife = function()
            return false
        end,
        isScoped = function()
            return false
        end,
        isFanFirearm = function()
            return false
        end,
        isChargedBow = function()
            return false
        end,
        holdToFire = function()
            return false
        end,
        triggerDamageReady = function()
            return true
        end,
        sniperTriggerReady = function()
            return true
        end,
        adsSettled = function()
            return true
        end,
    },
    projectileAim = {
        isSplashProjectile = function()
            return false
        end,
    },
    targeting = {},
    taskCounterPolicy = {
        shouldForceSpray = function()
            return false
        end,
    },
    clock = function()
        return 1
    end,
    itemClock = function()
        return 1
    end,
    getFighter = function()
        return { EquippedItem = { Info = { ShootCooldown = 0.1 } } }
    end,
    selectTarget = function()
        error("Silent Aim must not reselect")
    end,
    isDeflecting = function()
        return false
    end,
    isGunGame = function()
        return false
    end,
    localFighterIsCrouching = function()
        return false
    end,
    fighterFor = function()
        return nil
    end,
    targetRootPosition = function()
        return nil
    end,
    releaseFire = function()
        released += 1
    end,
    clearAimPlan = function() end,
    camera = {
        CFrame = CFrame.new(0, 0, 0),
    },
    cameraController = {},
    click = function()
        clicked += 1
    end,
    aimClick = function() end,
    aimPress = function() end,
    aimRelease = function() end,
    press = function() end,
}

session.settings.shotAim = true
session.presented = nil
TriggerBot.update(session, ctx)
assert(clicked == 0 and released >= 1, "Missing presented target must not fire")

local wall = { Name = "Wall" }
local blocked = {
    visible = true,
    position = { X = 0, Y = 0, Z = 10 },
    character = {},
}
assert(
    TriggerBot.pathReady(blocked, { Info = { ShootCooldown = 0.1 } }, {
        weaponPolicy = ctx.weaponPolicy,
        projectileAim = ctx.projectileAim,
        targeting = {
            visibleHeadPoint = function()
                return nil
            end,
            visibleBodyPoint = function()
                return nil
            end,
        },
        camera = {
            CFrame = CFrame.new(0, 0, 0),
        },
        raycast = function()
            return { Instance = wall }
        end,
    }) == false,
    "On-screen hitscan must not fire when the bullet path is blocked"
)

local offScreen = {
    visible = false,
    projectileAim = { direction = true },
}
assert(
    TriggerBot.pathReady(offScreen, { Info = { IsProjectile = true, ProjectileSpeed = 120 } }, {
        weaponPolicy = ctx.weaponPolicy,
        projectileAim = {
            isSplashProjectile = function()
                return false
            end,
            isDirectProjectile = function()
                return true
            end,
        },
    }) == true,
    "A solved projectile path must fire even when the target is off screen"
)

local onScreenArc = {
    visible = true,
    position = { X = 0, Y = 0, Z = 20 },
}
assert(
    TriggerBot.pathReady(onScreenArc, { Info = { IsProjectile = true, ProjectileSpeed = 120 } }, {
        weaponPolicy = ctx.weaponPolicy,
        projectileAim = {
            isSplashProjectile = function()
                return false
            end,
            isDirectProjectile = function()
                return true
            end,
            solveProjectileAim = function()
                return nil
            end,
        },
        camera = ctx.camera,
    }) == false,
    "An on-screen projectile must not fire without a solved bullet path"
)

local adapter = fs.readFile("games/rivals/Adapter.lua")
assert(adapter:find("raycast = type(environmentRaycast)", 1, true))
local source = fs.readFile("games/rivals/features/TriggerBot.lua")
assert(source:find("TriggerBot.pathReady", 1, true))
assert(source:find("TriggerBot.weaponReady", 1, true))
assert(source:find("ctx.selectTarget(nil, true, true)", 1, true))
assert(not source:find("not target.visible", 1, true))
assert(not source:find("0.35", 1, true), "Hold-to-fire must not restart after an ammo-replica stall")
assert(not source:find("target.screenDistance or math.huge) > radius", 1, true), "Trigger Bot must not require an 8px reticle")

session.settings.shotAim = false
session.aligned = { visible = true, position = Vector3.new(0, 0, 10), aimSettled = true }
ctx.alignedTarget = session.aligned
ctx.targeting.visibleHeadPoint = function()
    return Vector3.new(0, 0, 10)
end
ctx.raycast = function()
    return nil
end
clicked = 0
state.nextAt = 0
TriggerBot.update(session, ctx)
assert(clicked == 1, "A ready semi must fire on the first ready frame")
TriggerBot.update(session, ctx)
assert(clicked == 2, "A ready semi must not wait on a 0.1s hub interval")

print("rivals-trigger-bot-contracts-ok")
