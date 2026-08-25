local fs = require("@lune/fs")
local source = fs.readFile("loader.lua")
local queuedTeleportSource
local queueCount = 0
local environment = {
    queue_on_teleport = function(source)
        queueCount += 1
        queuedTeleportSource = source
    end,
}
local requestedUrl
local requestedUrls = {}
local loaded = false
local waitedForLoad = false
local pendingBootstrap
local spawnCount = 0

local function remoteBody(url)
    requestedUrl = url
    table.insert(requestedUrls, url)
    if url:find("/dist/runtime.lua", 1, true) then
        return [[
return {
    gameIds = { ["1"] = "rivals" },
    placeIds = {},
    run = function(bundle)
        assert(bundle.id == "rivals")
        assert(type(bundle.sources["ui/dist/Menu.lua"]) == "string")
        return "remote-loader-ok"
    end,
}
]]
    end
    if url:find("/dist/games/rivals.lua", 1, true) then
        return [[return { id = "rivals", sources = {} }]]
    end
    if url:find("/ui/dist/Menu.lua", 1, true) then
        return [[return {}]]
    end
    error("Unexpected remote bundle URL: " .. url)
end

function getgenv()
    return environment
end

task = {
    spawn = function(callback)
        spawnCount += 1
        pendingBootstrap = callback
    end,
}
game = {
    GameId = 1,
    PlaceId = 2,
    JobId = "remote-early-job",
    Loaded = {
        Wait = function()
            waitedForLoad = true
            loaded = true
        end,
    },
}
function game:IsLoaded()
    return loaded
end
function game:HttpGet(url, noCache)
    assert(noCache == true, "Remote loader must bypass the executor HTTP cache")
    assert(loaded, "Remote loader must not start network bootstrap before Roblox finishes loading")
    return remoteBody(url)
end

local chunk, compileError = loadstring(source, "loader.lua")
local result = assert(chunk, compileError)()
assert(result == nil, "Early autoexec must return immediately instead of blocking game startup")
assert(requestedUrl == nil, "Early autoexec must not bootstrap before Roblox finishes loading")
assert(type(pendingBootstrap) == "function", "Early autoexec must schedule a deferred bootstrap")
local duplicateEarlyChunk, duplicateEarlyCompileError = loadstring(source, "loader.lua")
local duplicateEarlyResult = assert(duplicateEarlyChunk, duplicateEarlyCompileError)()
assert(
    duplicateEarlyResult == nil,
    "A duplicate early remote bootstrap in the same job must coalesce"
)
assert(
    spawnCount == 1,
    "A duplicate early remote bootstrap must not schedule a second deferred task"
)
assert(queueCount == 1, "The remote loader must automatically persist across teleports")
assert(
    queuedTeleportSource
        and queuedTeleportSource:find("UniversalHubConfig.SourceBaseUrl", 1, true)
        and queuedTeleportSource:find("/loader.lua", 1, true),
    "The queued remote bootstrap must retain the matching loader source"
)
local deferredResult = pendingBootstrap()
assert(deferredResult == "remote-loader-ok")
assert(waitedForLoad, "Remote loader must yield to Roblox startup when launched from autoexec")
assert(
    requestedUrls[1]
        == "https://raw.githubusercontent.com/3xjn/universal-hub/refs/heads/beta/dist/runtime.lua"
)
assert(
    requestedUrls[2]
        == "https://raw.githubusercontent.com/3xjn/universal-hub/refs/heads/beta/dist/games/rivals.lua"
)
assert(
    requestedUrls[3]
        == "https://raw.githubusercontent.com/3xjn/universal-hub/refs/heads/beta/ui/dist/Menu.lua"
)

waitedForLoad = false
pendingBootstrap = nil
game.Loaded.Wait = function()
    error("Remote loader must not wait again after Roblox is already loaded")
end
task.spawn = function()
    error("Remote loader must not defer after Roblox is already loaded")
