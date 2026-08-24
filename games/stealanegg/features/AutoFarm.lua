local AutoFarm = {}
AutoFarm.__index = AutoFarm

local function rootPosition(localPlayer)
    local character = localPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return root and root:IsA("BasePart") and root.Position or nil
end

function AutoFarm.new(options)
    assert(options and options.assets and options.eggCmds and options.localPlayer)
    assert(options.navigator and options.plotCmds and options.serverHop and options.slotIdentity)
    local self = setmetatable({
        assets = options.assets,
        eggCmds = options.eggCmds,
        localPlayer = options.localPlayer,
        logger = options.logger,
        navigator = options.navigator,
        plotCmds = options.plotCmds,
        players = options.players,
        serverHop = options.serverHop,
        slotIdentity = options.slotIdentity,
        spawn = options.spawn or task.spawn,
        wait = options.wait or task.wait,
        workspace = options.workspace or workspace,
        enabled = false,
        targetRarities = { Eternal = true, Secret = true },
        highPopulation = false,
        maxPing = 120,
        token = 0,
        claimed = false,
    }, AutoFarm)
    self.claimConnection = self.eggCmds.AreaEggClaimed:Connect(function(feedback)
        if feedback and feedback.AssetCategory == self.claimCategory then
            self.claimed = true
        end
    end)
    return self
end

function AutoFarm:_log(level, message, fields)
    local write = self.logger and self.logger[level]
    if type(write) == "function" then
        write(self.logger, "stealanegg.autoFarm", message, fields)
    end
end

function AutoFarm:_active(token)
    return self.enabled and token == self.token
end

function AutoFarm:_rarity(record)
    local asset = self.assets.Directory[record.AssetCategory]
    local rarity = asset and asset.Rarity
    return rarity and rarity.RarityNumber or 0,
        rarity and (rarity.DisplayName or rarity._id) or "Unknown"
end

function AutoFarm:_selectTarget()
    local position = rootPosition(self.localPlayer)
    local best
    for _, record in ipairs(self.eggCmds.GetAreaEggSnapshot().Records) do
        if record.State == "Slot" or record.State == "Dropped" then
            local rarityNumber, rarityName = self:_rarity(record)
            if self.targetRarities[rarityName] == true then
                local distance = position and (position - record.BottomCFrame.Position).Magnitude
                    or math.huge
                if
                    not best
                    or rarityNumber > best.rarityNumber
                    or (rarityNumber == best.rarityNumber and distance < best.distance)
                    or (
                        rarityNumber == best.rarityNumber
                        and distance == best.distance
                        and record.Uid < best.record.Uid
                    )
                then
                    best = {
                        distance = distance,
                        rarityName = rarityName,
                        rarityNumber = rarityNumber,
                        record = record,
                    }
                end
            end
        end
    end
    return best
end

function AutoFarm:_selectCarried()
    for _, record in ipairs(self.eggCmds.GetAreaEggSnapshot().Records) do
        if record.State == "Carried" and record.CarrierUserId == self.localPlayer.UserId then
            local rarityNumber, rarityName = self:_rarity(record)
            return {
                distance = 0,
                rarityName = rarityName,
                rarityNumber = rarityNumber,
                record = record,
            }
        end
    end
    return nil
end

function AutoFarm:_activeCompetitor(record)
    if not self.players or type(self.players.GetPlayers) ~= "function" then
        return nil
    end
    local localPosition = rootPosition(self.localPlayer)
    local localCharacter = self.localPlayer.Character
    local localHumanoid = localCharacter and localCharacter:FindFirstChildOfClass("Humanoid")
    local localSpeed = math.max(localHumanoid and localHumanoid.WalkSpeed or 16, 1)
    local targetPosition = record.BottomCFrame.Position
    local localEta = localPosition and (localPosition - targetPosition).Magnitude / localSpeed
        or math.huge
    for _, player in ipairs(self.players:GetPlayers()) do
        if player ~= self.localPlayer then
            local character = player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if root and root:IsA("BasePart") and humanoid then
                local moving = humanoid.MoveDirection.Magnitude > 0.05
                    or root.AssemblyLinearVelocity.Magnitude > 2
                local eta = (root.Position - targetPosition).Magnitude
                    / math.max(humanoid.WalkSpeed, 1)
                if moving and eta < localEta then
                    return player
                end
            end
        end
    end
    return nil
end

function AutoFarm:_slotKey(record)
    if self.slotIdentity.IsFirstAreaUid(record.Uid) then
        return self.slotIdentity.BuildSlotKey(record.AreaId, record.NestId)
    end
    return nil
end

function AutoFarm:_claim(record, token)
    local deadline = self.workspace:GetServerTimeNow() + 5
    repeat
        local current = self.eggCmds.GetAreaEggRecord(record.Uid)
        if not current then
            return false, "egg-removed"
        end
        if current.State == "Carried" and current.CarrierUserId == self.localPlayer.UserId then
            return true
        end
        if current.State == "Slot" or current.State == "Dropped" then
            local position = rootPosition(self.localPlayer)
            if not position or (position - current.BottomCFrame.Position).Magnitude > 10 then
                return false, "egg-moved"
            end
            local ok, carried =
                pcall(self.eggCmds.RequestCarryAreaEgg, current.Uid, self:_slotKey(current))
            if ok and carried == true then
                return true
            end
        end
        self.wait(0.25)
    until not self:_active(token) or self.workspace:GetServerTimeNow() > deadline
    return false, self:_active(token) and "claim-timeout" or "cancelled"
