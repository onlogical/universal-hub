local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
CFrame = roblox.CFrame
Vector3 = roblox.Vector3

local Definition = require("../games/rivals/Definition")
local Session = require("../games/rivals/Session")
local TeleportBehind = require("../games/rivals/features/TeleportBehind")

assert(table.find(Definition.sources, "games/rivals/features/TeleportBehind"))
assert(table.find(Definition.features.capabilities, "teleportBehind"))
assert(Definition.defaults.teleportBehind == false)
assert(Definition.features.optionLabels.teleportBehind == "Warp")
assert(Definition.defaults.teleportOneShot == nil)
assert(not table.find(Definition.features.capabilities, "teleportOneShot"))
assert(TeleportBehind.DISTANCE == 56)
assert(TeleportBehind.HEIGHT == 64)
assert(TeleportBehind.HOP_RATE == 16)
assert(TeleportBehind.hopIndex(0) == 0)
assert(TeleportBehind.hopIndex(1 / 16) == 1)
local gunDistance, gunHeight = TeleportBehind.range()
assert(gunDistance == 56 and gunHeight == 64)

local source = fs.readFile("games/rivals/features/TeleportBehind.lua")
local adapter = fs.readFile("games/rivals/Adapter.lua")
assert(not string.find(source, "importDependency", 1, true))
assert(not string.find(source, "FireServer", 1, true))
assert(not string.find(source, "Anchored", 1, true), "Anchoring the root stops CFrame from replicating")
assert(string.find(source, "CFrame.lookAt(position, lookAt)", 1, true))
assert(string.find(source, "TeleportBehind.pullIn", 1, true))
assert(string.find(source, "TeleportBehind.canSee", 1, true))
assert(string.find(source, "TeleportBehind.isImmune", 1, true))
assert(string.find(adapter, "if settings.teleportBehind == true then", 1, true))
assert(string.find(adapter, "startTeleportPhysics()", 1, true))
assert(string.find(adapter, "TeleportBehind.update(session", 1, true))
assert(
    not string.find(adapter, "settings.teleportBehind == true or not settingsSubscription", 1, true)
        and not string.find(adapter, "or not settingsSubscription then\n            startTeleportPhysics", 1, true),
    "Warp must not start physics on the first frame before settings have subscribed"
)
assert(string.find(adapter, "raycast = function(origin, displacement)", 1, true))
local environmentAssign = string.find(adapter, "local environmentRaycast = context.environmentRaycast", 1, true)
local teleportRaycast = string.find(adapter, "local cast = environmentRaycast()", 1, true)
assert(
    environmentAssign and teleportRaycast and environmentAssign < teleportRaycast,
    "Warp raycast must close over the assigned environmentRaycast factory"
)
assert(string.find(adapter, "isImmune = function()", 1, true))
assert(string.find(adapter, "weaponMode = function()", 1, true))
assert(string.find(source, "TeleportBehind.knifeDestination", 1, true))
assert(string.find(source, "CLOSE_DISTANCE", 1, true))
assert(string.find(adapter, "TeleportBehind.hold(session", 1, true))
assert(not string.find(adapter, "libs.freeze", 1, true), "Firing must not park the barrage")
assert(string.find(adapter, "TeleportBehind.aimPoint(movedRoot.Position, lookTarget)", 1, true))
assert(string.find(adapter, "setAimRotation(", 1, true))
assert(string.find(adapter, "RunService.Heartbeat:Connect", 1, true))
assert(string.find(adapter, "RunService.Stepped:Connect", 1, true))
assert(string.find(adapter, "alignedTarget.aimSettled = true", 1, true))
assert(not string.find(adapter, "alignedTarget = alignCamera(false, taskCombatActive)\n                if not alignedTarget and settings.shotAim then\n                    alignedTarget = alignCamera(true, taskCombatActive)\n                end\n                session.aligned = alignedTarget\n            end\n        elseif settingsSubscription then", 1, true), "A second Camera Aim pass after the hop uses the stale camera")
assert(TeleportBehind.OOB_TAG == "OutOfBoundsPart")

local targetRoot = {
    CFrame = CFrame.lookAt(Vector3.new(10, 2, 0), Vector3.new(11, 2, 0)),
}
local target = {
    character = {
        FindFirstChild = function(_self, name)
            return name == "HumanoidRootPart" and targetRoot or nil
        end,
    },
}

local function offsetFrom(position)
    return Vector3.new(
        position.X - targetRoot.CFrame.Position.X,
        0,
        position.Z - targetRoot.CFrame.Position.Z
    )
end

