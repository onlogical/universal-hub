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
movement:stop()
print("lag-safe-movement-ok")
