local roblox = require("@lune/roblox")
CFrame = roblox.CFrame
Enum = roblox.Enum
Vector3 = roblox.Vector3

local createdModifier
Instance = {
    new = function(className)
        assert(className == "PathfindingModifier")
        createdModifier = {
            Destroy = function(self)
                self.destroyed = true
            end,
        }
        return createdModifier
    end,
}

local WalkNavigator = require("../../games/stealanegg/features/WalkNavigator")

local root = {
    Position = Vector3.zero,
    IsA = function(_, className)
        return className == "BasePart"
    end,
}
local moveCalls = {}
local humanoid = {
    MoveTo = function(_, position)
        table.insert(moveCalls, position)
    end,
}
local character = {
    FindFirstChild = function(_, name)
        return name == "HumanoidRootPart" and root or nil
    end,
    FindFirstChildOfClass = function(_, className)
        return className == "Humanoid" and humanoid or nil
    end,
}
local treadmill = {
    Parent = true,
    IsA = function(_, className)
        return className == "BasePart"
    end,
}
local pathOptions
local path = {
    ComputeAsync = function() end,
    GetWaypoints = function()
        root.Position = Vector3.new(5, 0, 0)
        return {
            { Action = Enum.PathWaypointAction.Walk, Position = Vector3.zero },
            { Action = Enum.PathWaypointAction.Walk, Position = Vector3.new(30, -5, 0) },
        }
    end,
    Status = Enum.PathStatus.Success,
}
local navigator
local waits = 0
navigator = WalkNavigator.new({
    blockedParts = { treadmill },
    localPlayer = { Character = character },
    pathfindingService = {
        CreatePath = function(_, options)
            pathOptions = options
            return path
        end,
    },
    runService = {
        Heartbeat = {
            Wait = function()
                waits += 1
                if waits == 1 then
                    navigator:resume()
                    root.Position = Vector3.new(30, 0, 0)
                end
            end,
        },
    },
    workspace = {
        GetServerTimeNow = function()
            return waits
        end,
    },
})
local reached = navigator:walkTo(Vector3.new(30, -5, 0), function()
    return true
end, 1)
assert(reached == true)
assert(
    pathOptions.Costs.UniversalHubTreadmill >= 1000000,
    "Pathfinding must treat the treadmill as blocked"
)
assert(createdModifier.Parent == treadmill and createdModifier.PassThrough == false)
assert(
    #moveCalls >= 2 and moveCalls[1] == Vector3.new(30, -5, 0),
    "Navigation must skip the stale start waypoint instead of walking backward"
)
assert(
    moveCalls[1] == moveCalls[2],
    "A native hit recovery must immediately resume the active MoveTo destination"
)
local escape = Vector3.new(-20, 0, 0)
assert(navigator:headToward(escape) == true and navigator:resume() == true)
assert(
    moveCalls[#moveCalls - 1] == escape and moveCalls[#moveCalls] == escape,
    "A carry request must preserve forward escape momentum and its recovery destination"
)
navigator:stop()
assert(createdModifier.destroyed == true, "Stopping navigation must remove its treadmill modifier")

local stepPosition = Vector3.zero
local stepRoot = setmetatable({
    AssemblyLinearVelocity = Vector3.new(5, 0, 0),
    IsA = function(_, className)
        return className == "BasePart"
    end,
}, {
    __index = function(_, key)
        if key == "Position" then
            return stepPosition
        end
        if key == "CFrame" then
            return CFrame.new(stepPosition)
        end
    end,
    __newindex = function(self, key, value)
        if key == "CFrame" then
            stepPosition = value.Position
        else
            rawset(self, key, value)
        end
    end,
})
local stepMoves = {}
local stepHumanoid = {
    WalkSpeed = 200,
    MoveTo = function(_, position)
        table.insert(stepMoves, position)
    end,
}
local stepCharacter = {
    FindFirstChild = function(_, name)
        return name == "HumanoidRootPart" and stepRoot or nil
    end,
    FindFirstChildOfClass = function(_, className)
        return className == "Humanoid" and stepHumanoid or nil
    end,
}
local stepWaits = 0
local stepNavigator = WalkNavigator.new({
    localPlayer = { Character = stepCharacter },
    runService = {
        Heartbeat = {
            Wait = function()
                stepWaits += 1
                return 1 / 60
            end,
        },
    },
    workspace = {
        GetServerTimeNow = function()
            return stepWaits / 60
        end,
    },
})
local stepped = stepNavigator:stepTo(Vector3.new(100, 8, 0), function()
    return true
end, 1)
assert(stepped == true and stepPosition == Vector3.new(100, 0, 0))
assert(
    stepRoot.AssemblyLinearVelocity == Vector3.zero and stepMoves[1] == Vector3.new(100, 8, 0),
    "Fast stepping must preserve native movement intent while clearing physical velocity"
)
local activeChecks = 0
local cancelled, cancelReason = stepNavigator:stepTo(Vector3.new(200, 0, 0), function()
    activeChecks += 1
    return activeChecks == 1
end, 1)
assert(cancelled == false and cancelReason == "cancelled")
assert(
    stepMoves[#stepMoves] == stepPosition,
    "Cancelled fast stepping must stop native movement at the current position"
)
stepNavigator:stop()
print("walk-navigator-ok")