end

function AutoFarm:_homePosition()
    local respawn = self.plotCmds.GetRespawnPointCFrame()
    if typeof(respawn) ~= "CFrame" then
        local plot = self.plotCmds.GetPlotData()
        respawn = plot and plot.RespawnPointCFrame or nil
    end
    local objects = type(self.workspace.FindFirstChild) == "function"
            and self.workspace:FindFirstChild("__OBJECTS")
        or nil
    local areas = objects and objects:FindFirstChild("Areas")
    local line = areas and areas:FindFirstChild("SeparationLine")
    if typeof(respawn) == "CFrame" and line and line:IsA("BasePart") then
        local offset = Vector3.new(
            respawn.Position.X - line.Position.X,
            0,
            respawn.Position.Z - line.Position.Z
        )
        if offset.Magnitude > 0 then
            return Vector3.new(line.Position.X, respawn.Position.Y, line.Position.Z)
                + offset.Unit * 18
        end
    end
    return typeof(respawn) == "CFrame" and respawn.Position or nil
end

function AutoFarm:_waitForClaim(uid, token)
    local deadline = self.workspace:GetServerTimeNow() + 10
    while self:_active(token) and self.workspace:GetServerTimeNow() <= deadline do
        if self.claimed or self.eggCmds.GetAreaEggRecord(uid) == nil then
            return true
        end
        self.wait(0.1)
    end
    return false
end

function AutoFarm:_hop(token)
    self.serverHop:run(self.maxPing, function(succeeded)
        if succeeded or not self:_active(token) then
            return
        end
        self.spawn(function()
            self.wait(5)
            if self:_active(token) then
                self:_run(token)
            end
        end)
    end, function()
        return self:_active(token)
    end, self.highPopulation and "high" or "low")
end

function AutoFarm:_run(token)
    self.wait(1.5)
    if not self:_active(token) then
        return
    end
    pcall(self.eggCmds.RequestAreaEggSnapshot)
    local target = self:_selectCarried()
    local alreadyCarried = target ~= nil
    if not target then
        if not self.targetRarities.Eternal and not self.targetRarities.Secret then
            self:_log("warn", "no target rarities selected")
            return
        end
        target = self:_selectTarget()
    end
    if not target then
        self:_log("info", "no matching egg; hopping", {
            eternal = self.targetRarities.Eternal,
            secret = self.targetRarities.Secret,
        })
        self:_hop(token)
        return
    end

    local record = target.record
    self.claimCategory = record.AssetCategory
    if not alreadyCarried then
        local competitor = self:_activeCompetitor(record)
        if competitor then
            self:_log("info", "active competitor detected; hopping", {
                player = competitor.Name,
                userId = competitor.UserId,
            })
            self:_hop(token)
            return
        end
        self:_log("info", "target selected", {
            area = record.AreaId,
            category = record.AssetCategory,
            rarity = target.rarityName,
            uid = record.Uid,
        })
        local reached, reason = self.navigator:walkTo(record.BottomCFrame.Position, function()
            return self:_active(token)
        end, 7)
        if not reached then
            self:_log("warn", "target walk failed", { reason = reason, uid = record.Uid })
            if self:_active(token) then
                self:_hop(token)
            end
            return
        end

        local carried, carryReason = self:_claim(record, token)
        if not carried then
            self:_log("warn", "claim failed", { reason = carryReason, uid = record.Uid })
            if self:_active(token) then
                self:_hop(token)
            end
            return
        end
    end

    local secured = false
    while self:_active(token) and not secured do
        local home = self:_homePosition()
        if home then
            self.claimed = false
            local returned, returnReason = self.navigator:walkTo(home, function()
                return self:_active(token) and not self.claimed
            end, 8)
            if returned or self.claimed then
                secured = self:_waitForClaim(record.Uid, token)
            else
                self:_log("warn", "return walk failed", {
                    reason = returnReason,
                    uid = record.Uid,
                })
            end
        else
            self:_log("warn", "home unavailable; retrying", { uid = record.Uid })
        end
        if not secured then
            self.wait(2)
        end
    end
    if not secured then
        return
    end

    self:_log("info", "egg secured; hopping", { uid = record.Uid })
    self.wait(1)
    if self:_active(token) then
        self:_hop(token)
    end
end

function AutoFarm:_startRun()
    local token = self.token
    self.spawn(function()
        local ok, err = pcall(self._run, self, token)
        if not ok then
            self:_log("error", "run failed", { error = err })
        end
    end)
end

function AutoFarm:setTargetRarities(eternal, secret)
    eternal = eternal == true
    secret = secret == true
    if self.targetRarities.Eternal == eternal and self.targetRarities.Secret == secret then
        return
    end
    self.targetRarities.Eternal = eternal
    self.targetRarities.Secret = secret
    if self.enabled then
        self.token += 1
        self:_startRun()
    end
end

function AutoFarm:setHighPopulation(enabled)
    self.highPopulation = enabled == true
end

function AutoFarm:setMaxPing(value)
    self.maxPing = math.max(1, tonumber(value) or 120)
end

function AutoFarm:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then
        return
    end
    self.enabled = enabled
    self.token += 1
    self:_log("info", enabled and "enabled" or "disabled")
    if enabled then
        self:_startRun()
    end
end

function AutoFarm:stop()
    self.enabled = false
    self.token += 1
    if self.claimConnection then
        pcall(self.claimConnection.Disconnect, self.claimConnection)
        self.claimConnection = nil
    end
end

return AutoFarm
