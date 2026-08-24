local UtilityPolicy = require("./UtilityPolicy")
local VisualSuppression = require("./VisualSuppression")
local TrajectoryRenderer = require("./TrajectoryRenderer")
local Effects = {}
Effects.__index = Effects

local THROWABLE_MAX_DISTANCE = 2000
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
local function connectSignal(signal, callback)
    if not signal or type(signal.Connect) ~= "function" then
        return nil
    end
    local succeeded, connection = pcall(signal.Connect, signal, callback)
    return succeeded and connection or nil
end

local function disconnect(connection)
    if connection and type(connection.Disconnect) == "function" then
        pcall(connection.Disconnect, connection)
    end
end

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
        local worldPosition = boundsFrame:PointToWorldSpace(
            Vector3.new(offset.X * boundsSize.X, offset.Y * boundsSize.Y, offset.Z * boundsSize.Z)
        )
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
    if
        environmentID ~= nil
        and observedEnvironment ~= nil
        and observedEnvironment ~= environmentID
    then
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
        worldPosition = part.Position,
    }
end

function Effects.new(options)
    assert(options and options.workspace, "RIVALS effects require Workspace")
    assert(options.localPlayer, "RIVALS effects require LocalPlayer")
    assert(options.projectileAim, "RIVALS effects require projectile aim")

    local self = setmetatable({
        clock = options.clock or os.clock,
        collectionService = options.collectionService,
        lighting = options.lighting,
        localPlayer = options.localPlayer,
        playerGui = options.playerGui,
        suppressedVisuals = setmetatable({}, { __mode = "k" }),
        throwableCandidates = {},
        throwableCandidateSet = setmetatable({}, { __mode = "k" }),
        throwableTagCounts = setmetatable({}, { __mode = "k" }),
        taggedCandidates = {},
        smokeCandidates = setmetatable({}, { __mode = "k" }),
        tagConnections = {},
        visualConnections = {},
        visualLifecycleConnections = {},
        visualRoots = {},
        smokeVisualConnections = setmetatable({}, { __mode = "k" }),
        visualNoFlash = false,
        visualNoSmoke = false,
        trajectoryRenderer = TrajectoryRenderer.new(options),
        workspace = options.workspace,
    }, Effects)
    self:_startThrowableRegistry()
    return self
end

function Effects:_addTaggedCandidate(tag, candidate)
    if not candidate then
        return
    end
    local tagged = self.taggedCandidates[tag]
    if tagged[candidate] then
        return
    end
    tagged[candidate] = true
    local count = (self.throwableTagCounts[candidate] or 0) + 1
    self.throwableTagCounts[candidate] = count
    if count == 1 then
        self.throwableCandidateSet[candidate] = true
        table.insert(self.throwableCandidates, candidate)
    end
    if tag == "SmokeCloud" then
        self.smokeCandidates[candidate] = true
        if self.visualNoSmoke then
            self:_attachSmokeVisual(candidate)
        end
    end
end

function Effects:_removeTaggedCandidate(tag, candidate)
    local tagged = self.taggedCandidates[tag]
    if not tagged or not tagged[candidate] then
        return
    end
    tagged[candidate] = nil
    if tag == "SmokeCloud" then
        self.smokeCandidates[candidate] = nil
        self:_detachSmokeVisual(candidate)
    end
    local count = (self.throwableTagCounts[candidate] or 1) - 1
    if count > 0 then
        self.throwableTagCounts[candidate] = count
        return
    end
    self.throwableTagCounts[candidate] = nil
    self.throwableCandidateSet[candidate] = nil
    for index, value in ipairs(self.throwableCandidates) do
        if value == candidate then
            table.remove(self.throwableCandidates, index)
            break
        end
    end
end

function Effects:_startThrowableRegistry()
    local service = self.collectionService
    if not service then
        return
    end
    for _, tag in ipairs(UtilityPolicy.TAGS) do
        self.taggedCandidates[tag] = setmetatable({}, { __mode = "k" })
        if service.GetInstanceAddedSignal then
            local succeeded, signal = pcall(service.GetInstanceAddedSignal, service, tag)
            if succeeded then
                local connection = connectSignal(signal, function(candidate)
                    self:_addTaggedCandidate(tag, candidate)
                end)
                if connection then
                    table.insert(self.tagConnections, connection)
                end
            end
        end
        if service.GetInstanceRemovedSignal then
            local succeeded, signal = pcall(service.GetInstanceRemovedSignal, service, tag)
            if succeeded then
                local connection = connectSignal(signal, function(candidate)
                    self:_removeTaggedCandidate(tag, candidate)
                end)
                if connection then
                    table.insert(self.tagConnections, connection)
                end
            end
        end
        if service.GetTagged then
            local succeeded, candidates = pcall(service.GetTagged, service, tag)
            if succeeded then
                for _, candidate in ipairs(candidates or {}) do
                    self:_addTaggedCandidate(tag, candidate)
                end
            end
        end
    end
end

-- Kept for callers/tests that use the old helper. Discovery itself is now event-driven.
function Effects:_collectThrowables()
    local candidates = {}
    for _, candidate in ipairs(self.throwableCandidates) do
        table.insert(candidates, candidate)
    end
    return candidates
end

function Effects:smokeRaycastIgnore()
    local smokeClouds = {}
    for candidate in pairs(self.smokeCandidates) do
        table.insert(smokeClouds, candidate)
    end
    return smokeClouds
