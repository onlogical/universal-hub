local fs = require("@lune/fs")
local source = fs.readFile("loader.lua")

local environment = {}
local queuedSource
local requests = {}
local httpGetCount = 0

function getgenv()
    return environment
end

environment.queue_on_teleport = function(value)
    queuedSource = value
end
environment.request = function(options)
    assert(options.Method == "GET")
    assert(options.Headers["Cache-Control"] == "no-cache")
    assert(options.Headers.Pragma == "no-cache")
    assert(options.Url:find("cacheBust=guid%-", 1) ~= nil)
    table.insert(requests, options.Url)

    if options.Url:find("/dist/runtime.lua", 1, true) then
        return {
            Body = [[
return {
    gameIds = { ["1"] = "rivals" },
    placeIds = {},
    run = function(bundle)
        assert(bundle.id == "rivals")
        assert(type(bundle.sources["ui/dist/Menu.lua"]) == "string")
        return "request-hub-ok"
    end,
}
]],
            StatusCode = 200,
            Success = true,
        }
    end
    if options.Url:find("/dist/games/rivals.lua", 1, true) then
        return {
            Body = [[return { id = "rivals", sources = {} }]],
            StatusCode = 200,
            Success = true,
        }
    end
    if options.Url:find("/ui/dist/Menu.lua", 1, true) then
        return {
            Body = [[return {}]],
            StatusCode = 200,
            Success = true,
        }
    end
    if options.Url:find("/loader.lua", 1, true) then
        return {
            Body = [[return "queued-request-ok"]],
            StatusCode = 200,
            Success = true,
        }
    end
    error("Unexpected request URL: " .. options.Url)
end

game = {
    GameId = 1,
    PlaceId = 2,
    JobId = "request-transport-job",
}
function game:GetService(name)
    assert(name == "HttpService")
    return {
        GenerateGUID = function()
            return "guid-123"
        end,
    }
end
function game:IsLoaded()
    return true
end
function game:HttpGet()
    httpGetCount += 1
    error("request transport must take precedence over HttpGet")
end

local chunk, compileError = loadstring(source, "loader.lua")
assert(assert(chunk, compileError)() == "request-hub-ok")
assert(httpGetCount == 0, "Remote loader must prefer request over HttpGet")
assert(#requests == 3)
assert(requests[1]:find("/dist/runtime.lua", 1, true))
assert(requests[2]:find("/dist/games/rivals.lua", 1, true))
assert(requests[3]:find("/ui/dist/Menu.lua", 1, true))
assert(type(queuedSource) == "string", "Teleport bootstrap must be queued")

environment.UniversalHubLoaderFlight = nil
environment.UniversalHubConfig = nil
local queuedChunk, queuedCompileError = loadstring(queuedSource, "queued-loader.lua")
assert(assert(queuedChunk, queuedCompileError)() == "queued-request-ok")
assert(httpGetCount == 0, "Queued bootstrap must use request instead of HttpGet")
assert(#requests == 4 and requests[4]:find("/loader.lua", 1, true))

environment.UniversalHubLoaderFlight = nil
environment.UniversalHubConfig = {
    SourceBaseUrl = "https://raw.githubusercontent.com/3xjn/universal-hub/refs/heads/main/",
}
game.JobId = "stale-branch-config-job"
local staleChunk, staleCompileError = loadstring(source, "stale-loader.lua")
assert(assert(staleChunk, staleCompileError)() == "request-hub-ok")
assert(
    requests[5]:find("/refs/heads/beta/dist/runtime.lua", 1, true),
    "Beta loader must not reuse a stale canonical branch from an earlier session"
)

print("request-transport-contracts-ok")
