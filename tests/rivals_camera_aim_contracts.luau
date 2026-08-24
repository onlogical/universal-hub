local roblox = require("@lune/roblox")
Vector2 = roblox.Vector2
Vector3 = roblox.Vector3
CFrame = roblox.CFrame

local CameraAim = require("../games/rivals/features/CameraAim")
local Definition = require("../games/rivals/Definition")
local ProjectileAim = require("../games/rivals/libraries/ProjectileAim")
local Targeting = require("../games/rivals/libraries/Targeting")
local WeaponPolicy = require("../games/rivals/libraries/WeaponPolicy")

local cameraAimSource = require("@lune/fs").readFile("games/rivals/features/CameraAim.lua")
assert(
    cameraAimSource:find("ctx.selectTarget(nil, true, false, true)", 1, true),
    "Camera Aim must prefer a visible in-FOV target before a blocked fallback"
)

assert(table.find(Definition.sources, "games/rivals/features/CameraAim"))
assert(table.find(Definition.sources, "games/rivals/Session"))

assert(
    CameraAim.enabled({ silentAim = true, shotAim = false }, false, false) == true,
    "Camera Aim runs when silentAim is on and Silent Aim is off"
)
assert(
    CameraAim.enabled({ silentAim = true, shotAim = true }, false, false) == false,
    "Camera Aim must not rotate the camera while Silent Aim is on"
)
assert(
    CameraAim.enabled({ silentAim = false, shotAim = true }, true, false) == true,
    "The Silent Aim planning pass is shotOnly"
)
assert(
    CameraAim.enabled({ silentAim = false, shotAim = false }, false, true) == true,
    "Task combat may aim without the Camera Aim setting"
)
assert(
    CameraAim.enabled({ silentAim = false, shotAim = false }, false, false) == false,
    "Neither setting nor task combat means no aim plan"
)

assert(
    CameraAim.shouldClearRetention({ silentAim = true, shotAim = true }, false, false, true, true)
        == false,
    "Silent Aim must keep the retained target while Camera Aim is gated off"
)
assert(
    CameraAim.shouldClearRetention({ silentAim = false, shotAim = false }, false, false, true, true)
        == true,
    "Both aim features off must drop retention"
)
assert(
    CameraAim.shouldClearRetention({ silentAim = true, shotAim = false }, false, true, true, true)
        == true,
    "Input capture outside task combat must drop retention"
)

local origin = Vector3.new(0, 2, 0)
local targetPosition = Vector3.new(10, 2, -4)
local target = {
    character = { Name = "dummy" },
    position = targetPosition,
    visible = true,
    health = 80,
    distance = 10,
}
local item = { Info = { ShootDamage = 24 } }
local rotations = {}
local instantRotations = {}
local retentionClears = 0
local remembered = {}

local function context(overrides)
    local ctx = {
        shotOnly = false,
        taskCombatActive = false,
        settings = { silentAim = true, shotAim = false },
        inputCaptured = false,
        fighterActive = true,
        inCombat = true,
        fighter = {
            EquippedItem = item,
            Entity = { RootPart = { Position = origin } },
        },
        camera = {
            CFrame = CFrame.new(origin),
        },
        clock = function()
            return 1
        end,
        renderDelta = 1 / 60,
        gravity = 196.2,
        getNetworkPing = function()
            return 0
        end,
        environmentRaycast = function()
            return function()
                return nil
            end
        end,
        solveBouncingProjectile = function()
            return nil
        end,
        solveSplashAim = function()
            return nil
        end,
        solveRicochet = function()
            return nil
        end,
        setAimRotation = function(rotation, instant)
            table.insert(rotations, rotation)
            table.insert(instantRotations, instant)
            return true
        end,
        selectTarget = function()
            return target
        end,
        selectBackstabTarget = function()
            return nil
        end,
        taskNavigationObservation = function()
            return nil
        end,
        plannedAimTarget = function(selected)
            return selected
        end,
        taskDebug = {},
        clearRetention = function()
            retentionClears += 1
        end,
        rememberWeapon = function(equipped)
            remembered.weapon = equipped
        end,
        rememberTarget = function(selected)
            remembered.target = selected
        end,
        clearTargetKey = function()
            remembered.target = nil
        end,
    }
    for key, value in pairs(overrides or {}) do
        ctx[key] = value
    end
    return ctx
end

local cameraAim = CameraAim.new({
    targeting = Targeting,
    projectileAim = ProjectileAim,
    weaponPolicy = WeaponPolicy,
})
assert(cameraAim:align(context({
    settings = { silentAim = false, shotAim = false },
})) == nil and retentionClears == 1, "A disabled Camera Aim must not invent a plan")

local aligned = cameraAim:align(context())
assert(
    aligned
        and aligned.position == targetPosition
        and aligned.aimSettled == true
        and aligned.visible == true
        and remembered.weapon == item
        and remembered.target == target
        and #rotations == 1
        and rotations[1] == Targeting.rotationToward(origin, targetPosition),
    "Camera Aim must settle on the selected target without picking another"
)

local silentRotations = #rotations
local silentAligned = cameraAim:align(context({
    shotOnly = true,
    settings = { silentAim = false, shotAim = true },
}))
assert(
    silentAligned and silentAligned.aimSettled == true and #rotations == silentRotations,
    "The Silent Aim planning pass must not move the camera"
)

local offScreen = {
    character = { Name = "behind" },
    position = Vector3.new(-20, 2, 8),
    visible = false,
    health = 80,
    distance = 22,
}
local offScreenSelects = {}
local offScreenAligned = cameraAim:align(context({
    selectTarget = function(_radius, includeBlocked, ignoreAimFov, preferVisible)
        table.insert(offScreenSelects, {
            includeBlocked = includeBlocked,
            ignoreAimFov = ignoreAimFov,
            preferVisible = preferVisible,
        })
        return offScreen
    end,
}))
assert(
    offScreenAligned
        and offScreenAligned.position == offScreen.position
        and offScreenAligned.aimSettled == true
        and #offScreenSelects == 1
        and offScreenSelects[1].includeBlocked == true
        and offScreenSelects[1].ignoreAimFov == false
        and offScreenSelects[1].preferVisible == true
        and instantRotations[#instantRotations] == false
        and rotations[#rotations] == Targeting.rotationToward(origin, offScreen.position),
    "Camera Aim must use its FOV and normal smoothing for a blocked fallback"
)

print("rivals-camera-aim-contracts-ok")
