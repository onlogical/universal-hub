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
                { id = "lowest", playing = 2, maxPlayers = 10, ping = 70 },
            },
        }
    end,
    httpGet = function(url)
        assert(url:find("/123/servers/Public", 1, true))
        return "response"
    end,
    jobId = "current",
    localPlayer = "player",
    logger = logger,
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
end)
assert(completed == true, "Server Hop must report successful requests to Auto Farm")
assert(
    teleported.placeId == 123 and teleported.serverId == "lowest" and teleported.player == "player"
)
assert(logs[1].scope == "stealanegg.serverHop" and logs[1].fields.players == 2)
teleportFailed:Fire("player", "Failure", "Error 279")
assert(completed == false, "Teleport-init failures must be reported so Auto Farm can retry")
hop:run(120, nil, nil, "high")
assert(teleported.serverId == "busier", "High-population mode must prefer the busiest server")
print("server-hop-ok")
