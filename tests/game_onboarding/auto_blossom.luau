local roblox = require("@lune/roblox")
CFrame = roblox.CFrame
Vector3 = roblox.Vector3

local function signal()
    local callback
    return {
        Connect = function(_, nextCallback)
            callback = nextCallback
            return { Disconnect = function() end }
        end,
        Fire = function(_, ...)
            if callback then
                callback(...)
            end
        end,
    }
end

local AutoBlossom = require("../../games/stealanegg/features/AutoBlossom")

local equipped
local bat = {
    GetAttribute = function(_, name)
        return name == "IsBat" and true or nil
    end,
}
local humanoid = {
    EquipTool = function(_, tool)
        equipped = tool
    end,
}
local character = {
    FindFirstChildOfClass = function(_, className)
        if className == "Humanoid" then
            return humanoid
        elseif className == "Tool" then
            return equipped
        end
    end,
    FindFirstChild = function(_, name)
        if name == "HumanoidRootPart" then
            return { Position = Vector3.new(0, 0, 0) }
        end
    end,
}
local tree = {
    Name = "BloomTree",
    Parent = true,
    GetAttribute = function(_, name)
        return name == "Radius" and 4 or nil
    end,
    GetPivot = function()
        return CFrame.new(20, 0, 0)
    end,
    IsA = function(_, className)
        return className == "Model"
    end,
}
local walked
local queued
local workStates = {}
local farm
farm = AutoBlossom.new({
    canFarm = function()
        return true
    end,
    collectionService = {
        GetTagged = function(_, tag)
            assert(tag == "SakuraBloomTree")
            return { tree }
        end,
    },
    hitCooldown = 0.6,
    hitRange = 10,
    localPlayer = {
        Character = character,
        FindFirstChildOfClass = function(_, className)
            assert(className == "Backpack")
            return {
                GetChildren = function()
                    return { bat }
                end,
            }
        end,
    },
    navigator = {
        walkTo = function(_, position, isActive, tolerance)
            assert(isActive())
            walked = { position = position, tolerance = tolerance }
            tree.Parent = nil
            return true
        end,
    },
    onWorkChanged = function(working)
        table.insert(workStates, working)
    end,
    spawn = function(callback)
        queued = callback
    end,
    treeTag = "SakuraBloomTree",
    wait = function(seconds)
        assert(seconds == 0.6)
        farm:setEnabled(false)
    end,
})
farm:setEnabled(true)
assert(type(queued) == "function")
queued()
assert(equipped == bat, "Auto Blossom must equip a native bat")
assert(
    walked.position == Vector3.new(20, 0, 0) and walked.tolerance == 13,
    "Auto Blossom must walk within native tree Radius + HitRange"
)
assert(
    workStates[1] == true and workStates[2] == false,
    "Auto Blossom must report when it takes and releases farm priority"
)

local lockedWalks = 0
local locked = AutoBlossom.new({
    canFarm = function()
        return false
    end,
    collectionService = {
        GetTagged = function()
            return { tree }
        end,
    },
    localPlayer = { Character = character },
    navigator = {
        walkTo = function()
            lockedWalks += 1
        end,
    },
    spawn = function(callback)
        queued = callback
    end,
    wait = function()
        error("Locked Auto Blossom must not poll")
    end,
})
locked:setEnabled(true)
queued()
assert(lockedWalks == 0, "Locked Sakura events must not start movement or treadmill work")
locked:stop()

local treeAdded = signal()
local eventTrees = {}
local eventWalks = 0
local eventFarm
eventFarm = AutoBlossom.new({
    collectionService = {
        GetInstanceAddedSignal = function(_, tag)
            assert(tag == "SakuraBloomTree")
            return treeAdded
        end,
        GetTagged = function()
            return eventTrees
        end,
    },
    localPlayer = { Character = character },
    navigator = {
        walkTo = function()
            eventWalks += 1
            tree.Parent = nil
            return true
        end,
    },
    spawn = function(callback)
        queued = callback
    end,
    wait = function()
        eventFarm:setEnabled(false)
    end,
})
eventFarm:setEnabled(true)
queued()
assert(eventWalks == 0, "Auto Blossom must not poll while no tagged tree exists")
tree.Parent = true
eventTrees = { tree }
treeAdded:Fire(tree)
queued()
assert(eventWalks == 1, "A native tree-added event must wake Auto Blossom immediately")
eventFarm:stop()
print("auto-blossom-ok")
