local AntiHit = {}
AntiHit.__index = AntiHit

local RECLAIM_SECONDS = 6
local KNOCKBACK_SUPPRESSION_SECONDS = 0.35

local function disconnectAll(connections)
    for _, connection in ipairs(connections) do
        pcall(connection.Disconnect, connection)
    end
    table.clear(connections)
end

function AntiHit.new(options)
    assert(options and options.localPlayer and options.workspace and options.runService)
    assert(options.ragdoll and options.eggCmds and options.slotIdentity)
    return setmetatable({
        localPlayer = options.localPlayer,
        logger = options.logger,
        workspace = options.workspace,
        runService = options.runService,
        ragdoll = options.ragdoll,
        eggCmds = options.eggCmds,
        slotIdentity = options.slotIdentity,
        spawn = options.spawn or task.spawn,
        wait = options.wait or task.wait,
        connections = {},
        characterConnections = {},
        enabled = false,
        claimToken = 0,
        suppressKnockbackUntil = -math.huge,
    }, AntiHit)
end

function AntiHit:_log(level, message, fields)
    local logger = self.logger
    local write = logger and logger[level]
    if type(write) == "function" then
        write(logger, "stealanegg.antiHit", message, fields)
    end
end

function AntiHit:_now()
    return self.workspace:GetServerTimeNow()
end

function AntiHit:_syncCarried()
    self.carriedUid = nil
    for _, record in ipairs(self.eggCmds.GetAreaEggSnapshot().Records) do
        if record.State == "Carried" and record.CarrierUserId == self.localPlayer.UserId then
            self.carriedUid = record.Uid
            return
        end
    end
end

function AntiHit:_slotKey(uid)
    if not self.slotIdentity.IsFirstAreaUid(uid) then
        return nil
    end
    local record = self.eggCmds.GetAreaEggRecord(uid)
    return record and self.slotIdentity.BuildSlotKey(record.AreaId, record.NestId) or nil
end

function AntiHit:_tryReclaim(uid)
    local record = self.eggCmds.GetAreaEggRecord(uid)
    if not record then
        return false, "missing-record"
    end
    if record.State ~= "Dropped" then
        return false, "state-" .. tostring(record.State)
    end
    local slotKey = self:_slotKey(uid)
    local succeeded, carried = pcall(self.eggCmds.RequestCarryAreaEgg, uid, slotKey)
    if not succeeded then
        return false, "request-error:" .. tostring(carried)
    end
    if carried ~= true then
        return false, "request-rejected"
    end
    self.carriedUid = uid
    self.reclaimUid = nil
    self.claimToken += 1
    return true
end

function AntiHit:_reclaim(uid)
    self.reclaimUid = uid
    self.claimToken += 1
    local token = self.claimToken
    local reclaimed, reason = self:_tryReclaim(uid)
    if reclaimed then
        self:_log("info", "reclaim immediate", { uid = uid })
        return
    end
    self:_log("info", "reclaim queued", { reason = reason, uid = uid })
    self.spawn(function()
        local deadline = self:_now() + RECLAIM_SECONDS
        local attempts = 0
        local lastReason = reason
        while self.enabled and token == self.claimToken and self:_now() <= deadline do
            attempts += 1
            reclaimed, lastReason = self:_tryReclaim(uid)
            if reclaimed then
                self:_log("info", "reclaim succeeded", { attempts = attempts, uid = uid })
                return
            end
            self.wait()
        end
        if token == self.claimToken then
            self.reclaimUid = nil
            self:_log("warn", "reclaim expired", {
                attempts = attempts,
                reason = lastReason,
                uid = uid,
            })
        end
    end)
end

function AntiHit:_onEggRecord(record)
    if self.enabled and self.reclaimUid and record and record.Uid == self.reclaimUid then
        if self:_tryReclaim(record.Uid) then
            self:_log("info", "reclaim succeeded", { source = "record-update", uid = record.Uid })
        end
    end
end

function AntiHit:_cancelVelocity()
    local character = self.localPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local movement = humanoid and humanoid.MoveDirection * humanoid.WalkSpeed or Vector3.zero
    root.AssemblyLinearVelocity = Vector3.new(movement.X, 0, movement.Z)
    root.AssemblyAngularVelocity = Vector3.zero
