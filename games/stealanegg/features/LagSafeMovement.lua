local LagSafeMovement = {}
LagSafeMovement.__index = LagSafeMovement

function LagSafeMovement.new(options)
    assert(options and options.eggCmds and options.localPlayer and options.runService)
    return setmetatable({
        eggCmds = options.eggCmds,
        enabled = false,
        factor = 0.65,
        guardSpeeds = assert(options.guardSpeeds),
        localPlayer = options.localPlayer,
        runService = options.runService,
    }, LagSafeMovement)
end

function LagSafeMovement:_humanoid()
    local character = self.localPlayer.Character
    return character and character:FindFirstChildOfClass("Humanoid") or nil
end

function LagSafeMovement:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then
        return
    end
    self.enabled = enabled
    if enabled then
        self.carrying = false
        for _, record in ipairs(self.eggCmds.GetAreaEggSnapshot().Records) do
            if record.State == "Carried" and record.CarrierUserId == self.localPlayer.UserId then
                self.carrying = true
                break
            end
        end
        self.carryConnection = self.eggCmds.AreaEggCarryStateChanged:Connect(function(state)
            self.carrying = state.IsCarrying == true
        end)
        self.connection = self.runService.Heartbeat:Connect(function()
            local humanoid = self:_humanoid()
            if not humanoid then
                return
            end
            local areaId = self.localPlayer:GetAttribute("AreaId")
            local guardSpeed = self.guardSpeeds[areaId]
            if not self.carrying or type(guardSpeed) ~= "number" or guardSpeed < 180 then
                if humanoid == self.humanoid and humanoid.WalkSpeed == self.appliedSpeed then
                    humanoid.WalkSpeed = self.baseSpeed
                end
                self.humanoid = nil
                self.baseSpeed = nil
                self.appliedSpeed = nil
                return
            end
            if humanoid ~= self.humanoid or humanoid.WalkSpeed ~= self.appliedSpeed then
                self.humanoid = humanoid
                self.baseSpeed = humanoid.WalkSpeed
            end
            self.appliedSpeed = self.baseSpeed * self.factor
            humanoid.WalkSpeed = self.appliedSpeed
        end)
    else
        if self.carryConnection then
            self.carryConnection:Disconnect()
            self.carryConnection = nil
        end
        self.carrying = false
        if self.connection then
            self.connection:Disconnect()
            self.connection = nil
        end
        if
            self.humanoid
            and self.humanoid.Parent
            and self.humanoid.WalkSpeed == self.appliedSpeed
        then
            self.humanoid.WalkSpeed = self.baseSpeed
        end
        self.humanoid = nil
        self.baseSpeed = nil
        self.appliedSpeed = nil
    end
end

function LagSafeMovement:stop()
    self:setEnabled(false)
end

return LagSafeMovement
