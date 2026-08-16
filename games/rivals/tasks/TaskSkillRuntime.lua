local TaskSkillRuntime = {}
TaskSkillRuntime.__index = TaskSkillRuntime

local function healthOf(subject)
    if not subject then return nil, nil end
    local humanoid = subject
    if typeof(subject) == "Instance" then
        if not subject:IsA("Humanoid") then
            humanoid = subject:FindFirstChildOfClass("Humanoid")
        end
    elseif type(subject) == "table" then
        humanoid = subject.Humanoid or subject
    end
    local health = humanoid and humanoid.Health
    local maximum = humanoid and humanoid.MaxHealth
    if type(health) ~= "number" then return nil, nil end
    if type(maximum) ~= "number" or maximum <= 0 then
        return health, nil
    end
    return health, maximum
end

local function attribute(player, name)
    if not player or type(player.GetAttribute) ~= "function" then return nil end
    local succeeded, value = pcall(player.GetAttribute, player, name)
    return succeeded and value or nil
end

local function playerStatThreat(localPlayer, opponent)
    local player = opponent and opponent.player
    if not player then return nil, nil end
    local elo = attribute(player, "DisplayELO")
    local level = attribute(player, "Level")
    local streak = attribute(player, "StatisticDuelsWinStreak")
    local localElo = attribute(localPlayer, "DisplayELO")
    local localLevel = attribute(localPlayer, "Level")
    local localStreak = attribute(localPlayer, "StatisticDuelsWinStreak")
    if type(elo) ~= "number" and type(level) ~= "number" and type(streak) ~= "number" then
        return nil, nil
    end
    local values = {}
    if type(elo) == "number" then
        values[#values + 1] = type(localElo) == "number"
            and math.clamp(0.5 + (elo - localElo) / 1600, 0, 1)
            or math.clamp((elo - 600) / 2000, 0, 1)
    end
    if type(level) == "number" then
        values[#values + 1] = type(localLevel) == "number"
            and math.clamp(0.5 + (level - localLevel) / 300, 0, 1)
            or math.clamp(level / 250, 0, 1)
    end
    if type(streak) == "number" then
        values[#values + 1] = type(localStreak) == "number"
            and math.clamp(0.5 + (streak - localStreak) / 20, 0, 1)
            or math.clamp(streak / 12, 0, 1)
    end
    local total = 0
    for _, value in ipairs(values) do total += value end
    return total / #values, { elo = elo, level = level, streak = streak }
end

function TaskSkillRuntime.new(options)
    options = options or {}
    return setmetatable({
        localPlayer = options.localPlayer,
        threat = 0.5,
        statsReady = false,
        opponentStats = nil,
        lastLocalHealth = nil,
        lastOpponentHealth = nil,
        lastOpponent = nil,
        samples = 0,
    }, TaskSkillRuntime)
end

function TaskSkillRuntime:reset()
    self.threat = 0.5
    self.statsReady = false
    self.opponentStats = nil
    self.lastLocalHealth = nil
    self.lastOpponentHealth = nil
    self.lastOpponent = nil
    self.samples = 0
end

function TaskSkillRuntime:update(localHumanoid, opponent, deltaTime)
    local localHealth, localMaximum = healthOf(localHumanoid)
    local opponentHumanoid = opponent and opponent.character
        and opponent.character.FindFirstChildOfClass
        and opponent.character:FindFirstChildOfClass("Humanoid")
    local opponentHealth, opponentMaximum = healthOf(opponentHumanoid)
    if type(opponent and opponent.health) == "number" then opponentHealth = opponent.health end
    if type(opponent and opponent.maxHealth) == "number" then opponentMaximum = opponent.maxHealth end
    if type(opponentHealth) == "number"
        and (type(opponentMaximum) ~= "number" or opponentMaximum <= 0)
    then
        opponentMaximum = nil
    end
    local opponentKey = opponent and (opponent.character or opponent.player or opponent.part)
    local statThreat, opponentStats = playerStatThreat(self.localPlayer, opponent)
    if opponentKey ~= self.lastOpponent then
        self.lastOpponent = opponentKey
        self.lastOpponentHealth = opponentHealth
        self.samples = 0
        if type(statThreat) == "number" then self.threat = statThreat end
    end
    self.statsReady = type(statThreat) == "number"
    self.opponentStats = opponentStats
    if not localHealth or not opponentHealth or not localMaximum or not opponentMaximum then
        self.lastLocalHealth = localHealth
        self.lastOpponentHealth = opponentHealth
        return self:rates()
    end
    local dt = math.max(type(deltaTime) == "number" and deltaTime or 1 / 60, 1 / 120)
    local incoming = math.max(0, (self.lastLocalHealth or localHealth) - localHealth) / dt
    local outgoing = math.max(0, (self.lastOpponentHealth or opponentHealth) - opponentHealth) / dt
    if incoming > 0 or outgoing > 0 then self.samples += 1 end
    local healthPressure = math.clamp((opponentHealth / opponentMaximum - localHealth / localMaximum + 1) * 0.5, 0, 1)
    local exchangePressure = (incoming + outgoing) > 0
        and incoming / (incoming + outgoing)
        or self.threat
    local observed = self.statsReady
        and statThreat * 0.5 + healthPressure * 0.35 + exchangePressure * 0.15
        or healthPressure * 0.65 + exchangePressure * 0.35
    self.threat += (observed - self.threat) * math.min(1, dt * 2.5)
    self.lastLocalHealth = localHealth
    self.lastOpponentHealth = opponentHealth
    return self:rates()
end

function TaskSkillRuntime:rates()
    return {
        headshotRate = math.floor(28 + self.threat * 22 + 0.5),
        missRate = math.floor(32 - self.threat * 12 + 0.5),
        ready = self.statsReady or self.samples >= 3,
        samples = self.samples,
        stats = self.opponentStats,
        statsReady = self.statsReady,
        threat = self.threat,
    }
end

return TaskSkillRuntime
