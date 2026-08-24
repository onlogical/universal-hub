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
local humanoid = { Parent = true, WalkSpeed = 100 }
local areaId = "Cosmic"
local ping = 200
local player = {
    UserId = 42,
    Character = {
        FindFirstChildOfClass = function(_, className)
            return className == "Humanoid" and humanoid or nil
        end,
    },
    GetAttribute = function(_, name)
        return name == "AreaId" and areaId or nil
    end,
}
local movement = LagSafeMovement.new({
    eggCmds = {
        AreaEggCarryStateChanged = carryChanged,
        GetAreaEggSnapshot = function()
            return {
                Records = { { CarrierUserId = 42, State = "Carried" } },
            }
        end,
    },
    getPing = function()
        return ping
    end,
    guardSpeeds = { Cosmic = 200, Snow = 98 },
    localPlayer = player,
    runService = { Heartbeat = heartbeat },
})

movement:setEnabled(true)
callback()
assert(humanoid.WalkSpeed == 65, "Already-carried eggs must immediately use the safer speed")
callback()
assert(humanoid.WalkSpeed == 65, "The speed cap must not decay every frame")
areaId = "Snow"
callback()
assert(humanoid.WalkSpeed == 100, "Normal areas must restore full speed")
areaId = "Cosmic"
humanoid.WalkSpeed = 250
callback()
assert(humanoid.WalkSpeed == 250, "Players who can outrun the boss must keep full speed")
humanoid.WalkSpeed = 100
ping = 80
callback()
assert(humanoid.WalkSpeed == 100, "Low-ping servers must not apply High Ping Mode")
ping = 200
callback()
assert(humanoid.WalkSpeed == 65, "High ping plus a faster boss must apply the safety cap")
movement:setPingThreshold(300)
callback()
assert(humanoid.WalkSpeed == 100, "The configured ping limit must control automatic activation")
movement:stop()
print("lag-safe-movement-ok")
