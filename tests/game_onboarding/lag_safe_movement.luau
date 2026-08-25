local roblox = require("@lune/roblox")
Vector3 = roblox.Vector3
CFrame = roblox.CFrame

local LagSafeMovement = require("../../games/stealanegg/features/LagSafeMovement")

local function signal()
    local current
    return {
        Connect = function(_, callback)
            current = callback
            return { Disconnect = function() end }
        end,
        Fire = function(_, value)
            current(value)
        end,
    }
end

local carryChanged = signal()
local callback
local heartbeat = {
    Connect = function(_, nextCallback)
        callback = nextCallback
        return { Disconnect = function() end }
    end,
}
local baitStops = 0
local escapeResumes = 0
local playerRoot
local humanoid = {
    Parent = true,
    WalkSpeed = 100,
    MoveTo = function(_, position)
        assert(position == playerRoot.Position)
        baitStops += 1
    end,
}
playerRoot = {
    Position = Vector3.zero,
    IsA = function(_, className)
        return className == "BasePart"
    end,
}
local areaId = "Cosmic"
local now = 0
local ping = 200
local guardPosition = Vector3.new(15, 0, 0)
local guardState = "Waking"
local player = {
    UserId = 42,
    Character = {
        FindFirstChild = function(_, name)
            return name == "HumanoidRootPart" and playerRoot or nil
        end,
        FindFirstChildOfClass = function(_, className)
            return className == "Humanoid" and humanoid or nil
        end,
    },
    GetAttribute = function(_, name)
        return name == "AreaId" and areaId or nil
    end,
}
local movement = LagSafeMovement.new({
    canOutrun = function(currentArea, playerSpeed)
        return currentArea == "Snow" or playerSpeed >= 250
    end,
    clock = function()
        return now
    end,
    eggCmds = {
        AreaEggCarryStateChanged = carryChanged,
        GetAreaEggSnapshot = function()
            return {
                Records = { { CarrierUserId = 42, State = "Carried", Uid = "egg" } },
            }
        end,
    },
    getPing = function()
        return ping
    end,
    guardConfigs = {
        Cosmic = { FlatRadius = 20, HitDistance = 4, WalkSpeed = 200 },
        Snow = { FlatRadius = 20, HitDistance = 10, WalkSpeed = 98 },
    },
    guardModels = {
        Cosmic = {
            Parent = true,
            GetAttribute = function(_, name)
                return name == "GuardState" and guardState or nil
            end,
            GetPivot = function()
                return CFrame.new(guardPosition)
            end,
        },
        Snow = {
            Parent = true,
            GetAttribute = function(_, name)
                return name == "GuardState" and guardState or nil
            end,
            GetPivot = function()
                return CFrame.new(guardPosition)
            end,
        },
    },
    localPlayer = player,
    onEscape = function()
        escapeResumes += 1
    end,
    runService = { Heartbeat = heartbeat },
})

movement:setEnabled(true)
callback()
assert(
    humanoid.WalkSpeed == 65 and baitStops == 0,
    "High ping must slow without cancelling forward movement"
)
now = 0.2
callback()
assert(humanoid.WalkSpeed == 65 and baitStops == 0, "Slow bait must hold before the ping lead")
now = 0.24
callback()
assert(
    humanoid.WalkSpeed == 100 and escapeResumes == 1,
    "Movement must resume before the replicated waking state can report a late hit"
)
guardState = "Chasing"
guardPosition = Vector3.new(60, 0, 0)
callback()
assert(
    humanoid.WalkSpeed == 100 and baitStops == 0,
    "A committed waking escape must keep full speed through the chase"
)
now = 0.8
guardState = "RetrievingEgg"
carryChanged:Fire({ IsCarrying = false, Uid = "egg" })
callback()
assert(humanoid.WalkSpeed == 100, "A transient hit drop must retain full escape speed")
now = 1
carryChanged:Fire({ IsCarrying = true, Uid = "egg" })
guardState = "Chasing"
now = 1.4
callback()
assert(
    humanoid.WalkSpeed == 65 and baitStops == 0,
    "Immediate Anti Hit reclaim must slow without stopping another escape"
)
now = 1.72
callback()
assert(
    humanoid.WalkSpeed == 100 and escapeResumes == 2,
    "Measured boss cadence must resume inside the immediate reclaim range"
)
areaId = "Snow"
guardPosition = Vector3.new(100, 0, 0)
guardState = "Waking"
callback()
assert(
    humanoid.WalkSpeed == 100,
    "High Ping Mode must stay off when native player speed already outruns the boss"
)
areaId = "Cosmic"
guardPosition = Vector3.new(200, 0, 0)
callback()
guardPosition = Vector3.new(100, 0, 0)
ping = 80
callback()
assert(humanoid.WalkSpeed == 100, "Low-ping servers must not apply the bait policy")
ping = 200
guardState = "Chasing"
now = 3
callback()
assert(humanoid.WalkSpeed == 65, "A new high-ping encounter must start a fresh bait phase")
movement:setPingThreshold(300)
callback()
assert(humanoid.WalkSpeed == 100, "The configured ping limit must control automatic activation")
humanoid.WalkSpeed = 250
movement:setPingThreshold(170)
callback()
assert(
    humanoid.WalkSpeed == 250,
    "Native head-start prediction must preserve full speed when the player escapes safely"
)
movement:stop()
assert(humanoid.WalkSpeed == 250, "Stopping must preserve an unmodified native speed")
print("lag-safe-movement-ok")
