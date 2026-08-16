local fs = require("@lune/fs")
local source = fs.readFile("local.lua")
assert(
    source:find('configuration.LimnPath', 1, true)
        and source:find('modules/Helpers.lua', 1, true),
    "Local bootstrap must stage Limn and Hydroxide Helpers before init"
)
assert(
    source:find("configuration.RivalsAutoCounterTest = {", 1, true)
        and source:find("enabled = false", 1, true)
        and source:find("verticalOffset = 1000", 1, true)
        and not source:find("UniversalHubCounterCandidate", 1, true),
    "Local bootstrap must keep the Auto Counter hop off unless explicitly enabled"
)
assert(
    not source:find('HydroxideRoot .. "/init.lua"', 1, true)
        and not source:find("environment.HydroxideConfig", 1, true),
    "Local bootstrap must not execute or configure the Hydroxide application"
)
local hydroxideAllowlist = assert(source:match("local hydroxideModules = {(.-)}"))
for _, path in ipairs({
    "modules/Closure",
    "modules/Lifecycle",
    "modules/Targeting",
}) do
    assert(hydroxideAllowlist:find(path, 1, true), "Local bootstrap must retain stable helper " .. path)
end
assert(
    not hydroxideAllowlist:find("Drawing", 1, true)
        and not hydroxideAllowlist:find("Remote", 1, true)
        and not source:find("raw.githubusercontent.com/3xjn/hydroxide", 1, true),
    "Local bootstrap must use only its configured Hydroxide root and stable helper allowlist"
)
local exited = false
local loaded = {}
local queuedTeleportSource
local queueCount = 0
local pendingBootstrap
local spawnCount = 0
local waitedForLoad = false
local gameLoaded = false
local duplicateDuringLoadResult
local attemptedDuplicateDuringLoad = false
local failHelpers = false
local environment = {
    queue_on_teleport = function(source)
        queueCount += 1
        queuedTeleportSource = source
    end,
    UniversalHubConfig = {
        Import = function()
            error("stale remote import must not run")
        end,
    },
    oh = {
        drawing = {},
        targeting = {
            stale = true,
        },
        Exit = function()
            exited = true
        end,
    },
}
environment.OriginalOh = environment.oh

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
    JobId = "local-job",
    Loaded = {
        Wait = function()
            waitedForLoad = true
            gameLoaded = true
        end,
    },
}
function game:IsLoaded()
    return gameLoaded
end

function loadfile(path)
    local source = readfile(path)
    local chunk, compileError = loadstring(source, path)
    return chunk, compileError
end

