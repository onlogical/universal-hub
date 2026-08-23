local ServerHop = {}
ServerHop.__index = ServerHop

function ServerHop.new(options)
    assert(options and options.httpGet and options.decode and options.teleportService)
    assert(options.localPlayer and options.placeId and options.jobId)
    return setmetatable({
        decode = options.decode,
        httpGet = options.httpGet,
        jobId = options.jobId,
        localPlayer = options.localPlayer,
        logger = options.logger,
        placeId = options.placeId,
        spawn = options.spawn or task.spawn,
        teleportService = options.teleportService,
        running = false,
        stopped = false,
    }, ServerHop)
end

function ServerHop:_log(level, message, fields)
    local write = self.logger and self.logger[level]
    if type(write) == "function" then
        write(self.logger, "stealanegg.serverHop", message, fields)
    end
end

function ServerHop:run(maxPing)
    if self.running or self.stopped then
        return
    end
    self.running = true
    self.spawn(function()
        local ok, result = pcall(function()
            local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(
                self.placeId
            )
            local response = self.decode(self.httpGet(url))
            local best
            for _, server in ipairs(response.data or {}) do
                if
                    server.id ~= self.jobId
                    and server.playing < server.maxPlayers
                    and type(server.ping) == "number"
                    and server.ping <= maxPing
                    and (
                        not best
                        or server.playing < best.playing
                        or (server.playing == best.playing and server.ping < best.ping)
                    )
                then
                    best = server
                end
            end
            assert(best, ("No available server found below %d ms"):format(maxPing))
            self:_log("info", "teleporting", {
                ping = best.ping,
                players = best.playing,
                serverId = best.id,
            })
            if not self.stopped then
                self.teleportService:TeleportToPlaceInstance(
                    self.placeId,
                    best.id,
                    self.localPlayer
                )
            end
        end)
        self.running = false
        if not ok then
            self:_log("error", "failed", { error = result })
        end
    end)
end

function ServerHop:stop()
    self.stopped = true
end

return ServerHop