end

function Effects:observeThrowables(camera, environmentID)
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

function Effects:_disconnectVisualRoots()
    for _, connection in ipairs(self.visualConnections) do
        disconnect(connection)
    end
    for _, connection in ipairs(self.visualLifecycleConnections) do
        disconnect(connection)
    end
    self.visualConnections = {}
    self.visualLifecycleConnections = {}
    self.visualRoots = {}
end

function Effects:_globalVisualRoots()
    local playerGui = self.playerGui
    if not playerGui and self.localPlayer.FindFirstChildOfClass then
        playerGui = self.localPlayer:FindFirstChildOfClass("PlayerGui")
    end
    local roots = {}
    if self.lighting then
        table.insert(roots, self.lighting)
    end
    if self.workspace.CurrentCamera then
        table.insert(roots, self.workspace.CurrentCamera)
    end
    if playerGui then
        table.insert(roots, playerGui)
    end
    return roots
end

function Effects:_startFlashVisuals()
    self:_disconnectVisualRoots()
    self.visualRoots = self:_globalVisualRoots()
    for _, root in ipairs(self.visualRoots) do
        local added = connectSignal(root.DescendantAdded, function(instance)
            VisualSuppression.apply({ noFlash = true }, { instance }, self.suppressedVisuals)
        end)
        local removing = connectSignal(root.DescendantRemoving, function(instance)
            VisualSuppression.restoreRoots({ instance }, self.suppressedVisuals)
        end)
        if added then
            table.insert(self.visualConnections, added)
        end
        if removing then
            table.insert(self.visualConnections, removing)
        end
    end

    -- Camera replacement is rare, but must also remain event-driven.
    if self.workspace.GetPropertyChangedSignal then
        local succeeded, signal =
            pcall(self.workspace.GetPropertyChangedSignal, self.workspace, "CurrentCamera")
        if succeeded then
            local connection = connectSignal(signal, function()
                if self.visualNoFlash then
                    for _, root in ipairs(self.visualRoots) do
                        VisualSuppression.restoreRoots({ root }, self.suppressedVisuals)
                    end
                    self:_startFlashVisuals()
                end
            end)
            if connection then
                table.insert(self.visualLifecycleConnections, connection)
            end
        end
    end
    VisualSuppression.apply({ noFlash = true }, self.visualRoots, self.suppressedVisuals)
end

function Effects:_stopFlashVisuals()
    for _, root in ipairs(self.visualRoots) do
        VisualSuppression.restoreRoots({ root }, self.suppressedVisuals)
    end
    self:_disconnectVisualRoots()
end

function Effects:_attachSmokeVisual(candidate)
    if not candidate or self.smokeVisualConnections[candidate] then
        return
    end
    local descriptor, root = UtilityPolicy.descriptor(candidate)
    if not descriptor or descriptor.tone ~= "smoke" or not root then
        return
    end

    local connections = { root = root }
    local added = connectSignal(root.DescendantAdded, function(instance)
        VisualSuppression.apply({ noSmoke = true }, {
            { instance = instance, kind = "smoke" },
        }, self.suppressedVisuals)
    end)
    local removing = connectSignal(root.DescendantRemoving, function(instance)
        VisualSuppression.restoreRoots({ instance }, self.suppressedVisuals)
    end)
    if added then
        table.insert(connections, added)
    end
    if removing then
        table.insert(connections, removing)
    end
    self.smokeVisualConnections[candidate] = connections
    VisualSuppression.apply({ noSmoke = true }, {
        { instance = root, kind = "smoke" },
    }, self.suppressedVisuals)
end

function Effects:_detachSmokeVisual(candidate)
    local connections = self.smokeVisualConnections[candidate]
    if not connections then
        return
    end
    for _, connection in ipairs(connections) do
        disconnect(connection)
    end
    VisualSuppression.restoreRoots({ connections.root }, self.suppressedVisuals)
    self.smokeVisualConnections[candidate] = nil
end

function Effects:_stopSmokeVisuals()
    local candidates = {}
    for candidate in pairs(self.smokeVisualConnections) do
        table.insert(candidates, candidate)
    end
    for _, candidate in ipairs(candidates) do
        self:_detachSmokeVisual(candidate)
    end
end

function Effects:update(settings)
    local noFlash = settings.noFlash == true
    local noSmoke = settings.noSmoke == true
    if noFlash == self.visualNoFlash and noSmoke == self.visualNoSmoke then
        return
    end

    if noFlash ~= self.visualNoFlash then
        self.visualNoFlash = noFlash
        if noFlash then
            self:_startFlashVisuals()
        else
            self:_stopFlashVisuals()
        end
    end
    if noSmoke ~= self.visualNoSmoke then
        self.visualNoSmoke = noSmoke
        if noSmoke then
            for candidate in pairs(self.smokeCandidates) do
                self:_attachSmokeVisual(candidate)
            end
        else
            self:_stopSmokeVisuals()
        end
    end
end

function Effects:renderTrajectory(path)
    self.trajectoryRenderer:render(path)
end

function Effects:stop()
    self:_stopSmokeVisuals()
    Effects.updateVisualSuppressions({}, {}, self.suppressedVisuals)
    self:_disconnectVisualRoots()
    for _, connection in ipairs(self.tagConnections) do
        disconnect(connection)
    end
    self.tagConnections = {}
    self.trajectoryRenderer:stop()
end

return Effects
