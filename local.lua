local environment = assert(getgenv, "<UH> ~ Your executor is not supported")()
local jobId = game.JobId
local activeFlight = environment.UniversalHubLoaderFlight
if type(activeFlight) == "table" and activeFlight.jobId == jobId then
    return
end

local owner = {}
environment.UniversalHubLoaderFlight = {
    jobId = jobId,
    owner = owner,
}

local function ownsFlight()
    local current = environment.UniversalHubLoaderFlight
    return type(current) == "table" and current.owner == owner
end

local function releaseFlight()
    if ownsFlight() then
        environment.UniversalHubLoaderFlight = nil
    end
end

local configuration

local function loadHub()
    local limnSource = readfile(configuration.LimnPath)
    local limnChunk, limnError = loadstring(limnSource, "vendor/Limn.lua")
    local Limn = assert(limnChunk, limnError)()
    assert(type(Limn) == "table" and type(Limn.new) == "function", "Universal Hub requires Limn")

    local helpersPath = configuration.HydroxideRoot .. "/modules/Helpers.lua"
    local helpersChunk, helpersError = loadstring(readfile(helpersPath), "hydroxide/modules/Helpers.lua")
    local Helpers = assert(helpersChunk, helpersError)()
    assert(
        type(Helpers) == "table" and type(Helpers.load) == "function",
        "Universal Hub requires Hydroxide Helpers.load"
    )

    configuration.Limn = Limn
    configuration.HydroxideHelpers = Helpers
    if not ownsFlight() then
        return
    end

    local hubChunk, hubError = loadstring(readfile(configuration.LocalRoot .. "/init.lua"), "universal-hub/init.lua")
    return assert(hubChunk, hubError)()
end

local function completeBootstrap()
    if not ownsFlight() then
        return
    end

    local succeeded, result = pcall(loadHub)
    releaseFlight()
    if not succeeded then
        error(result, 0)
    end
    return result
end

local function startBootstrap()
    configuration = environment.UniversalHubConfig or {}
    configuration.LocalRoot = configuration.LocalRoot or "universal-hub/local"
    configuration.HydroxideRoot = configuration.HydroxideRoot or "hydroxide/local"
    configuration.LimnPath = configuration.LimnPath or "limn/dist/Limn.lua"
    local importCache = {}
    configuration.Import = function(path)
        assert(
            type(path) == "string"
                and path:match("^[%w_/%-]+$") ~= nil
                and not path:find("//", 1, true),
            "Invalid local hub module path"
        )
        if importCache[path] ~= nil then
            return importCache[path]
        end
        local file = path .. ".lua"
        local source = readfile(configuration.LocalRoot .. "/" .. file)
        local chunk, compileError = loadstring(source, file)
        local result = assert(chunk, compileError)()
        importCache[path] = result
        return result
    end
    local hydroxideModules = {
        ["modules/Closure"] = true,
        ["modules/Lifecycle"] = true,
        ["modules/Targeting"] = true,
    }
    local hydroxideCache = {}
    configuration.HydroxideImport = function(path)
        assert(hydroxideModules[path] == true, "Unknown Hydroxide helper module: " .. tostring(path))
        if hydroxideCache[path] ~= nil then
            return hydroxideCache[path]
        end
        local file = path .. ".lua"
        local source = readfile(configuration.HydroxideRoot .. "/" .. file)
        local chunk, compileError = loadstring(source, "hydroxide/" .. file)
        local result = assert(chunk, compileError)()
        hydroxideCache[path] = assert(result, "Hydroxide helper module returned nil: " .. path)
        return hydroxideCache[path]
    end
    environment.UniversalHubConfig = configuration

    local synapse = environment.syn
    local queue = type(environment.queue_on_teleport) == "function"
            and environment.queue_on_teleport
        or type(environment.queueonteleport) == "function" and environment.queueonteleport
        or type(synapse) == "table" and type(synapse.queue_on_teleport) == "function"
            and synapse.queue_on_teleport
    if queue then
        queue(([[
loadstring(readfile(%q), "universal-hub/local.lua")()
]]):format(configuration.LocalRoot .. "/local.lua"))
    end

    if not game:IsLoaded() then
        task.spawn(function()
            local succeeded, result = pcall(function()
                game.Loaded:Wait()
                return completeBootstrap()
            end)
            if not succeeded then
                releaseFlight()
                error(result, 0)
            end
            return result
        end)
        return
    end

    return completeBootstrap()
end

local succeeded, result = pcall(startBootstrap)
if not succeeded then
    releaseFlight()
    error(result, 0)
end
return result
