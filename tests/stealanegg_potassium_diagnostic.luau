local fs = require("@lune/fs")

local function signal()
    local callbacks = {}
    return {
        Connect = function(_self, callback)
            callbacks[callback] = true
            return {
                Disconnect = function()
                    callbacks[callback] = nil
                end,
            }
        end,
        Fire = function(_self, ...)
            for callback in pairs(callbacks) do
                callback(...)
            end
        end,
    }
end

local carryChanged = signal()
local eggUpdated = signal()
local ragdollChanged = signal()
local record = {
    AreaId = "Forest",
    CarrierUserId = 42,
    NestId = "Nest1",
    State = "Carried",
    Uid = "egg-42",
}
local originalCarry = function(uid, slotKey)
    assert(uid == record.Uid and slotKey == "Forest:Nest1")
    return true, "accepted"
end
local eggCmds = {
    AreaEggCarryStateChanged = carryChanged,
    AreaEggUpdated = eggUpdated,
    GetAreaEggSnapshot = function()
        return { Records = { record } }
    end,
    RequestCarryAreaEgg = originalCarry,
}
local player = {
    UserId = 42,
    GetAttribute = function()
        return 0
    end,
    GetAttributeChangedSignal = function()
        return ragdollChanged
    end,
}
local eggModule = {}
local replicatedStorage = {
    Library = {
        Client = {
            EggCmds = eggModule,
        },
    },
}
local workspace = {
    GetServerTimeNow = function()
        return 100
    end,
}
local gameMock = { JobId = "job-1" }
function gameMock:GetService(name)
    if name == "Players" then
        return { LocalPlayer = player }
    elseif name == "ReplicatedStorage" then
        return replicatedStorage
    elseif name == "Workspace" then
        return workspace
    end
    error("Unexpected service " .. name)
end

local environment = {
    UniversalHubSession = {
        store = {
            Get = function()
                return { settings = { antiHit = true, instantPrompts = false } }
            end,
        },
    },
}
local written = ""
local delayed
local source = fs.readFile("diagnostics/stealanegg-potassium.lua")
local chunk, compileError = loadstring(source, "stealanegg-potassium.lua")
assert(chunk, compileError)
setfenv(
    chunk,
    setmetatable({
        game = gameMock,
        getgenv = function()
            return environment
        end,
        identifyexecutor = function()
            return "Potassium", "test"
        end,
        makefolder = function() end,
        require = function(module)
            assert(module == eggModule)
            return eggCmds
        end,
        task = {
            delay = function(_seconds, callback)
                delayed = callback
            end,
        },
        warn = function() end,
        writefile = function(path, content)
            assert(path == "universal-hub/stealanegg-potassium.log")
            written = content
        end,
    }, { __index = getfenv() })
)

local diagnostic = chunk()
assert(eggCmds.RequestCarryAreaEgg ~= originalCarry)
assert(eggCmds.RequestCarryAreaEgg(record.Uid, "Forest:Nest1") == true)
record.State = "Dropped"
record.CarrierUserId = nil
eggUpdated:Fire(record)
carryChanged:Fire({ IsCarrying = false, Uid = record.Uid })
delayed()
assert(eggCmds.RequestCarryAreaEgg == originalCarry)
assert(environment.UniversalHubEggDiagnostic == nil)
assert(written:find("executor=Potassium", 1, true))
assert(written:find("RequestCarry END", 1, true))
assert(written:find("state=Dropped", 1, true))
assert(written:find("STOP", 1, true))

diagnostic.stop()
print("stealanegg-potassium-diagnostic-ok")
