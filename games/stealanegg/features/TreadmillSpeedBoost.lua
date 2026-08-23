local TreadmillSpeedBoost = {}
TreadmillSpeedBoost.__index = TreadmillSpeedBoost

local MULTIPLIER = 4

local function treadmillAncestor(instance)
    local current = instance
    while current and current ~= workspace do
        local name = current.Name:lower()
        if name:find("treadmill", 1, true) or name:find("runningmachine", 1, true) then
            return current
        end
        current = current.Parent
    end
    return nil
end

function TreadmillSpeedBoost.new(options)
    assert(options and options.localPlayer and options.runService and options.workspace)
    return setmetatable({
        localPlayer = options.localPlayer,
        runService = options.runService,
        workspace = options.workspace,
        enabled = false,
    }, TreadmillSpeedBoost)
end

function TreadmillSpeedBoost:_restore()
    if self.humanoid and self.nativeSpeed then
        self.humanoid.WalkSpeed = self.nativeSpeed
    end
    self.humanoid = nil
    self.nativeSpeed = nil
end

function TreadmillSpeedBoost:_step()
    local character = self.localPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then
        self:_restore()
        return
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { character }
    local result = self.workspace:Raycast(root.Position, Vector3.new(0, -7, 0), params)
    local onTreadmill = result and treadmillAncestor(result.Instance) ~= nil

    if not onTreadmill then
        self:_restore()
        return
    end

    if self.humanoid ~= humanoid then
        self:_restore()
        self.humanoid = humanoid
        self.nativeSpeed = humanoid.WalkSpeed
    elseif humanoid.WalkSpeed ~= self.nativeSpeed * MULTIPLIER then
        self.nativeSpeed = humanoid.WalkSpeed
    end
    humanoid.WalkSpeed = self.nativeSpeed * MULTIPLIER
end

function TreadmillSpeedBoost:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then return end
    self.enabled = enabled
    if enabled then
        self.connection = self.runService.Heartbeat:Connect(function()
            self:_step()
        end)
    else
        if self.connection then self.connection:Disconnect() self.connection = nil end
        self:_restore()
    end
end

function TreadmillSpeedBoost:stop()
    self:setEnabled(false)
end

return TreadmillSpeedBoost
