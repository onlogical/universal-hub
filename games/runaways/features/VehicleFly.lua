local VehicleFly = {}
VehicleFly.__index = VehicleFly

function VehicleFly.new()
    return setmetatable({ root = nil, stopped = false }, VehicleFly)
end

function VehicleFly:release()
    if self.root and self.root.Parent then
        self.root.AssemblyLinearVelocity = Vector3.zero
        self.root.AssemblyAngularVelocity = Vector3.zero
    end
    self.root = nil
end

function VehicleFly:update(settings, character, camera, input)
    if self.stopped then
        return
    end
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local seat = humanoid and humanoid.SeatPart
    if
        settings.vehicleFly ~= true
        or not camera
        or not seat
        or not (seat:IsA("Seat") or seat:IsA("VehicleSeat"))
        or seat.Occupant ~= humanoid
    then
        self:release()
        return
    end
    local root = seat.AssemblyRootPart or seat
    self.root = root

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
    local speed = math.max(tonumber(settings.vehicleFlySpeed) or 100, 0)
    root.AssemblyLinearVelocity = direction.Magnitude > 1e-3 and direction.Unit * speed
        or Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end

function VehicleFly:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    self:release()
end

return VehicleFly
