local environment = assert(getgenv, "Diagnostic requires getgenv")()
local previous = environment.UniversalHubEggDiagnostic
if type(previous) == "table" and type(previous.stop) == "function" then
    pcall(previous.stop)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
local EggCmds = require(ReplicatedStorage.Library.Client.EggCmds)
local logPath = "universal-hub/stealanegg-potassium.log"
local startedAt = os.clock()
local lines = {}
local connections = {}
local stopped = false

if type(makefolder) == "function" then
    pcall(makefolder, "universal-hub")
end

local function writeLog()
    if type(writefile) == "function" then
        pcall(writefile, logPath, table.concat(lines, "\n") .. "\n")
    end
end

local function log(message)
    local line = ("[%07.3f] %s"):format(os.clock() - startedAt, tostring(message))
    table.insert(lines, line)
    writeLog()
    warn("[UH Egg Diagnostic] " .. line)
end

local function describeRecord(record)
    if type(record) ~= "table" then
        return tostring(record)
    end
    return ("uid=%s state=%s carrier=%s area=%s nest=%s"):format(
        tostring(record.Uid),
        tostring(record.State),
        tostring(record.CarrierUserId),
        tostring(record.AreaId),
        tostring(record.NestId)
    )
end

local function snapshot(reason)
    local succeeded, value = pcall(EggCmds.GetAreaEggSnapshot)
    if not succeeded then
        log(("snapshot %s ERROR %s"):format(reason, value))
        return
    end
    local relevant = {}
    for _, record in ipairs(value and value.Records or {}) do
        if record.CarrierUserId == player.UserId or record.State == "Dropped" then
            table.insert(relevant, describeRecord(record))
        end
    end
    log(("snapshot %s relevant=%d %s"):format(reason, #relevant, table.concat(relevant, " | ")))
end

local function connect(signal, callback, name)
    local succeeded, connection = pcall(function()
        return signal:Connect(callback)
    end)
    if succeeded then
        table.insert(connections, connection)
    else
        log(("connect %s ERROR %s"):format(name, connection))
    end
end

local originalCarry = EggCmds.RequestCarryAreaEgg
local wrappedCarry
if type(originalCarry) == "function" then
    wrappedCarry = function(uid, slotKey)
        log(("RequestCarry BEGIN uid=%s slot=%s"):format(tostring(uid), tostring(slotKey)))
        local results = table.pack(pcall(originalCarry, uid, slotKey))
        if not results[1] then
            log(("RequestCarry ERROR uid=%s %s"):format(tostring(uid), tostring(results[2])))
            error(results[2], 0)
        end
        local values = {}
        for index = 2, results.n do
            table.insert(values, tostring(results[index]))
        end
        log(("RequestCarry END uid=%s results=%s"):format(tostring(uid), table.concat(values, ",")))
        return table.unpack(results, 2, results.n)
    end
    EggCmds.RequestCarryAreaEgg = wrappedCarry
else
    log("RequestCarryAreaEgg is unavailable")
end

local diagnostic = {}
function diagnostic.stop()
    if stopped then
        return
    end
    stopped = true
    if EggCmds.RequestCarryAreaEgg == wrappedCarry then
        EggCmds.RequestCarryAreaEgg = originalCarry
    end
    for _, connection in ipairs(connections) do
        pcall(connection.Disconnect, connection)
    end
    table.clear(connections)
    log("STOP")
    if environment.UniversalHubEggDiagnostic == diagnostic then
        environment.UniversalHubEggDiagnostic = nil
    end
end

environment.UniversalHubEggDiagnostic = diagnostic

local executorName, executorVersion = "unknown", "unknown"
if type(identifyexecutor) == "function" then
    local succeeded, name, version = pcall(identifyexecutor)
    if succeeded then
        executorName, executorVersion = tostring(name), tostring(version)
    end
end
local session = environment.UniversalHubSession
local settings = type(session) == "table" and session.store and session.store:Get().settings or {}
log(
    ("START executor=%s version=%s job=%s user=%s"):format(
        executorName,
        executorVersion,
        tostring(game.JobId),
        tostring(player.UserId)
    )
)
log(
    ("settings antiHit=%s instantPrompts=%s"):format(
        tostring(settings.antiHit),
        tostring(settings.instantPrompts)
    )
)
log(
    ("ragdollEnd=%s serverNow=%s"):format(
        tostring(player:GetAttribute("RagdollEndTime")),
        tostring(Workspace:GetServerTimeNow())
    )
)
snapshot("start")

connect(EggCmds.AreaEggCarryStateChanged, function(state)
    log(("CarryState carrying=%s uid=%s"):format(tostring(state.IsCarrying), tostring(state.Uid)))
    snapshot("carry-state")
end, "AreaEggCarryStateChanged")
connect(EggCmds.AreaEggUpdated, function(record)
    if record.CarrierUserId == player.UserId or record.State == "Dropped" then
        log("AreaEggUpdated " .. describeRecord(record))
    end
end, "AreaEggUpdated")
connect(player:GetAttributeChangedSignal("RagdollEndTime"), function()
    log(
        ("RagdollEndTime value=%s serverNow=%s"):format(
            tostring(player:GetAttribute("RagdollEndTime")),
            tostring(Workspace:GetServerTimeNow())
        )
    )
end, "RagdollEndTime")

if task and type(task.delay) == "function" then
    task.delay(90, diagnostic.stop)
end

log("Reproduce the failed pickup now; logging stops automatically after 90 seconds")
return diagnostic