end
local immediateChunk, immediateCompileError = loadstring(source, "loader.lua")
local immediateResult = assert(immediateChunk, immediateCompileError)()
assert(immediateResult == "remote-loader-ok")
assert(not waitedForLoad, "Manual execution in a loaded game must start immediately")

local duplicateLoadedResult
local attemptedLoadedDuplicate = false
game.JobId = "remote-loaded-job"
function game:HttpGet(url, noCache)
    assert(noCache == true, "Remote loader must bypass the executor HTTP cache")
    assert(loaded, "Remote loader must not start network bootstrap before Roblox finishes loading")
    if not attemptedLoadedDuplicate then
        attemptedLoadedDuplicate = true
        local duplicateLoadedChunk, duplicateLoadedCompileError = loadstring(source, "loader.lua")
        duplicateLoadedResult = assert(duplicateLoadedChunk, duplicateLoadedCompileError)()
    end
    return remoteBody(url)
end
local overlapChunk, overlapCompileError = loadstring(source, "loader.lua")
local overlapResult = assert(overlapChunk, overlapCompileError)()
assert(overlapResult == "remote-loader-ok")
assert(
    duplicateLoadedResult == nil,
    "A duplicate loaded remote bootstrap must coalesce through hub initialization"
)

environment.UniversalHubConfig = {
    LocalRoot = "universal-hub/local",
}
requestedUrl = nil
queuedTeleportSource = nil
function readfile(path)
    assert(path == "universal-hub/local/local.lua")
    return [[
local environment = getgenv()
environment.LocalLoaderDelegated = true
environment.queue_on_teleport("local-loader-queue")
return "local-loader-from-remote-entry-ok"
]]
end
local localChunk, localCompileError = loadstring(source, "loader.lua")
local localResult = assert(localChunk, localCompileError)()
assert(localResult == "local-loader-from-remote-entry-ok")
assert(requestedUrl == nil, "An explicitly configured local version must not fall back to GitHub")
assert(
    queuedTeleportSource == "local-loader-queue",
    "A local version entered through loader.lua must own its queued follow-up bootstrap"
)
assert(
    environment.LocalLoaderDelegated == true,
    "loader.lua must delegate directly to a configured local loader"
)

environment.UniversalHubConfig = {
    SourceBaseUrl = "https://example.invalid/custom/",
}
readfile = nil
requestedUrl = nil
queuedTeleportSource = nil
local customChunk, customCompileError = loadstring(source, "loader.lua")
local customResult = assert(customChunk, customCompileError)()
assert(customResult == "remote-loader-ok")
assert(
    requestedUrl == "https://example.invalid/custom/ui/dist/Menu.lua",
    "An explicit custom source may be used for the current bundled session"
)
assert(
    queuedTeleportSource == nil,
    "A custom remote source must not become persistent cross-teleport code execution"
)

loaded = false
pendingBootstrap = nil
spawnCount = 0
local pendingBootstraps = {}
game.JobId = "remote-stale-job"
task.spawn = function(callback)
    spawnCount += 1
    pendingBootstrap = callback
    table.insert(pendingBootstraps, callback)
end
game.Loaded.Wait = function()
    loaded = true
end
local staleJobChunk, staleJobCompileError = loadstring(source, "loader.lua")
assert(assert(staleJobChunk, staleJobCompileError)() == nil)
game.JobId = "remote-next-job"
local nextJobChunk, nextJobCompileError = loadstring(source, "loader.lua")
assert(assert(nextJobChunk, nextJobCompileError)() == nil)
assert(
    spawnCount == 2,
    "A new teleport job must replace a stale remote flight instead of being suppressed"
)
requestedUrl = nil
assert(pendingBootstraps[1]() == nil)
assert(requestedUrl == nil, "A stale job's deferred loader must not publish after ownership moves")
loaded = false
assert(pendingBootstraps[2]() == "remote-loader-ok")

print("remote-loader-contracts-ok")
