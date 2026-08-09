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

local UtilityPolicy = importDependency("games/rivals/UtilityPolicy", "./UtilityPolicy")
local VisualSuppression = importDependency("games/rivals/VisualSuppression", "./VisualSuppression")
local TrajectoryRenderer = importDependency("games/rivals/TrajectoryRenderer", "./TrajectoryRenderer")
local Effects = {}
Effects.__index = Effects

local THROWABLE_MAX_DISTANCE = 2000
local THROWABLE_REFRESH_INTERVAL = 0.2
local WIREFRAME_CUBE_OFFSETS = {
    Vector3.new(-0.5, -0.5, -0.5),
    Vector3.new(0.5, -0.5, -0.5),
    Vector3.new(0.5, 0.5, -0.5),
    Vector3.new(-0.5, 0.5, -0.5),
    Vector3.new(-0.5, -0.5, 0.5),
    Vector3.new(0.5, -0.5, 0.5),
    Vector3.new(0.5, 0.5, 0.5),
    Vector3.new(-0.5, 0.5, 0.5),
}
local function hierarchyAttribute(instance, name)
    local current = instance
    for _depth = 1, 32 do
        if not current then
            break
        end
        if current.GetAttribute then
            local succeeded, value = pcall(current.GetAttribute, current, name)
            if succeeded and value ~= nil then
                return value
            end
        end
        current = current.Parent
    end
    return nil
end

local function isWorldUtility(root, camera, worldRoot, localPlayer)
    local current = root
    local reachedWorld = worldRoot == nil
    local localCharacter = localPlayer and localPlayer.Character
    for _depth = 1, 32 do
        if not current then
            break
        end
        if current == worldRoot then
            reachedWorld = true
        end
        if current == camera or current == localCharacter then
            return false
        end
        if current.IsA then
            local succeeded, isCamera = pcall(current.IsA, current, "Camera")
            if succeeded and isCamera then
                return false
            end
        end
        current = current.Parent
    end
    return reachedWorld
end

local function projectWireframeCube(camera, boundsFrame, boundsSize)
    if not boundsFrame or not boundsSize then
        return nil
    end

    local corners = {}
    local minimumX = math.huge
    local minimumY = math.huge
    local maximumX = -math.huge
    local anyOnScreen = false
    for _, offset in ipairs(WIREFRAME_CUBE_OFFSETS) do
        local worldPosition = boundsFrame:PointToWorldSpace(Vector3.new(
            offset.X * boundsSize.X,
            offset.Y * boundsSize.Y,
            offset.Z * boundsSize.Z
        ))
        local point, onScreen = camera:WorldToViewportPoint(worldPosition)
        if point.Z <= 0 then
            return nil
        end
        local corner = Vector2.new(point.X, point.Y)
        table.insert(corners, corner)
        minimumX = math.min(minimumX, corner.X)
        minimumY = math.min(minimumY, corner.Y)
        maximumX = math.max(maximumX, corner.X)
        anyOnScreen = anyOnScreen or onScreen == true
    end
    return corners, Vector2.new((minimumX + maximumX) * 0.5, minimumY - 16), anyOnScreen
end

Effects.updateVisualSuppressions = VisualSuppression.update

function Effects.throwableObservation(camera, candidate, environmentID, worldRoot, localPlayer)
    local descriptor, root = UtilityPolicy.descriptor(candidate)
    if not descriptor or not camera or not root then
        return nil
    end
    if root.Parent == nil and candidate.Parent == nil then
        return nil
    end
    if not isWorldUtility(root, camera, worldRoot, localPlayer) then
        return nil
    end

    local finished = hierarchyAttribute(root, "SimulationFinished") == true
        or hierarchyAttribute(root, "Exploded") == true
        or hierarchyAttribute(root, "Detonated") == true
    if finished then
        return nil
    end
    local observedEnvironment = hierarchyAttribute(root, "EnvironmentID")
    if environmentID ~= nil and observedEnvironment ~= nil and observedEnvironment ~= environmentID then
        return nil
    end

    local part
    if candidate.IsA and candidate:IsA("BasePart") then
        part = candidate
    elseif root.IsA and root:IsA("BasePart") then
        part = root
    else
        part = root.PrimaryPart
            or (root.FindFirstChildWhichIsA and root:FindFirstChildWhichIsA("BasePart", true))
    end
    if not part or not part.Position then
        return nil
    end

    local cameraPosition = camera.CFrame and camera.CFrame.Position
    if cameraPosition and (part.Position - cameraPosition).Magnitude > THROWABLE_MAX_DISTANCE then
        return nil
    end
    local point, onScreen = camera:WorldToViewportPoint(part.Position)
    local markerStyle
    local wireframeCorners
    local labelPosition
    local wireframeOnScreen = false
    if descriptor.markerStyle == "wireframeCube" then
        local boundsFrame
        local boundsSize
        if root.GetBoundingBox then
            local succeeded
            succeeded, boundsFrame, boundsSize = pcall(root.GetBoundingBox, root)
            if not succeeded then
                boundsFrame = nil
                boundsSize = nil
            end
        end
        boundsFrame = boundsFrame or part.CFrame
        boundsSize = boundsSize or part.Size
        wireframeCorners, labelPosition, wireframeOnScreen =
            projectWireframeCube(camera, boundsFrame, boundsSize)
        if wireframeCorners then
            markerStyle = descriptor.markerStyle
        end
    end
    return {
        key = root,
        label = descriptor.label,
        labelPosition = labelPosition,
        markerStyle = markerStyle,
        onScreen = point.Z > 0 and (onScreen == true or wireframeOnScreen),
        polygons = {},
        screenPosition = Vector2.new(point.X, point.Y),
        tone = descriptor.tone,
        wireframeCorners = wireframeCorners,
    }
