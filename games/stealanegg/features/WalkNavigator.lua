local WalkNavigator = {}
WalkNavigator.__index = WalkNavigator

local function characterParts(localPlayer)
    local character = localPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if humanoid and root and root:IsA("BasePart") then
        return humanoid, root
    end
    return nil, nil
end

function WalkNavigator.new(options)
    assert(options and options.localPlayer and options.runService)
    return setmetatable({
        localPlayer = options.localPlayer,
        pathfindingService = options.pathfindingService,
        runService = options.runService,
        workspace = options.workspace or workspace,
        stopped = false,
    }, WalkNavigator)
end

function WalkNavigator:_waitForCharacter(isActive)
    local deadline = self.workspace:GetServerTimeNow() + 12
    while not self.stopped and isActive() and self.workspace:GetServerTimeNow() <= deadline do
        local humanoid, root = characterParts(self.localPlayer)
        if humanoid and root then
            return humanoid, root
        end
        self.runService.Heartbeat:Wait()
    end
    return nil, nil
end

function WalkNavigator:_walkPoint(position, isActive, tolerance)
    local humanoid, root = self:_waitForCharacter(isActive)
    if not humanoid then
        return false, "character-unavailable"
    end
    local deadline = self.workspace:GetServerTimeNow()
        + math.max(10, (root.Position - position).Magnitude / 6)
    local nextMove = -math.huge
    while not self.stopped and isActive() and self.workspace:GetServerTimeNow() <= deadline do
        humanoid, root = characterParts(self.localPlayer)
        if not humanoid or not root then
            return false, "character-lost"
        end
        if (root.Position - position).Magnitude <= tolerance then
            return true
        end
        local now = self.workspace:GetServerTimeNow()
        if now >= nextMove then
            humanoid:MoveTo(position)
            nextMove = now + 1.5
        end
        self.runService.Heartbeat:Wait()
    end
    local cancelled = self.stopped or not isActive()
    if cancelled then
        humanoid, root = characterParts(self.localPlayer)
        if humanoid and root then
            humanoid:MoveTo(root.Position)
        end
    end
    return false, cancelled and "cancelled" or "timeout"
end

function WalkNavigator:_waypoints(startPosition, destination)
    if not self.pathfindingService then
        return nil
    end
    local path = self.pathfindingService:CreatePath({
        AgentCanJump = true,
        AgentRadius = 2,
        AgentHeight = 5,
        WaypointSpacing = 12,
    })
    local ok = pcall(path.ComputeAsync, path, startPosition, destination)
    if not ok or path.Status ~= Enum.PathStatus.Success then
        return nil
    end
    return path:GetWaypoints()
end

function WalkNavigator:walkTo(destination, isActive, tolerance)
    assert(typeof(destination) == "Vector3", "WalkNavigator destination must be a Vector3")
    isActive = isActive or function()
        return true
    end
    tolerance = tolerance or 7
    local _, root = self:_waitForCharacter(isActive)
    if not root then
        return false, "character-unavailable"
    end
    local waypoints = self:_waypoints(root.Position, destination)
    if waypoints then
        for _, waypoint in ipairs(waypoints) do
            if waypoint.Action == Enum.PathWaypointAction.Jump then
                local humanoid = characterParts(self.localPlayer)
                if humanoid then
                    humanoid.Jump = true
                end
            end
            local reached, reason = self:_walkPoint(waypoint.Position, isActive, tolerance)
            if not reached then
                return false, reason
            end
        end
    end
    return self:_walkPoint(destination, isActive, tolerance)
end

function WalkNavigator:moveToDirect(destination, isActive, tolerance)
    assert(typeof(destination) == "Vector3", "WalkNavigator destination must be a Vector3")
    return self:_walkPoint(destination, isActive or function()
        return true
    end, tolerance or 4)
end

function WalkNavigator:jump()
    local humanoid = characterParts(self.localPlayer)
    if not humanoid then
        return false
    end
    humanoid.Jump = true
    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    return true
end

function WalkNavigator:stop()
    self.stopped = true
    local humanoid, root = characterParts(self.localPlayer)
    if humanoid and root then
        humanoid:MoveTo(root.Position)
    end
end

return WalkNavigator