end

function AntiHit:_recover()
    local character = self.localPlayer.Character
    if not character then
        return
    end
    pcall(self.ragdoll.ClearClientRagdoll, character)
    self:_cancelVelocity()
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.PlatformStand = false
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
end

function AntiHit:_onHit()
    if not self.enabled then
        return
    end
    self.suppressKnockbackUntil = self:_now() + KNOCKBACK_SUPPRESSION_SECONDS
    self:_log("info", "hit detected", {
        carriedUid = self.carriedUid,
        ragdollEnd = self.localPlayer:GetAttribute("RagdollEndTime"),
    })
    self:_recover()
end

function AntiHit:_onCarryState(state)
    if state.IsCarrying then
        self:_log("info", "carry acquired", { uid = state.Uid })
        self.carriedUid = state.Uid
        self.intentionalDropUid = nil
        self.reclaimUid = nil
        self.claimToken += 1
        return
    end

    local uid = state.Uid or self.carriedUid or self.reclaimUid
    self:_log("info", "carry lost", {
        intentional = uid == self.intentionalDropUid,
        uid = uid,
    })
    self.carriedUid = nil
    if uid == self.intentionalDropUid then
        self.intentionalDropUid = nil
        self.reclaimUid = nil
        self.claimToken += 1
        return
    end
    if uid then
        self:_reclaim(uid)
    end
end

function AntiHit:_bindDropRequest()
    local original = self.eggCmds.RequestDropAreaEgg
    if type(original) ~= "function" then
        return
    end
    self.originalDropRequest = original
    self.dropRequest = function(...)
        local uid = self.carriedUid
        self.intentionalDropUid = uid
        self.reclaimUid = nil
        self.claimToken += 1
        local results = table.pack(original(...))
        if results[1] ~= true and self.intentionalDropUid == uid then
            self.intentionalDropUid = nil
        end
        return table.unpack(results, 1, results.n)
    end
    self.eggCmds.RequestDropAreaEgg = self.dropRequest
end

function AntiHit:_unbindDropRequest()
    if self.eggCmds.RequestDropAreaEgg == self.dropRequest then
        self.eggCmds.RequestDropAreaEgg = self.originalDropRequest
    end
    self.dropRequest = nil
    self.originalDropRequest = nil
end

function AntiHit:_bindCharacter(character)
    disconnectAll(self.characterConnections)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end
    table.insert(
        self.characterConnections,
        humanoid.StateChanged:Connect(function(_, state)
            if state == Enum.HumanoidStateType.Physics then
                self:_onHit()
            end
        end)
    )
end

function AntiHit:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then
        return
    end
    self.enabled = enabled
    self:_log("info", enabled and "enabled" or "disabled")

    if enabled then
        self:_syncCarried()
        self:_bindDropRequest()
        table.insert(
            self.connections,
            self.runService.PostSimulation:Connect(function()
                if self:_now() <= self.suppressKnockbackUntil then
                    self:_cancelVelocity()
                end
            end)
        )
        table.insert(
            self.connections,
            self.eggCmds.AreaEggCarryStateChanged:Connect(function(state)
                if self.enabled then
                    self:_onCarryState(state)
                end
            end)
        )
        table.insert(
            self.connections,
            self.eggCmds.AreaEggUpdated:Connect(function(record)
                self:_onEggRecord(record)
            end)
        )
        table.insert(
            self.connections,
            self.localPlayer:GetAttributeChangedSignal("RagdollEndTime"):Connect(function()
                if (self.localPlayer:GetAttribute("RagdollEndTime") or 0) > self:_now() then
                    self:_onHit()
                end
            end)
        )
        table.insert(
            self.connections,
            self.localPlayer.CharacterAdded:Connect(function(character)
                self:_bindCharacter(character)
            end)
        )
        self:_bindCharacter(self.localPlayer.Character)
        return
    end

    self.claimToken += 1
    self:_unbindDropRequest()
    disconnectAll(self.connections)
    disconnectAll(self.characterConnections)
    self.carriedUid = nil
    self.intentionalDropUid = nil
    self.reclaimUid = nil
    self.suppressKnockbackUntil = -math.huge
end

function AntiHit:stop()
    self:setEnabled(false)
end

return AntiHit
