local roblox = require("@lune/roblox")
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
print("walk-navigator-ok")
