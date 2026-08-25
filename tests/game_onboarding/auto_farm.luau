local roblox = require("@lune/roblox")
CFrame = roblox.CFrame
Color3 = roblox.Color3
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

local eggUpdated = signal()
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
    {
        AreaId = "Cosmic",
        AssetCategory = "Secret Egg",
        CarrierUserId = 123,
        State = "Claimed",
        Uid = "unstreamed-carrier",
    },
}
local byUid = {
    secret = records[1],
    eternal = records[2],
    limited = records[3],
    ["unstreamed-carrier"] = records[4],
}
local queued
local walks = {}
local directMoves = 0
local jumps = 0
local hops = 0
local now = 0
local resetSeconds = 2
local failWalk = false
local blossomWork = false
local blossomStarts = 0
local globalSpawns = {}
local indexed = { ["Eternal Egg"] = true, ["Secret Egg"] = true }
local pendingIndex = {}
local published = 0
local lastPublished
local secured = 0
local farm
local carrierRoot = {
    IsA = function(_, className)
        return className == "BasePart"
    end,
    Position = Vector3.new(60, 0, 0),
}
local root = {
    IsA = function(_, className)
        return className == "BasePart"
    end,
    Position = Vector3.new(0, 0, 0),
}
local eggCmds = {
    AreaEggClaimed = signal(),
    AreaEggUpdated = eggUpdated,
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
    jump = function()
        jumps += 1
        return true
    end,
    moveToDirect = function(_, position)
        directMoves += 1
        root.Position = position
        table.insert(walks, position)
        return true
    end,
    walkTo = function(_, position)
        if failWalk then
            return false, "blocked"
        end
        if position ~= Vector3.new(0, 0, 100) then
            assert(resetSeconds <= 0, "Auto Farm must wait for the reset phase to finish")
        end
        root.Position = position
        table.insert(walks, position)
        if byUid.contested and position == carrierRoot.Position then
            byUid.contested.State = "Dropped"
            byUid.contested.BottomCFrame = CFrame.new(position)
        end
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
            ["Divine Egg"] = { Rarity = { DisplayName = "Divine", RarityNumber = 11 } },
            ["Common Egg"] = { Rarity = { DisplayName = "Common", RarityNumber = 1 } },
        },
    },
    eggCmds = eggCmds,
    getIdlePosition = function()
        return Vector3.new(0, 0, 100)
    end,
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
    hasMissingIndex = function()
        return true
    end,
    isGlobalSpawnKnown = function(rarity)
        return globalSpawns[rarity] == true
    end,
    isIndexed = function(category)
        return indexed[category] == true
    end,
    isIndexPending = function(category)
        return pendingIndex[category] == true
    end,
    markGlobalSpawn = function(rarity)
        globalSpawns[rarity] = true
    end,
    navigator = navigator,
    onSecured = function(record)
        assert(record.Uid == "eternal")
        secured += 1
    end,
    players = {
        GetPlayerByUserId = function(_, userId)
            if userId == 99 then
                return {
                    Character = {
                        FindFirstChild = function(_, name)
                            return name == "HumanoidRootPart" and carrierRoot or nil
                        end,
                    },
                }
            end
        end,
    },
    publishStatus = function(model)
        published += 1
        lastPublished = model
    end,
    plotCmds = {
        GetRespawnPointCFrame = function()
            return CFrame.new(0, 0, 100)
        end,
    },
    serverHop = {
        run = function(_, maxPing, _completed, _active, targetPopulation)
            assert(maxPing == 90 and targetPopulation == 6)
            hops += 1
        end,
    },
    shouldRunBlossom = function()
        if blossomWork then
            blossomStarts += 1
        end
        return blossomWork
    end,
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