local first = TeleportBehind.destination(target, 0)
assert(first)
assert(first.Position.Y - targetRoot.CFrame.Position.Y >= 40)
assert(
    (first.Position - targetRoot.CFrame.Position).Magnitude < 130,
    "The orbit must stay in hitscan range"
)
local nextSlot = TeleportBehind.destination(target, 1 / 16)
assert(nextSlot)
local firstPlanar = offsetFrom(first.Position)
local nextPlanar = offsetFrom(nextSlot.Position)
assert(firstPlanar.Magnitude > 1 and nextPlanar.Magnitude > 1)
assert(
    firstPlanar.Unit:Dot(nextPlanar.Unit) < 0.5,
    "Hops must choose a new side around the enemy"
)
local stacked = Session.new()
assert(TeleportBehind.focusY(stacked, 2) == 2)
targetRoot.CFrame = CFrame.lookAt(Vector3.new(10, 80, 0), Vector3.new(11, 80, 0))
assert(TeleportBehind.focusY(stacked, 80) == 2, "Do not stack height on another airborne teleporter")
local grounded = TeleportBehind.destination(target, 0, 56, 64, nil, 0, 2)
assert(grounded.Position.Y == 66)
targetRoot.CFrame = CFrame.lookAt(Vector3.new(10, 2, 0), Vector3.new(11, 2, 0))

local wall = {
    CFrame = CFrame.new(10 + 56, 66, 0),
    Size = Vector3.new(20, 40, 20),
}
local function wallBlocks(position)
    return TeleportBehind.insidePart(wall, position)
end
assert(TeleportBehind.clear(wall.CFrame.Position, wallBlocks) == false)
local pulled = TeleportBehind.pullIn(
    targetRoot.CFrame.Position,
    wall.CFrame.Position,
    wallBlocks
)
assert(pulled)
assert(TeleportBehind.insidePart(wall, pulled) == false)
assert((pulled - targetRoot.CFrame.Position).Magnitude >= TeleportBehind.MIN_DISTANCE)
local clipped = TeleportBehind.destination(target, 0, 56, 64, wallBlocks, 0, 2)
assert(clipped)
assert(TeleportBehind.insidePart(wall, clipped.Position) == false)

assert(TeleportBehind.AIM_TORSO == 1)
assert(TeleportBehind.HIGH_AIM == 12)
local lookAt = TeleportBehind.lookPoint(target)
local highFrom = targetRoot.CFrame.Position + Vector3.new(0, 64, 56)
local highAim = TeleportBehind.aimPoint(highFrom, target)
assert(highAim)
assert(highAim.Y == targetRoot.CFrame.Position.Y + TeleportBehind.AIM_TORSO)
assert(
    highAim.Y < lookAt.Y or lookAt.Y == targetRoot.CFrame.Position.Y + 2,
    "A sky slot must aim at the torso, not the head"
)
local levelAim = TeleportBehind.aimPoint(targetRoot.CFrame.Position + Vector3.new(-8, 0, 0), target)
assert(levelAim == lookAt, "A level slot may keep the normal look point")
assert(TeleportBehind.canSee(clipped.Position, lookAt, function()
    return nil
end) == true)
assert(TeleportBehind.canSee(clipped.Position, lookAt, function()
    return { Instance = true }
end) == false)
local blocked = TeleportBehind.destination(target, 0, 56, 64, nil, 0, 2, function(origin)
    if origin.X > 40 then
        return { Instance = true }
    end
    return nil
end)
assert(blocked)
assert(blocked.Position.X <= 40, "A blocked slot must hop to a side with line of sight")

local skyBlocked = TeleportBehind.destination(target, 0, 56, 64, function(position)
    return position.Y > 20
end, 0, 2)
assert(skyBlocked)
assert(
    skyBlocked.Position.Y - targetRoot.CFrame.Position.Y <= 16,
    "A blocked sky slot must fall in to the close pocket"
)

local facing = CFrame.lookAt(Vector3.new(10, 2, 0), Vector3.new(20, 2, 0))
targetRoot.CFrame = facing
local knife = TeleportBehind.knifeDestination(target, nil, nil, 2)
assert(knife)
assert(
    (knife.Position - facing.Position).Magnitude < 12,
    "Knife One Shot must stand in backstab reach"
)
assert(facing.LookVector:Dot((knife.Position - facing.Position).Unit) < 0, "Knife One Shot must stand behind")
targetRoot.CFrame = CFrame.lookAt(Vector3.new(10, 2, 0), Vector3.new(11, 2, 0))

