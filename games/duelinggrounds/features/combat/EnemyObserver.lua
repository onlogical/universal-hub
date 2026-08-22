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

local EnemyPolicy =
    importDependency("games/duelinggrounds/features/combat/EnemyPolicy", "./EnemyPolicy")

local EnemyObserver = {}
EnemyObserver.__index = EnemyObserver

local function characterSnapshot(model)
    return model
            and {
                model = model,
                isDead = model:GetAttribute("IsDead") == true,
                teamGroup = model:GetAttribute("TeamGroup"),
            }
        or nil
end

function EnemyObserver.new(context)
    assert(context and context.players and context.localPlayer, "EnemyObserver requires players")
    assert(context.characterController, "EnemyObserver requires CharacterController")
    assert(type(context.observeTrack) == "function", "EnemyObserver requires observeTrack")
    return setmetatable({
        context = context,
        observations = {},
        stopped = false,
    }, EnemyObserver)
end

function EnemyObserver:_disconnect(model)
    local observation = self.observations[model]
    if not observation then
        return
    end
    observation.connection:Disconnect()
    self.observations[model] = nil
    if self.context.removeHandler then
        self.context.removeHandler(observation.handler)
    end
end

function EnemyObserver:_observe(model)
    if self.observations[model] then
        return
    end
    local handler = self.context.characterController:GetCharacterHandler(model)
    local animator = handler and handler.Animator
    if not animator then
        return
    end
    local function observe(track)
        self.context.observeTrack(handler, track, model)
    end
    self.observations[model] = {
        connection = animator.AnimationPlayed:Connect(observe),
        handler = handler,
    }
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        observe(track)
    end
end

function EnemyObserver:refresh(lockedTarget)
    if self.stopped then
        return
    end
    local lockedModel = lockedTarget and lockedTarget:FindFirstAncestorWhichIsA("Model")
    local localPlayer = self.context.localPlayer
    local candidates = {}
    local modelBySnapshot = {}
    for _, player in ipairs(self.context.players:GetPlayers()) do
        local snapshot = {
            player = player,
            character = characterSnapshot(player.Character),
        }
        table.insert(candidates, snapshot)
        if snapshot.character then
            modelBySnapshot[snapshot] = snapshot.character.model
        end
    end
    local localSnapshot = {
        player = localPlayer,
        character = characterSnapshot(localPlayer.Character),
    }
    local lockedSnapshot = lockedModel and {
        character = characterSnapshot(lockedModel),
    } or nil
    local current = {}
    for _, candidate in ipairs(EnemyPolicy.filter(localSnapshot, candidates, lockedSnapshot)) do
        local model = modelBySnapshot[candidate]
        if model then
            current[model] = true
        end
    end

    -- A lock can point at an NPC or a player omitted by Players:GetPlayers().
    if lockedModel and lockedModel:GetAttribute("IsDead") ~= true then
        current[lockedModel] = true
    end
    for model in pairs(current) do
        self:_observe(model)
    end
    for model in pairs(self.observations) do
        if not current[model] then
            self:_disconnect(model)
        end
    end
end

function EnemyObserver:clear()
    for model in pairs(self.observations) do
        self:_disconnect(model)
    end
end

function EnemyObserver:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    self:clear()
end

return EnemyObserver