end

function Effects.new(options)
    assert(options and options.workspace, "RIVALS effects require Workspace")
    assert(options.localPlayer, "RIVALS effects require LocalPlayer")
    assert(options.projectileAim, "RIVALS effects require projectile aim")

    return setmetatable({
        clock = options.clock or os.clock,
        collectionService = options.collectionService,
        lighting = options.lighting,
        localPlayer = options.localPlayer,
        nextThrowableRefreshAt = 0,
        nextVisualRefreshAt = 0,
        playerGui = options.playerGui,
        suppressedVisuals = setmetatable({}, { __mode = "k" }),
        throwableCandidates = {},
        trajectoryRenderer = TrajectoryRenderer.new(options),
        workspace = options.workspace,
    }, Effects)
end

function Effects:_collectThrowables()
    local candidates = {}
    local seen = {}
    local function collect(values)
        for _, value in ipairs(values or {}) do
            if value and not seen[value] then
                seen[value] = true
                table.insert(candidates, value)
            end
        end
    end

    if self.collectionService and self.collectionService.GetTagged then
        for _, tag in ipairs(UtilityPolicy.TAGS) do
            local succeeded, tagged =
                pcall(self.collectionService.GetTagged, self.collectionService, tag)
            if succeeded then
                collect(tagged)
            end
        end
    end
    return candidates
end

function Effects:smokeRaycastIgnore()
    if not self.collectionService or not self.collectionService.GetTagged then
        return {}
    end
    local succeeded, smokeClouds =
        pcall(self.collectionService.GetTagged, self.collectionService, "SmokeCloud")
    return succeeded and smokeClouds or {}
end

function Effects:observeThrowables(camera, environmentID)
    local now = self.clock()
    if now >= self.nextThrowableRefreshAt then
        self.throwableCandidates = self:_collectThrowables()
        self.nextThrowableRefreshAt = now + THROWABLE_REFRESH_INTERVAL
    end

    local utilities = {}
    for _, candidate in ipairs(self.throwableCandidates) do
        local observation = Effects.throwableObservation(
            camera,
            candidate,
            environmentID,
            self.workspace,
            self.localPlayer
        )
        if observation then
            table.insert(utilities, observation)
        end
    end
    return utilities
end

function Effects:update(settings)
    if settings.noFlash ~= true and settings.noSmoke ~= true then
        if next(self.suppressedVisuals) ~= nil then
            Effects.updateVisualSuppressions({}, {}, self.suppressedVisuals)
        end
        return
    end
    local now = self.clock()
    if now < self.nextVisualRefreshAt then
        return
    end
    self.nextVisualRefreshAt = now + 0.1

    local roots = { self.lighting, self.workspace.CurrentCamera }
    local playerGui = self.playerGui
    if not playerGui and self.localPlayer.FindFirstChildOfClass then
        playerGui = self.localPlayer:FindFirstChildOfClass("PlayerGui")
    end
    if playerGui then
        table.insert(roots, playerGui)
    end
    if settings.noSmoke then
        for _, candidate in ipairs(self.throwableCandidates) do
            local descriptor, root = UtilityPolicy.descriptor(candidate)
            if descriptor and descriptor.tone == "smoke" then
                table.insert(roots, {
                    instance = root,
                    kind = "smoke",
                })
            end
        end
    end
    Effects.updateVisualSuppressions(settings, roots, self.suppressedVisuals)
end

function Effects:renderTrajectory(path)
    self.trajectoryRenderer:render(path)
end

function Effects:stop()
    Effects.updateVisualSuppressions({}, {}, self.suppressedVisuals)
    self.trajectoryRenderer:stop()
end

return Effects
