local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local Sampler = importDependency(
    "games/duelinggrounds/recording/Sampler",
    "./Sampler"
)
local Replay = importDependency(
    "games/duelinggrounds/recording/Replay",
    "./Replay"
)

local Runtime = {}
Runtime.__index = Runtime

local MAX_GLOBAL_EVENTS = 4000
local MAX_MATCH_EVENTS = 5000
local MAX_SAMPLES = 8000
local MAX_MATCHES = 25
local SAMPLE_INTERVAL = 0.05

local function trim(list, limit)
    while #list > limit do
        table.remove(list, 1)
    end
end

local function copyInto(destination, source)
    for key, value in pairs(source or {}) do
        destination[key] = value
    end
end

local function isDead(model)
    return model
        and type(model.GetAttribute) == "function"
        and model:GetAttribute("IsDead") == true
end

function Runtime.new(dependencies)
    dependencies = dependencies or {}
    local environment = dependencies.environment or _G
    local telemetry = environment.__DuelingGroundsCombatTelemetry
    if type(telemetry) ~= "table" or telemetry.version ~= 1 then
        telemetry = { version = 1, events = {} }
        environment.__DuelingGroundsCombatTelemetry = telemetry
    end
    telemetry.events = telemetry.events or {}
    telemetry.matches = telemetry.matches or {}
    telemetry.nextMatchId = telemetry.nextMatchId or 0
    telemetry.current = nil

    return setmetatable({
        clock = dependencies.clock or os.clock,
        wallClock = dependencies.wallClock or os.time,
        persistence = dependencies.persistence,
        sample = dependencies.sample or Sampler.sample,
        replay = dependencies.replay or Replay,
        telemetry = telemetry,
        lastStyle = nil,
        stopped = false,
    }, Runtime)
end

function Runtime:_append(kind, data)
    local match = self.telemetry.current
    if not match then
        return
    end
    local event = { kind = kind, t = self.clock() - match.startedClock }
    copyInto(event, data)
    event.kind = kind
    event.t = self.clock() - match.startedClock
    table.insert(match.events, event)
    trim(match.events, MAX_MATCH_EVENTS)
end

function Runtime:recordEvent(kind, data, global)
    if self.stopped then
        return
    end
    if global == true then
        local event = { kind = kind, t = self.clock() }
        copyInto(event, data)
        event.kind = kind
        event.t = self.clock()
        table.insert(self.telemetry.events, event)
        trim(self.telemetry.events, MAX_GLOBAL_EVENTS)
        local matchEvent = {}
        copyInto(matchEvent, event)
        matchEvent.decisionKind = kind
        self:_append("decision", matchEvent)
        return
    end
    self:_append(kind, data)
end

function Runtime:recordDecision(kind, data)
    self:recordEvent(kind, data, true)
end

function Runtime:_start(frame, settings)
    local telemetry = self.telemetry
    telemetry.nextMatchId += 1
    local metadata = {
        id = telemetry.nextMatchId,
        startedAt = self.wallClock(),
        style = settings.combatStyle,
        autoMovement = settings.autoMovement == true,
    }
    copyInto(metadata, frame.metadata)
    local now = self.clock()
    telemetry.current = {
        startedClock = now,
        targetModelRef = frame.targetModel,
        metadata = metadata,
        events = {},
        samples = {},
        lastSampleAt = -math.huge,
    }
    self.lastStyle = settings.combatStyle
    self:_append("matchStarted", {
        autoMovement = settings.autoMovement == true,
        style = settings.combatStyle,
    })
end

function Runtime:_finish(reason)
    local match = self.telemetry.current
    if not match then
        return
    end
    match.metadata.duration = self.clock() - match.startedClock
    match.metadata.endedAt = self.wallClock()
    match.metadata.endReason = reason
    match.metadata.eventCount = #match.events
    match.metadata.sampleCount = #match.samples
    match.startedClock = nil
    match.targetModelRef = nil
    match.lastSampleAt = nil
    local replaySucceeded, timeline = pcall(self.replay.build, match)
    match.timeline = replaySucceeded and timeline or {
        id = match.metadata.id,
        target = match.metadata.target,
        duration = match.metadata.duration,
        entries = {},
        counts = {},
        error = tostring(timeline),
    }
    table.insert(self.telemetry.matches, match)
    trim(self.telemetry.matches, MAX_MATCHES)
    self.telemetry.current = nil
    self.lastStyle = nil
    if self.persistence then
        self.persistence:save(self.telemetry.version, match)
    end
end

function Runtime:getCurrentMatch()
    return self.telemetry.current
end

function Runtime:getLatestMatch()
    return self.telemetry.matches[#self.telemetry.matches]
end

function Runtime:update(frame, settings)
    if self.stopped then
        return
    end
    frame = frame or {}
    settings = settings or {}
    local targetModel = frame.targetModel
    local match = self.telemetry.current

    if settings.autoFight ~= true or not targetModel then
        self:_finish(settings.autoFight == true and "targetLost" or "autoFightOff")
        return
    end
    if frame.targetDead == true or isDead(targetModel) then
        self:_finish("targetDead")
        return
    end

    local localHandler = frame.localHandler
    local localAction = localHandler
        and localHandler.ActionManager
        and localHandler.ActionManager.CurrentAction
    if frame.selfDead == true
        or (localHandler
            and (isDead(localHandler.Model)
                or (localAction and localAction.ActionType == "Death")))
    then
        self:_finish("selfDead")
        return
    end
    if match and match.targetModelRef ~= targetModel then
        self:_finish("targetChanged")
        match = nil
    end
    if not match then
        self:_start(frame, settings)
        match = self.telemetry.current
    end
    if self.lastStyle ~= settings.combatStyle then
        self:_append("styleChanged", {
            from = self.lastStyle,
            to = settings.combatStyle,
        })
        self.lastStyle = settings.combatStyle
    end

    local now = self.clock()
    if now - match.lastSampleAt < SAMPLE_INTERVAL then
        return
    end
    match.lastSampleAt = now
    table.insert(match.samples, self.sample(frame, settings, now - match.startedClock))
    trim(match.samples, MAX_SAMPLES)
end

function Runtime:stop(reason)
    if self.stopped then
        return
    end
    self.stopped = true
    self:_finish(reason or "sessionStopped")
end

return Runtime
