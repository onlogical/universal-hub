local ObservationRuntime = {}
ObservationRuntime.__index = ObservationRuntime

function ObservationRuntime.rangeHealth(humanoid)
    local health = humanoid.Health
    local maximum = humanoid.MaxHealth
    if health == math.huge or maximum == math.huge then
        return 150, 150
    end
    return health, maximum
end

function ObservationRuntime.new(options)
    assert(options and options.targeting, "RIVALS observations require Hydroxide Targeting")
    assert(options.workspace, "RIVALS observations require Workspace")
    assert(options.getFighter, "RIVALS observations require a fighter getter")
    return setmetatable({
        effects = options.effects,
        equippedWeapon = options.equippedWeapon,
        getFighter = options.getFighter,
        getPlayerTone = options.getPlayerTone,
        isOpponent = options.isOpponent,
        maximumDistance = options.maximumDistance or 2000,
        targeting = options.targeting,
        workspace = options.workspace,
    }, ObservationRuntime)
end

function ObservationRuntime:update(screenOrigin, includeTeammates, includeEnemies)
    local raycastIgnore = self.effects and self.effects:smokeRaycastIgnore() or {}
    local eligibility = self.isOpponent
    if includeTeammates and self.getPlayerTone then
        eligibility = function(player, character)
            return self.getPlayerTone(player, character) ~= nil
        end
    end
    local observations = self.targeting.observePlayers({
        isEligible = eligibility,
        raycastIgnore = raycastIgnore,
        screenOrigin = screenOrigin,
    })
    local fighter = self.getFighter()
    local data = fighter and fighter.Data
    local camera = self.workspace.CurrentCamera
    local rangeEntities = self.workspace:FindFirstChild("ShootingRangeEntities")
    if type(data) == "table" and data.IsInShootingRange and camera and rangeEntities then
        local containers = { rangeEntities }
        local hurtEffect = self.workspace:FindFirstChild("HurtEffect")
        if hurtEffect then
            table.insert(containers, hurtEffect)
        end
        for _, container in ipairs(containers) do
            for _, entity in ipairs(container:GetChildren()) do
                local humanoid = entity:FindFirstChildOfClass("Humanoid")
                local environmentID = entity:GetAttribute("EnvironmentID")
                if
                    entity:IsA("Model")
                    and humanoid
                    and humanoid.Health > 0
                    and (data.EnvironmentID == nil or environmentID == data.EnvironmentID)
                then
                    local observation = self.targeting.observeCharacter(entity, {
                        screenOrigin = screenOrigin,
                    })
                    if observation then
                        observation.player = entity
                        observation.health, observation.maxHealth =
                            ObservationRuntime.rangeHealth(humanoid)
                        table.insert(observations, observation)
                    end
                end
            end
        end
    end
    local cameraFrame = camera
        and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
    local cameraPosition = cameraFrame and cameraFrame.Position
    local nearby = {}
    if cameraPosition then
        for _, observation in ipairs(observations) do
            if
                observation.position
                and (observation.position - cameraPosition).Magnitude <= self.maximumDistance
            then
                table.insert(nearby, observation)
            end
        end
    end
    for _, observation in ipairs(nearby) do
        if observation.player ~= observation.character then
            local character = observation.character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            observation.health = humanoid and humanoid.Health or nil
            observation.maxHealth = humanoid and humanoid.MaxHealth or nil
            observation.weapon = self.equippedWeapon and self.equippedWeapon(observation.player)
                or nil
            observation.tone = self.getPlayerTone
                    and self.getPlayerTone(observation.player, character)
                or "enemy"
        end
    end
    local opponents = {}
    local allies = {}
    for _, observation in ipairs(nearby) do
        if observation.player ~= observation.character and observation.tone == "team" then
            table.insert(allies, observation)
        else
            table.insert(opponents, observation)
        end
    end
    if includeTeammates and includeEnemies ~= false then
        local visual = {}
        for _, observation in ipairs(opponents) do
            table.insert(visual, observation)
        end
        for _, observation in ipairs(allies) do
            table.insert(visual, observation)
        end
        return opponents, visual
    end
    if includeTeammates then
        return opponents, allies
    end
    if includeEnemies == false then
        return opponents, {}
    end
    return opponents, opponents
end

return ObservationRuntime
