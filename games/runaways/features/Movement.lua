local Movement = {}
Movement.__index = Movement

local function humanoidAndRoot(character)
    return character and character:FindFirstChildOfClass("Humanoid"),
        character and character:FindFirstChild("HumanoidRootPart")
end

function Movement.new()
    return setmetatable({ stopped = false }, Movement)
end

function Movement:releaseFly()
    local humanoid = self.flyHumanoid
    if humanoid and humanoid.Parent then
        humanoid.PlatformStand = self.flyPlatformStand == true
    end
    if self.flyRoot and self.flyRoot.Parent then
        self.flyRoot.AssemblyLinearVelocity = Vector3.zero
    end
    self.flyHumanoid = nil
    self.flyPlatformStand = nil
    self.flyRoot = nil
end

function Movement:releaseSpeed()
    local humanoid = self.speedHumanoid
    if humanoid and humanoid.Parent and humanoid.WalkSpeed == self.appliedWalkSpeed then
        humanoid.WalkSpeed = self.speedOriginal
    end
    self.speedHumanoid = nil
    self.speedOriginal = nil
    self.appliedWalkSpeed = nil
end

function Movement:update(settings, character, camera, input)
    if self.stopped then
        return
    end
    local humanoid, root = humanoidAndRoot(character)

    if settings.speed == true and humanoid then
        local desired = math.clamp(tonumber(settings.walkSpeed) or 32, 16, 100)
        if self.speedHumanoid ~= humanoid then
            self:releaseSpeed()
            self.speedHumanoid = humanoid
            self.speedOriginal = humanoid.WalkSpeed
        end
        humanoid.WalkSpeed = desired
        self.appliedWalkSpeed = desired
    else
        self:releaseSpeed()
    end

    if settings.fly ~= true or not humanoid or not root or not camera then
        self:releaseFly()
        return
    end
    if self.flyHumanoid ~= humanoid then
        self:releaseFly()
        self.flyHumanoid = humanoid
        self.flyPlatformStand = humanoid.PlatformStand
        self.flyRoot = root
    end

    humanoid.PlatformStand = true
    local direction = Vector3.zero
    if input:IsKeyDown(Enum.KeyCode.W) then
        direction += camera.CFrame.LookVector
    end
    if input:IsKeyDown(Enum.KeyCode.S) then
        direction -= camera.CFrame.LookVector
    end
    if input:IsKeyDown(Enum.KeyCode.D) then
        direction += camera.CFrame.RightVector
    end
    if input:IsKeyDown(Enum.KeyCode.A) then
        direction -= camera.CFrame.RightVector
    end
    if input:IsKeyDown(Enum.KeyCode.Space) then
        direction += Vector3.yAxis
    end
    if input:IsKeyDown(Enum.KeyCode.LeftControl) then
        direction -= Vector3.yAxis
    end
    local speed = math.clamp(tonumber(settings.flySpeed) or 60, 20, 500)
    root.AssemblyLinearVelocity = direction.Magnitude > 1e-3 and direction.Unit * speed
        or Vector3.zero
end

function Movement:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    self:releaseFly()
    self:releaseSpeed()
end

return Movement