local originalRecords = records
local divineEgg = {
    AreaId = "Cherry Blossom",
    AssetCategory = "Divine Egg",
    BottomCFrame = CFrame.new(10, 0, 0),
    NestId = "Divine",
    State = "Slot",
    Uid = "divine",
}
records = { divineEgg }
farm:setTargetRarities(true, false)
assert(
    farm:_selectTarget().record == divineEgg,
    "Eternal farming must implicitly target Divine eggs"
)
farm:setTargetRarities(false, true)
assert(
    farm:_selectTarget().record == divineEgg,
    "Secret farming must implicitly target Divine eggs"
)
farm:setTargetRarities(false, false)
assert(farm:_selectTarget() == nil, "Divine eggs must remain opt-in through a rare target mode")
records = originalRecords
farm:setTargetRarities(true, true)
farm:setMaxPing(90)
farm:setEnabled(true)
queued()
assert(walks[1] == Vector3.new(40, 0, 0), "Auto Farm must skip the treadmill when a target exists")
assert(globalSpawns.Eternal == true, "Seeing a target must remember its global spawn")
assert(walks[2] == Vector3.new(0, 0, 100), "Auto Farm must walk back to the base")
assert(hops == 0, "Auto Farm must rescan before leaving a server with more targets")
assert(type(queued) == "function", "A secured egg must queue another scan of the current server")
assert(secured == 1, "Secured eggs must be recorded exactly once")
local missingIndexEgg = {
    AreaId = "Forest",
    AssetCategory = "Common Egg",
    BottomCFrame = CFrame.new(70, 0, 0),
    NestId = "Index",
    State = "Slot",
    Uid = "missing-index",
}
records = { records[1], missingIndexEgg }
byUid[missingIndexEgg.Uid] = missingIndexEgg
farm:setCompleteIndex(true)
assert(
    farm:_selectTarget().record == records[1],
    "Global Secret targets must take priority over missing Index eggs"
)
farm:setTargetRarities(false, false)
records = { missingIndexEgg }
pendingIndex[missingIndexEgg.AssetCategory] = true
assert(
    farm:_selectTarget() == nil,
    "Complete Index must skip categories already owned or placed while they await hatching"
)
pendingIndex[missingIndexEgg.AssetCategory] = nil
blossomWork = true
local walksBeforeBlossom = #walks
farm:_run(farm.token)
assert(
    blossomStarts == 1 and #walks == walksBeforeBlossom,
    "Auto Blossom must run after rare eggs but before Complete Index"
)
blossomWork = false
queued = nil
failWalk = true
farm:_run(farm.token)
assert(
    type(queued) == "function" and hops == 0,
    "Complete Index must pursue missing eggs without Secret or Eternal filters"
)
failWalk = false
records = {}
assert(
    farm.setIndexServerHopping == nil,
    "Index Server Hopping must not remain a configurable mode"
)
farm:setIdleTreadmill(false)
local walksBeforeIdle = #walks
queued = nil
farm:_hop(farm.token)
assert(hops == 0, "Complete Index must stay in the server because index drops are global")
assert(#walks == walksBeforeIdle, "Idle Treadmill off must leave the player in place")
farm:setIdleTreadmill(true)
farm:_hop(farm.token)
assert(
    walks[#walks] == Vector3.new(0, 0, 100) and directMoves > 0,
    "Idle Treadmill must use direct movement only while no target exists"
)
assert(farm.onTreadmill == true, "Auto Farm must remember that it entered the treadmill")
farm:_leaveTreadmill()
assert(jumps == 1 and farm.onTreadmill == false, "Auto Farm must jump before leaving the treadmill")
farm:setTargetRarities(true, true)
records = { byUid.secret }
queued = nil
farm:_hop(farm.token)
assert(
    hops == 0 and type(queued) == "function",
    "Auto Farm must rescan instead of hopping while a selected lobby egg exists"
)
local blocked = {
    AreaId = "Cosmic",
    AssetCategory = "Eternal Egg",
    BottomCFrame = CFrame.new(80, 0, 0),
    NestId = "Blocked",
    State = "Slot",
    Uid = "blocked",
}
records = { blocked }
byUid.blocked = blocked
failWalk = true
queued = nil
farm:_run(farm.token)
assert(hops == 0, "A blocked path must not force a server hop")
assert(type(queued) == "function", "A blocked path must rebuild its route in the same server")
failWalk = false
local contested = {
    AreaId = "Volcano",
    AssetCategory = "Secret Egg",
    BottomCFrame = CFrame.new(55, 0, 0),
    CarrierUserId = 99,
    State = "Claimed",
    Uid = "contested",
}
byUid.contested = contested
local dropped = farm:_pursueCarrier(contested, farm.token)
assert(
    dropped == contested and contested.State == "Dropped",
    "Claimed eggs must be pursued until dropped"
)
farm:setCompleteIndex(false)
table.clear(globalSpawns)
records = {}
queued = nil
farm:_hop(farm.token)
assert(hops == 0, "Auto Farm must not hop before a selected global rarity has spawned")
assert(queued == nil, "Waiting for a global spawn must be event-driven")
eggUpdated:Fire(byUid.secret)
assert(type(queued) == "function", "Egg updates must wake global-spawn detection")
globalSpawns.Secret = true
farm:setServerHopping(false)
queued = nil
farm:_hop(farm.token)
assert(hops == 0, "Auto Farm must stay in the current server when Server Hopping is off")
assert(queued == nil, "Disabled server hopping must not poll on a timer")
eggUpdated:Fire(byUid.secret)
assert(type(queued) == "function", "Egg updates must wake the event-driven farm")
farm:setPaused(true)
assert(
    type(lastPublished) == "table" and lastPublished.visible == true,
    "Auto Blossom priority must keep the Auto Farm monitor visible"
)
farm:setPaused(false)
local beforeDisable = published
farm:setEnabled(false)
assert(published == beforeDisable + 1, "Disabling Auto Farm must publish one hidden monitor state")
local afterDisable = published
farm:setEnabled(false)
assert(published == afterDisable, "Repeated disabled state must not publish recursively")
farm:stop()
print("auto-farm-ok")
