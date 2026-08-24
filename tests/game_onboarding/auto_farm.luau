local roblox = require("@lune/roblox")
CFrame = roblox.CFrame
Vector3 = roblox.Vector3

local AutoFarm = require("../../games/stealanegg/features/AutoFarm")

local function signal()
    local callback
    return {
        Connect = function(_, nextCallback)
            callback = nextCallback
            return { Disconnect = function() end }
        end,
        Fire = function(_, value)
            if callback then
                callback(value)
            end
        end,
    }
end

local records = {
    {
        AreaId = "Cosmic",
        AssetCategory = "Secret Egg",
        BottomCFrame = CFrame.new(20, 0, 0),
        NestId = "A",
        State = "Slot",
        Uid = "secret",
    },
    {
        AreaId = "Cherry Blossom",
        AssetCategory = "Eternal Egg",
        BottomCFrame = CFrame.new(40, 0, 0),
        NestId = "B",
        State = "Slot",
        Uid = "eternal",
    },
    {
        AreaId = "Event",
        AssetCategory = "Limited Egg",
        BottomCFrame = CFrame.new(5, 0, 0),
        NestId = "C",
        State = "Slot",
        Uid = "limited",
    },
}
local byUid = { secret = records[1], eternal = records[2], limited = records[3] }
local queued
local walks = {}
local hops = 0
local now = 0
local resetSeconds = 2
local farm
local root = {
    IsA = function(_, className)
        return className == "BasePart"
    end,
    Position = Vector3.new(0, 0, 0),
}
local eggCmds = {
    AreaEggClaimed = signal(),
    GetAreaEggSnapshot = function()
        return { Records = records }
    end,
    GetAreaEggRecord = function(uid)
        return byUid[uid]
    end,
    RequestAreaEggSnapshot = function()
        return { Records = records }
    end,
    RequestCarryAreaEgg = function(uid)
        byUid[uid].State = "Carried"
        byUid[uid].CarrierUserId = 42
        return true
    end,
}
local navigator = {
    walkTo = function(_, position)
        assert(resetSeconds <= 0, "Auto Farm must wait for the reset phase to finish")
        root.Position = position
        table.insert(walks, position)
        if #walks == 2 then
            byUid.eternal = nil
            farm.claimed = true
        end
        return true
    end,
}
farm = AutoFarm.new({
    assets = {
        Directory = {
            ["Secret Egg"] = { Rarity = { DisplayName = "Secret", RarityNumber = 8 } },
            ["Eternal Egg"] = { Rarity = { DisplayName = "Eternal", RarityNumber = 9 } },
            ["Limited Egg"] = { Rarity = { DisplayName = "Limited", RarityNumber = 10 } },
        },
    },
    eggCmds = eggCmds,
    getResetSeconds = function()
        return resetSeconds
    end,
    localPlayer = {
        UserId = 42,
        Character = {
            FindFirstChild = function(_, name)
                if name == "HumanoidRootPart" then
                    return root
                end
            end,
        },
    },
    navigator = navigator,
    plotCmds = {
        GetRespawnPointCFrame = function()
            return CFrame.new(0, 0, 100)
        end,
    },
    serverHop = {
        run = function(_, maxPing)
            assert(maxPing == 90)
            hops += 1
        end,
    },
    slotIdentity = {
        IsFirstAreaUid = function()
            return false
        end,
    },
    spawn = function(callback)
        queued = callback
    end,
    wait = function(seconds)
        resetSeconds = math.max(0, resetSeconds - (seconds or 0))
    end,
    workspace = {
        GetServerTimeNow = function()
            now += 0.1
            return now
        end,
    },
})

farm:setTargetRarities(true, true)
farm:setMaxPing(90)
farm:setEnabled(true)
queued()
assert(walks[1] == Vector3.new(40, 0, 0), "Auto Farm must prefer Eternal over Secret")
assert(walks[2] == Vector3.new(0, 0, 100), "Auto Farm must walk back to the base")
assert(hops == 1, "Auto Farm must hop only after the egg is secured")
farm:stop()
print("auto-farm-ok")
