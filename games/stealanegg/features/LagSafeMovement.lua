local LagSafeMovement = {}
LagSafeMovement.__index = LagSafeMovement

function LagSafeMovement.new(options)
    assert(options and options.eggCmds and options.localPlayer and options.runService)
    return setmetatable({
        eggCmds = options.eggCmds,
        enabled = false,
        clock = options.clock or os.clock,
        factor = 0.65,
        canOutrun = options.canOutrun or function()
            return nil
        end,
        getPing = options.getPing or function()
            return math.huge
        end,
        guardConfigs = assert(options.guardConfigs),
        guardModels = options.guardModels or {},
        hitIntervals = {},
        localPlayer = options.localPlayer,
        onEscape = options.onEscape,
        pingThreshold = options.pingThreshold or 170,
        reclaimDistance = options.reclaimDistance or 9,
        runService = options.runService,
        wakingDuration = options.wakingDuration or 0.63,
    }, LagSafeMovement)
end

function LagSafeMovement:_humanoid()
    local character = self.localPlayer.Character
    return character and character:FindFirstChildOfClass("Humanoid") or nil
end

function LagSafeMovement:_restore()
    if self.humanoid and self.humanoid.Parent and self.humanoid.WalkSpeed == self.appliedSpeed then
        self.humanoid.WalkSpeed = self.baseSpeed
    end
    self.humanoid = nil
    self.baseSpeed = nil
    self.appliedSpeed = nil
end

function LagSafeMovement:_resetEncounter()
    self.phase = nil
    self.phaseArea = nil
    self.wakingStartedAt = nil
end

function LagSafeMovement:_beginEscape()
    if self.phase ~= "escape" and type(self.onEscape) == "function" then
        pcall(self.onEscape)
    end
    self.phase = "escape"
end

function LagSafeMovement:_shouldBait(humanoid, areaId, config)
    if not self.carrying or type(config) ~= "table" then
        return false
    end
    local guardSpeed = tonumber(config.WalkSpeed)
    local flatRadius = tonumber(config.FlatRadius)
    local hitDistance = tonumber(config.HitDistance) or 10
    if not guardSpeed or not flatRadius then
        self:_resetEncounter()
        return false
    end
    local ping = tonumber(self.getPing()) or 0
    if ping < self.pingThreshold then
        self:_resetEncounter()
        return false
    end
    local playerSpeed = humanoid == self.humanoid and self.baseSpeed or humanoid.WalkSpeed
    local guard = self.guardModels[areaId]
    local character = self.localPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not guard or not guard.Parent or not root or not root:IsA("BasePart") then
        self:_resetEncounter()
        return false
    end
    local offset = guard:GetPivot().Position - root.Position
    local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
    if distance > flatRadius * 7 then
        self:_resetEncounter()
        return false
    end
    if type(playerSpeed) ~= "number" or self.canOutrun(areaId, playerSpeed) ~= false then
        self:_resetEncounter()
        return false
    end
    if self.phaseArea ~= areaId then
        self.phaseArea = areaId
        self.phase = "bait"
    end
    local slowedSpeed = playerSpeed * self.factor
    local releaseDistance = hitDistance + math.max(0, guardSpeed - slowedSpeed) * (ping / 1000)
    local guardState = guard:GetAttribute("GuardState")
    if guardState == "RetrievingEgg" then
        self:_beginEscape()
        return false
    elseif guardState == "Sleeping" then
        self.wakingStartedAt = nil
        self.phase = "bait"
        return true
    elseif guardState == "Waking" then
        self.wakingStartedAt = self.wakingStartedAt or self.clock()
        if
            self.clock() - self.wakingStartedAt
            >= math.max(0, self.wakingDuration - (ping * 2) / 1000)
        then
            self:_beginEscape()
            return false
        end
        self.phase = "bait"
        return true
    elseif guardState == "Chasing" then
        self.wakingStartedAt = nil
        if self.phase == "escape" then
            return false
        end
        local interval = self.hitIntervals[areaId]
        local elapsed = self.carryStartedAt and self.clock() - self.carryStartedAt
        if interval and elapsed then
            local lead = math.min(ping / 1000, self.reclaimDistance / math.max(playerSpeed, 1))
            if
                elapsed >= math.max(0, interval - lead)
                and elapsed <= interval + math.max(0.1, lead * 0.5)
            then
                self:_beginEscape()
                return false
            end
            self.phase = "bait"
            return true
        elseif distance <= releaseDistance then
            self:_beginEscape()
            return false
        end
        self.phase = "bait"
        return true
    end
    if self.phase == "escape" then
        return false
    end
    if distance <= releaseDistance then
        self:_beginEscape()
        return false
    end
    return true
end

function LagSafeMovement:setPingThreshold(value)
    self.pingThreshold = math.max(1, tonumber(value) or 170)
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
                self.carryUid = record.Uid
                self.carryStartedAt = self.clock()
                break
            end
        end
        self.carryConnection = self.eggCmds.AreaEggCarryStateChanged:Connect(function(state)
            if state.IsCarrying == true then
                if self.carryUid and state.Uid and state.Uid ~= self.carryUid then
                    self:_resetEncounter()
                end
                self.carryUid = state.Uid or self.carryUid
                self.carrying = true
                self.carryStartedAt = self.clock()
            else
                local guard = self.phaseArea and self.guardModels[self.phaseArea]
                if
                    self.carryStartedAt
                    and guard
                    and guard:GetAttribute("GuardState") == "RetrievingEgg"
                then
                    local interval = self.clock() - self.carryStartedAt
                    if interval > 0 and interval < 5 then
                        self.hitIntervals[self.phaseArea] = interval
                    end
                end
                self.carrying = false
                self.carryStartedAt = nil
                if self.phaseArea then
                    self.phase = "bait"
                end
            end
        end)
        self.connection = self.runService.Heartbeat:Connect(function()
            local humanoid = self:_humanoid()
            if not humanoid then
                return
            end
            local areaId = self.localPlayer:GetAttribute("AreaId")
            local config = self.guardConfigs[areaId]
            if not self:_shouldBait(humanoid, areaId, config) then
                self:_restore()
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
        if self.connection then
            self.connection:Disconnect()
            self.connection = nil
        end
        self.carrying = false
        self.carryStartedAt = nil
        self.carryUid = nil
        self:_resetEncounter()
        self:_restore()
    end
end

function LagSafeMovement:stop()
    self:setEnabled(false)
end

return LagSafeMovement
