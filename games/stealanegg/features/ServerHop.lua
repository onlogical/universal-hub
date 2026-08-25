local ServerHop = {}
ServerHop.__index = ServerHop

function ServerHop.new(options)
    assert(options and options.httpGet and options.decode and options.teleportService)
    assert(options.localPlayer and options.placeId and options.jobId)
    local visitedServerIds = options.visitedServerIds or {}
    visitedServerIds[options.jobId] = true
    if options.persistVisited then
        options.persistVisited()
    end
    local self = setmetatable({
        decode = options.decode,
        httpGet = options.httpGet,
        jobId = options.jobId,
        localPlayer = options.localPlayer,
        logger = options.logger,
        placeId = options.placeId,
        persistVisited = options.persistVisited,
        spawn = options.spawn or task.spawn,
        teleportService = options.teleportService,
        visitedServerIds = visitedServerIds,
        requestSerial = 0,
        running = false,
        stopped = false,
    }, ServerHop)
    local failedSignal = options.teleportService.TeleportInitFailed
    if failedSignal and type(failedSignal.Connect) == "function" then
        self.teleportFailedConnection = failedSignal:Connect(function(player, result, message)
            if player ~= self.localPlayer or not self.pendingTeleport then
                return
            end
            local pending = self.pendingTeleport
            self.pendingTeleport = nil
            self:_log("warn", "destination rejected; trying another", {
                error = message,
                result = tostring(result),
                serverId = pending.serverId,
            })
            if pending.completed then
                pending.completed(false, message or tostring(result))
            end
        end)
    end
    return self
end

function ServerHop:_log(level, message, fields)
    local write = self.logger and self.logger[level]
    if type(write) == "function" then
        write(self.logger, "stealanegg.serverHop", message, fields)
    end
end

function ServerHop:run(maxPing, completed, isActive, targetPopulation)
    if self.running or self.stopped then
        if completed then
            completed(false, self.stopped and "stopped" or "busy")
        end
        return
    end
    self.running = true
    self.spawn(function()
        local ok, result = pcall(function()
            self.requestSerial += 1
            targetPopulation = math.max(1, tonumber(targetPopulation) or 6)
            local desiredPlaying = math.max(0, targetPopulation - 1)
            local sortOrder = desiredPlaying >= 4 and "Desc" or "Asc"
            local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%s&limit=100&excludeFullGames=true&_=%s-%d"):format(
                self.placeId,
                sortOrder,
                self.jobId,
                self.requestSerial
            )
            local response = self.decode(self.httpGet(url))
            local best
            for _, server in ipairs(response.data or {}) do
                if
                    server.id ~= self.jobId
                    and self.visitedServerIds[server.id] ~= true
                    and server.playing < server.maxPlayers
                    and type(server.ping) == "number"
                    and server.ping <= maxPing
                    and (
                        not best
                        or math.abs(server.playing - desiredPlaying) < math.abs(
                            best.playing - desiredPlaying
                        )
                        or (
                            math.abs(server.playing - desiredPlaying)
                                == math.abs(best.playing - desiredPlaying)
                            and server.ping < best.ping
                        )
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
            assert(not self.stopped and (not isActive or isActive()), "Server hop cancelled")
            self.pendingTeleport = {
                completed = completed,
                serverId = best.id,
            }
            self.teleportService:TeleportToPlaceInstance(self.placeId, best.id, self.localPlayer)
            self.visitedServerIds[best.id] = true
            if self.persistVisited then
                self.persistVisited()
            end
        end)
        self.running = false
        if not ok then
            self.pendingTeleport = nil
            self:_log("error", "failed", { error = result })
        end
        if completed then
            completed(ok, result)
        end
    end)
end

function ServerHop:stop()
    self.stopped = true
    self.pendingTeleport = nil
    if self.teleportFailedConnection then
        pcall(self.teleportFailedConnection.Disconnect, self.teleportFailedConnection)
        self.teleportFailedConnection = nil
    end
end

return ServerHop
