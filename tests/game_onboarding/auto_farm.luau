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
}
local byUid = { secret = records[1], eternal = records[2], limited = records[3] }
local queued
local walks = {}
local hops = 0
local now = 0
local resetSeconds = 2
local failWalk = false
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
        if #walks == 3 then
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
assert(walks[1] == Vector3.new(0, 0, 100), "Auto Farm must use the treadmill while idle")
assert(walks[2] == Vector3.new(40, 0, 0), "Auto Farm must prefer Eternal over Secret")
assert(walks[3] == Vector3.new(0, 0, 100), "Auto Farm must walk back to the base")
assert(hops == 0, "Auto Farm must rescan before leaving a server with more targets")
assert(type(queued) == "function", "A secured egg must queue another scan of the current server")
assert(secured == 1, "Secured eggs must be recorded exactly once")
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
farm:setServerHopping(false)
queued = nil
farm:_hop(farm.token)
assert(hops == 0, "Auto Farm must stay in the current server when Server Hopping is off")
assert(queued == nil, "Disabled server hopping must not poll on a timer")
eggUpdated:Fire(records[1])
assert(type(queued) == "function", "Egg updates must wake the event-driven farm")
farm:stop()
print("auto-farm-ok")