function readfile(path)
    table.insert(loaded, path)
    if path == "universal-hub/local/ui/dist/Menu.lua" then
        return [[
return {
    mountUniversalHubMenu = function() end,
}
]]
    end
    if path == "limn/dist/Limn.lua" then
        return [[return { new = function() end }]]
    end
    if path == "hydroxide/local/modules/Helpers.lua" then
        if failHelpers then
            error("intentional helpers failure")
        end
        if not attemptedDuplicateDuringLoad then
            attemptedDuplicateDuringLoad = true
            local duplicateChunk, duplicateCompileError = loadstring(source, "local.lua")
            duplicateDuringLoadResult = assert(duplicateChunk, duplicateCompileError)()
        end
        return [[
return {
    load = function(options)
        local files = {
            closure = "modules/Closure",
            lifecycle = "modules/Lifecycle",
            targeting = "modules/Targeting",
        }
        local namespace = {}
        for _, name in ipairs(options.modules or {}) do
            namespace[name] = options.import(files[name])
        end
        return namespace
    end,
}
]]
    end
    if path == "hydroxide/local/modules/Targeting.lua" then
        return [[return { nearestPlayer = function() end }]]
    end
    if path == "hydroxide/local/modules/Closure.lua"
        or path == "hydroxide/local/modules/Lifecycle.lua"
    then
        return [[return {}]]
    end
    assert(path ~= "hydroxide/local/init.lua", "Local loader must never execute hydroxide/init.lua")
    if path:sub(1, #"universal-hub/local/") == "universal-hub/local/"
        and path ~= "universal-hub/local/init.lua"
    then
        return fs.readFile(path:sub(#"universal-hub/local/" + 1))
    end
    assert(path == "universal-hub/local/init.lua")
    return [[
assert(
    type(getgenv().UniversalHubConfig.Import) == "function",
    "Local loader must install a fresh local Import seam"
)
local executionPlan = assert(getgenv().UniversalHubConfig.Import)(
    "games/town/ExecutionPlan"
)
assert(
    type(executionPlan) == "table" and type(executionPlan.compile) == "function",
    "Local loader must resolve the production Town dependency graph"
)
assert(
    type(getgenv().UniversalHubConfig.Limn.new) == "function",
    "Local loader must stage Limn before loading a game adapter"
)
local helpers = getgenv().UniversalHubConfig.HydroxideHelpers.load({
    import = getgenv().UniversalHubConfig.HydroxideImport,
    modules = { "targeting" },
})
assert(
    type(helpers.targeting.nearestPlayer) == "function",
    "Local loader must load selected stable helpers through Helpers.load"
)
assert(
    not pcall(getgenv().UniversalHubConfig.HydroxideImport, "modules/Store"),
    "Hydroxide imports must not resolve Universal Hub modules"
)
assert(
    getgenv().oh == getgenv().OriginalOh,
    "Local loader must not replace the unrelated Hydroxide namespace"
)
return "local-loader-ok"
]]
end

local chunk, compileError = loadstring(source, "local.lua")
local result = assert(chunk, compileError)()
assert(result == nil, "Early local loader execution must return before Roblox finishes loading")
assert(#loaded == 0, "Early local loader execution must not initialize Hydroxide or the hub")
assert(type(pendingBootstrap) == "function", "Early local loader execution must schedule a deferred bootstrap")
local duplicateEarlyChunk, duplicateEarlyCompileError = loadstring(source, "local.lua")
local duplicateEarlyResult = assert(duplicateEarlyChunk, duplicateEarlyCompileError)()
assert(duplicateEarlyResult == nil, "A duplicate early local bootstrap in the same job must coalesce")
assert(spawnCount == 1, "A duplicate early local bootstrap must not schedule a second deferred task")
assert(queueCount == 1, "A duplicate early local bootstrap must queue teleport code once")
assert(
    type(queuedTeleportSource) == "string"
        and string.find(queuedTeleportSource, "universal%-hub/local/local%.lua") ~= nil
        and string.find(queuedTeleportSource, "loadfile%(") ~= nil
        and not string.find(queuedTeleportSource, "loadstring(readfile", 1, true),
    "Local loader must queue itself so game-to-game teleports refresh the selected adapter"
)
local deferredResult = pendingBootstrap()
assert(deferredResult == "local-loader-ok")
assert(waitedForLoad, "Local loader must yield to Roblox startup when launched from autoexec")
assert(exited == false, "Scoped helper loading must not exit an unrelated Hydroxide session")
assert(
    loaded[1] == "universal-hub/local/ui/dist/Menu.lua"
        and loaded[2] == "limn/dist/Limn.lua"
        and loaded[3] == "hydroxide/local/modules/Helpers.lua"
        and loaded[4] == "universal-hub/local/init.lua",
    "Local bootstrap must stage the native menu, Limn, and Helpers before Universal Hub"
)
local function loadedCount(path)
    local count = 0
    for _, loadedPath in ipairs(loaded) do
        if loadedPath == path then
            count += 1
        end
    end
    return count
end
assert(
    loadedCount("hydroxide/local/init.lua") == 0
        and loadedCount("universal-hub/local/ui/dist/Menu.lua") == 1
        and loadedCount("limn/dist/Limn.lua") == 1
        and loadedCount("hydroxide/local/modules/Helpers.lua") == 1
        and loadedCount("hydroxide/local/modules/Targeting.lua") == 1
        and loadedCount("universal-hub/local/init.lua") == 1,
    "A duplicate local bootstrap must stage each selected dependency and hub exactly once"
)
assert(
    loadedCount("universal-hub/local/games/town/ExecutionPlan.lua") == 1
        and loadedCount("universal-hub/local/games/town/Canonical.lua") == 1,
    "The local loader must read nested Town modules from its selected local root"
)
assert(duplicateDuringLoadResult == nil, "A duplicate local bootstrap during helper staging must coalesce")
assert(type(environment.UniversalHubConfig.ReloadMenu) == "function", "Local loader must expose ReloadMenu")
assert(
    environment.UniversalHubConfig.MenuStampPath == "universal-hub/local/ui/dist/Menu.lua",
    "Without isfile, the compiled menu itself is the hot-reload stamp"
)
local restaged = environment.UniversalHubConfig.ReloadMenu()
assert(type(restaged) == "table" and type(restaged.mountUniversalHubMenu) == "function")
assert(environment.UniversalHubConfig.Menu == restaged)
assert(loadedCount("universal-hub/local/ui/dist/Menu.lua") == 2, "ReloadMenu must loadfile the compiled menu again")

waitedForLoad = false
pendingBootstrap = nil
game.Loaded.Wait = function()
    error("Local loader must not wait again after Roblox is already loaded")
end
task.spawn = function()
    error("Local loader must not defer after Roblox is already loaded")
end
local immediateChunk, immediateCompileError = loadstring(source, "local.lua")
local immediateResult = assert(immediateChunk, immediateCompileError)()
assert(immediateResult == "local-loader-ok")
assert(not waitedForLoad, "Manual execution in a loaded game must start immediately")
assert(queueCount == 2, "Manual reexecution after a completed flight must start a fresh bootstrap")

game.JobId = "local-error-job"
failHelpers = true
local errorChunk, errorCompileError = loadstring(source, "local.lua")
assert(not pcall(assert(errorChunk, errorCompileError)), "A failed local flight must surface its initialization error")
failHelpers = false
local retryChunk, retryCompileError = loadstring(source, "local.lua")
local retryResult = assert(retryChunk, retryCompileError)()
assert(retryResult == "local-loader-ok", "A failed local flight must release ownership for a retry")

print("local-loader-contracts-ok")
