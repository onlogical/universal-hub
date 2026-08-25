local ServerHop = require("../../games/stealanegg/features/ServerHop")

local function signal()
    local callback
    return {
        Connect = function(_, nextCallback)
            callback = nextCallback
            return { Disconnect = function() end }
        end,
        Fire = function(_, ...)
            if callback then
                callback(...)
            end
        end,
    }
end

local teleportFailed = signal()
local teleported
local requestedUrls = {}
local logs = {}
local logger = {}
function logger:info(scope, message, fields)
    table.insert(logs, { scope = scope, message = message, fields = fields })
end
function logger:error(scope, message, fields)
    table.insert(logs, { scope = scope, message = message, fields = fields })
end

local hop = ServerHop.new({
    decode = function()
        return {
            data = {
                { id = "current", playing = 1, maxPlayers = 10, ping = 30 },
                { id = "full", playing = 2, maxPlayers = 2, ping = 20 },
                { id = "too-slow", playing = 1, maxPlayers = 10, ping = 180 },
                { id = "seen", playing = 0, maxPlayers = 10, ping = 25 },
                { id = "busier", playing = 5, maxPlayers = 10, ping = 50 },
                { id = "seven", playing = 7, maxPlayers = 8, ping = 60 },
                { id = "lowest", playing = 2, maxPlayers = 10, ping = 70 },
            },
        }
    end,
    httpGet = function(url)
        assert(url:find("/123/servers/Public", 1, true))
        table.insert(requestedUrls, url)
        return "response"
    end,
    jobId = "current",
    localPlayer = "player",
    logger = logger,
    maxPlayers = 8,
    placeId = 123,
    spawn = function(callback)
        callback()
    end,
    visitedServerIds = { seen = true },
    teleportService = {
        TeleportInitFailed = teleportFailed,
        TeleportToPlaceInstance = function(_, placeId, serverId, player)
            teleported = { placeId = placeId, player = player, serverId = serverId }
        end,
    },
})

local completed
hop:run(120, function(succeeded)
    completed = succeeded
end, nil, 4)
assert(completed == true, "Server Hop must report successful requests to Auto Farm")
assert(
    teleported.placeId == 123 and teleported.serverId == "busier" and teleported.player == "player",
    "Server Hop must prefer the best reported connection"
)
assert(logs[1].scope == "stealanegg.serverHop" and logs[1].fields.players == 5)
assert(
    requestedUrls[1]:find("sortOrder=Desc", 1, true),
    "A four-player target must search populated servers instead of the empty-server page"
)
teleportFailed:Fire("player", "Failure", "Error 279")
assert(completed == false, "Teleport-init failures must be reported so Auto Farm can retry")
hop:run(120, nil, nil, 6)
assert(
    requestedUrls[2]:find("sortOrder=Desc", 1, true),
    "A higher target population must request the busy end"
)
assert(
    teleported.serverId == "seven",
    "Visited best connections must fall through to the next lowest ping"
)
hop:run(120, nil, nil, 99)
assert(
    teleported.serverId == "lowest",
    "Target population must clamp without overriding connection priority"
)

local zeroTeleported
local zeroUrl
local zeroHop = ServerHop.new({
    decode = function()
        return {
            data = {
                { id = "one-player", playing = 1, maxPlayers = 8, ping = 40 },
                { id = "empty", playing = 0, maxPlayers = 8, ping = 40 },
            },
        }
    end,
    httpGet = function(url)
        zeroUrl = url
        return "response"
    end,
    jobId = "zero-current",
    localPlayer = "player",
    maxPlayers = 8,
    placeId = 123,
    spawn = function(callback)
        callback()
    end,
    teleportService = {
        TeleportToPlaceInstance = function(_, _, serverId)
            zeroTeleported = serverId
        end,
    },
})
zeroHop:run(120, nil, nil, 0)
assert(zeroTeleported == "empty", "A zero-population preference must favor empty servers")
assert(zeroUrl:find("sortOrder=Asc", 1, true), "Zero population must search the empty end")
print("server-hop-ok")
