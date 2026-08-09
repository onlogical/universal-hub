local ObservationRuntime = {}
ObservationRuntime.__index = ObservationRuntime

function ObservationRuntime.new(options)
    assert(options and options.targeting, "RIVALS observations require Hydroxide Targeting")
    assert(options.workspace, "RIVALS observations require Workspace")
    assert(options.getFighter, "RIVALS observations require a fighter getter")
    return setmetatable({
        effects = options.effects,
        equippedWeapon = options.equippedWeapon,
        getFighter = options.getFighter,
        isOpponent = options.isOpponent,
        maximumDistance = options.maximumDistance or 2000,
        targeting = options.targeting,
        workspace = options.workspace,
    }, ObservationRuntime)
end

function ObservationRuntime:update(screenOrigin)
    local raycastIgnore = self.effects and self.effects:smokeRaycastIgnore() or {}
    local observations = self.targeting.observePlayers({
        isEligible = self.isOpponent,
        raycastIgnore = raycastIgnore,
        screenOrigin = screenOrigin,
    })
    local fighter = self.getFighter()
    local data = fighter and fighter.Data
    local camera = self.workspace.CurrentCamera
    local rangeEntities = self.workspace:FindFirstChild("ShootingRangeEntities")
    if type(data) == "table" and data.IsInShootingRange and camera and rangeEntities then
        for _, entity in ipairs(rangeEntities:GetChildren()) do
            local humanoid = entity:FindFirstChildOfClass("Humanoid")
            local environmentID = entity:GetAttribute("EnvironmentID")
            local root = entity:FindFirstChild("HumanoidRootPart")
            local onScreen = false
            if root then
                local _viewportPoint
                _viewportPoint, onScreen = camera:WorldToViewportPoint(root.Position)
            end
            if entity:IsA("Model")
                and humanoid
                and humanoid.Health > 0
                and (data.EnvironmentID == nil or environmentID == data.EnvironmentID)
                and onScreen
            then
                local observation = self.targeting.observeCharacter(entity, {
                    screenOrigin = screenOrigin,
                })
                if observation then
                    observation.player = entity
                    observation.health = humanoid.Health
                    observation.maxHealth = humanoid.MaxHealth
                    table.insert(observations, observation)
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
            if observation.position
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
            observation.weapon = self.equippedWeapon and self.equippedWeapon(observation.player) or nil
        end
    end
    return nearby
end

return ObservationRuntime
