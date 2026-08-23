local environment = assert(getgenv, "<UH> ~ Your executor is not supported")()
local configuration = environment.UniversalHubConfig or {}
local officialSourceRoot = "https://raw.githubusercontent.com/3xjn/universal-hub/refs/heads/beta/"
local sourceRoot = configuration.SourceBaseUrl or officialSourceRoot
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
        return response.Body
    end
    return httpGame:HttpGet(url, true)
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
    configuration.Fetch = fetchSource
    environment.UniversalHubConfig = configuration

    local source = fetchSource(sourceRoot .. "hub.lua")
    if not ownsFlight() then
        return
    end
    local chunk, compileError = loadstring(source, "universal-hub/hub.lua")
    return assert(chunk, compileError)()
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
