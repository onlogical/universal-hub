local environment = assert(getgenv, "<UH> ~ Your executor is not supported")()
local configuration = environment.UniversalHubConfig or {}
local bootTiming = {
    fetchCount = 0,
    fetchSeconds = 0,
    mode = "remote",
    startedAt = os.clock(),
}
configuration.BootTiming = bootTiming
local officialSourceRoot = "https://raw.githubusercontent.com/3xjn/universal-hub/refs/heads/beta/"
local repositoryBranchRoot = "https://raw.githubusercontent.com/3xjn/universal-hub/refs/heads/"
local sourceRoot = configuration.SourceBaseUrl
if
    type(sourceRoot) == "string"
    and sourceRoot:sub(1, #repositoryBranchRoot) == repositoryBranchRoot
then
    sourceRoot = officialSourceRoot
end
sourceRoot = sourceRoot or officialSourceRoot
local localRoot = configuration.LocalRoot
local localLoaderPath = type(localRoot) == "string" and localRoot .. "/local.lua" or nil
local localLoaderSource
if localLoaderPath and type(readfile) == "function" then
    local succeeded, source = pcall(readfile, localLoaderPath)
    if succeeded then
        localLoaderSource = source
    end
end
type HttpGame = typeof(game) & {
    HttpGet: (self: typeof(game), url: string, noCache: boolean?) -> string,
}
local httpGame = game :: HttpGame

if localLoaderSource then
    local chunk, compileError = loadstring(localLoaderSource, "universal-hub/local.lua")
    return assert(chunk, compileError)()
end

local synapse = environment.syn
local requestFunction = type(environment.request) == "function" and environment.request
    or type(environment.http_request) == "function" and environment.http_request
    or type(synapse) == "table" and type(synapse.request) == "function" and synapse.request
local HttpService = requestFunction and game:GetService("HttpService")

local function fetchSource(url)
    local startedAt = os.clock()
    local body
    if requestFunction then
        local separator = url:find("?", 1, true) and "&" or "?"
        local response = requestFunction({
            Url = url .. separator .. "cacheBust=" .. HttpService:GenerateGUID(false),
            Method = "GET",
            Headers = {
                ["Cache-Control"] = "no-cache",
                Pragma = "no-cache",
            },
        })
        local status = response and (response.StatusCode or response.Status)
        assert(
            type(response) == "table"
                and type(response.Body) == "string"
                and response.Success ~= false
                and (status == nil or (status >= 200 and status < 300)),
            ("Universal Hub source request failed (%s)"):format(tostring(status or "unknown"))
        )
        body = response.Body
    else
        body = httpGame:HttpGet(url, true)
    end
    local elapsed = os.clock() - startedAt
    bootTiming.fetchCount += 1
    bootTiming.fetchSeconds += elapsed
    if not bootTiming.slowestFetchSeconds or elapsed > bootTiming.slowestFetchSeconds then
        bootTiming.slowestFetch = url
        bootTiming.slowestFetchSeconds = elapsed
    end
    return body
end

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

local function queueNextPlace()
    local synapse = environment.syn
    local queue = type(environment.queue_on_teleport) == "function"
            and environment.queue_on_teleport
        or type(environment.queueonteleport) == "function" and environment.queueonteleport
        or type(synapse) == "table"
            and type(synapse.queue_on_teleport) == "function"
            and synapse.queue_on_teleport
    if not queue then
        return
    end

    if sourceRoot ~= officialSourceRoot then
        return
    end

    pcall(
        queue,
        ([[
local environment = getgenv()
local HttpService = game:GetService("HttpService")
local synapse = environment.syn
local requestFunction = type(environment.request) == "function" and environment.request
    or type(environment.http_request) == "function" and environment.http_request
    or type(synapse) == "table" and type(synapse.request) == "function" and synapse.request
assert(requestFunction, "Universal Hub requires request")
environment.UniversalHubConfig = environment.UniversalHubConfig or {}
environment.UniversalHubConfig.SourceBaseUrl = %q
local response = requestFunction({
    Url = %q .. "?cacheBust=" .. HttpService:GenerateGUID(false),
    Method = "GET",
    Headers = { ["Cache-Control"] = "no-cache", Pragma = "no-cache" },
})
local status = response and (response.StatusCode or response.Status)
assert(
    type(response) == "table"
        and type(response.Body) == "string"
        and response.Success ~= false
        and (status == nil or (status >= 200 and status < 300)),
    ("Universal Hub loader request failed (%%s)"):format(tostring(status or "unknown"))
)
local chunk, compileError = loadstring(response.Body, "universal-hub/loader.lua")
return assert(chunk, compileError)()
]]):format(sourceRoot, sourceRoot .. "loader.lua")
    )
end

local function loadHub()
    configuration.SourceBaseUrl = sourceRoot
    environment.UniversalHubConfig = configuration

    local runtimeSource = fetchSource(sourceRoot .. "dist/runtime.lua")
    if not ownsFlight() then
        return
    end
    local runtimeChunk, runtimeError = loadstring(runtimeSource, "universal-hub/dist/runtime.lua")
    local runtime = assert(runtimeChunk, runtimeError)()
    local bundleId = runtime.placeIds[tostring(game.PlaceId)]
        or runtime.gameIds[tostring(game.GameId)]
    assert(bundleId, "Universal Hub does not support this game")

    local gamePath = "dist/games/" .. bundleId .. ".lua"
    local gameSource = fetchSource(sourceRoot .. gamePath)
    local gameChunk, gameError = loadstring(gameSource, "universal-hub/" .. gamePath)
    local bundle = assert(gameChunk, gameError)()
    bundle.sources["ui/dist/Menu.lua"] = fetchSource(sourceRoot .. "ui/dist/Menu.lua")
    if not ownsFlight() then
        return
    end
    return runtime.run(bundle)
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
    queueNextPlace()
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