local shielded = {
    FindFirstChildOfClass = function(_self, className)
        return className == "ForceField" and {} or nil
    end,
}
assert(TeleportBehind.hasForceField(shielded) == true)
assert(TeleportBehind.hasForceField(target.character) == false)
local immuneSession = Session.new()
immuneSession.settings = { teleportBehind = true }
immuneSession.active = true
immuneSession.inCombat = true
assert(TeleportBehind.update(immuneSession, {
    getRoot = function()
        return { CFrame = CFrame.new(0, 2, 0) }
    end,
    getCharacter = function()
        return shielded
    end,
    selectTarget = function()
        return target
    end,
}) == false, "Spawn ForceField must wait out immunity")

local session = Session.new()
local localRoot = {
    CFrame = CFrame.new(0, 2, 0),
    AssemblyLinearVelocity = Vector3.new(0, -40, 0),
}
local humanoid = { PlatformStand = false }
local selected = 0
local now = 0
local libs = {
    clock = function()
        return now
    end,
    getRoot = function()
        return localRoot
    end,
    getHumanoid = function()
        return humanoid
    end,
    selectTarget = function()
        selected += 1
        return target
    end,
}

assert(TeleportBehind.update(session, libs) == false, "Off by default")
session.settings = { teleportBehind = true }
session.active = true
session.inCombat = true
assert(TeleportBehind.update(session, libs) == true)
assert(selected == 1)
assert((localRoot.CFrame.Position - targetRoot.CFrame.Position).Magnitude > 16)
assert(humanoid.PlatformStand == true)

session.aligned = target
local firstHop = localRoot.CFrame
now = 1
assert(TeleportBehind.update(session, libs) == true)
assert(selected == 1)
assert((localRoot.CFrame.Position - firstHop.Position).Magnitude > 1)

local hopped = localRoot.CFrame
libs.freeze = true
now = 3
assert(TeleportBehind.update(session, libs) == true)
assert(
    (localRoot.CFrame.Position - hopped.Position).Magnitude > 1,
    "Firing must not park the barrage on the first lock"
)

local held = localRoot.CFrame
session.presented = nil
session.aligned = nil
libs.selectTarget = function()
    selected += 1
    return nil
end
localRoot.CFrame = CFrame.new(0, 2, 0)
assert(TeleportBehind.update(session, libs) == true, "A missing target must keep the last safe hold")
assert((localRoot.CFrame.Position - held.Position).Magnitude < 1e-4)
assert(TeleportBehind.hold(session, libs) == true)

session.inCombat = false
session.active = false
localRoot.CFrame = CFrame.new(0, 2, 0)
assert(TeleportBehind.update(session, libs) == true, "Once engaged, combat flicker must not drop the hold")

session.aligned = target
libs.selectTarget = function()
    return target
end
session.inputCaptured = true
session.taskCombat = false
localRoot.CFrame = CFrame.new(0, 2, 0)
now = 0
assert(TeleportBehind.update(session, libs) == true, "Menu capture must not drop the sky hold")
assert(humanoid.PlatformStand == true)

session.inputCaptured = false
session.inCombat = true
session.active = true
now = 0
session.teleportHop = nil
session.teleportYaw = nil
libs.isOutOfBounds = wallBlocks
assert(TeleportBehind.update(session, libs) == true)
assert(TeleportBehind.insidePart(wall, localRoot.CFrame.Position) == false)

local fresh = Session.new()
fresh.settings = { teleportBehind = true }
fresh.active = true
fresh.inCombat = true
local freshRoot = { CFrame = CFrame.new(0, 2, 0) }
assert(TeleportBehind.update(fresh, {
    getRoot = function()
        return freshRoot
    end,
    isOutOfBounds = function()
        return true
    end,
    selectTarget = function()
        return target
    end,
}) == false)
assert(freshRoot.CFrame.Position.X == 0)

session.settings = { teleportBehind = false }
assert(TeleportBehind.update(session, libs) == false)
assert(humanoid.PlatformStand == false)

local sniper = Session.new()
sniper.settings = { teleportBehind = true }
sniper.active = true
sniper.inCombat = true
sniper.aligned = target
local sniperRoot = { CFrame = CFrame.new(0, 2, 0) }
local sniperNow = 0
local sniperLibs = {
    clock = function()
        return sniperNow
    end,
    getRoot = function()
        return sniperRoot
    end,
    getHumanoid = function()
        return { PlatformStand = false }
    end,
    weaponMode = function()
        return "sniper"
    end,
}
assert(TeleportBehind.update(sniper, sniperLibs) == true)
local sniperSlot = sniperRoot.CFrame
sniperNow = 2
assert(TeleportBehind.update(sniper, sniperLibs) == true)
assert(
    (sniperRoot.CFrame.Position - sniperSlot.Position).Magnitude < 1e-4,
    "Sniper One Shot must hold the angle"
)

print("rivals-teleport-behind-contracts-ok")
