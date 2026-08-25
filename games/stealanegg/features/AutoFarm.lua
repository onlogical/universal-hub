local AutoFarm = {}
AutoFarm.__index = AutoFarm

local function rootPosition(localPlayer)
    local character = localPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return root and root:IsA("BasePart") and root.Position or nil
end

local function isCarried(record)
    return record.State == "Carried" or record.State == "Claimed"
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
        defer = options.defer or task.defer,
        getEscapePosition = options.getEscapePosition or function()
            return nil
        end,
        getIdlePosition = options.getIdlePosition or function()
            return nil
        end,
        getResetSeconds = options.getResetSeconds or function()
            return 0
        end,
        getSecuredEggs = options.getSecuredEggs or function()
            return {}
        end,
        hasMissingIndex = options.hasMissingIndex or function()
            return false
        end,
        isGlobalSpawnKnown = options.isGlobalSpawnKnown or function()
            return false
        end,
        isIndexed = options.isIndexed or function()
            return true
        end,
        isIndexPending = options.isIndexPending or function()
            return false
        end,
        isOnTreadmill = options.isOnTreadmill or function()
            return false
        end,
        leaveTreadmill = options.leaveTreadmill or function() end,
        markGlobalSpawn = options.markGlobalSpawn or function() end,
        onRareAvailable = options.onRareAvailable,
        onSecured = options.onSecured,
        shouldRunBlossom = options.shouldRunBlossom or function()
            return false
        end,
        plotCmds = options.plotCmds,
        players = options.players,
        publishStatus = options.publishStatus,
        serverHop = options.serverHop,
        serverHopping = true,
        slotIdentity = options.slotIdentity,
        spawn = options.spawn or task.spawn,
        wait = options.wait or task.wait,
        workspace = options.workspace or workspace,
        completeIndex = false,
        enabled = false,
        idleTreadmill = true,
        onTreadmill = false,
        paused = false,
        targetRarities = { Eternal = true, Secret = true },
        targetPopulation = 6,
        maxPing = 120,
        token = 0,
        claimed = false,
    }, AutoFarm)
    self.claimConnection = self.eggCmds.AreaEggClaimed:Connect(function(feedback)
        if feedback and feedback.AssetCategory == self.claimCategory then
            self.claimed = true
        end
    end)
    if self.eggCmds.AreaEggUpdated then
        self.eggUpdateConnection = self.eggCmds.AreaEggUpdated:Connect(function(record)
            if type(record) == "table" then
                local _, rarityName = self:_rarity(record)
                if self:_isRarityTarget(rarityName) then
                    self.markGlobalSpawn(rarityName)
                    if
                        type(self.onRareAvailable) == "function"
                        and (
                            record.State == "Slot"
                            or record.State == "Dropped"
                            or (
                                isCarried(record)
                                and record.CarrierUserId ~= self.localPlayer.UserId
                            )
                        )
                    then
                        pcall(self.onRareAvailable, record)
                    end
                end
            end
            if not self.enabled then
                self:_publish("Farm off", "Enable Auto Farm to pursue a target.")
            elseif self.waitingForEggUpdate == self.token then
                self.waitingForEggUpdate = nil
                self:_startRun()
            end
        end)
    end
    return self
end

function AutoFarm:_log(level, message, fields)
    local write = self.logger and self.logger[level]
    if type(write) == "function" then
        write(self.logger, "stealanegg.autoFarm", message, fields)
    end
end

function AutoFarm:_publish(stage, detail, targetUid)
    if type(self.publishStatus) ~= "function" then
        return
    end
    local eggs = {}
    local targets = 0
    local snapshot = self.eggCmds.GetAreaEggSnapshot()
    for _, record in ipairs(snapshot.Records) do
        local rarityNumber, rarityName = self:_rarity(record)
        local asset = self.assets.Directory[record.AssetCategory]
        local available = record.State == "Slot"
            or record.State == "Dropped"
            or (isCarried(record) and record.CarrierUserId ~= self.localPlayer.UserId)
        local indexTarget = self:_isIndexTarget(record)
        if available and (self:_isRarityTarget(rarityName) or indexTarget) then
            targets += 1
        end
        table.insert(eggs, {
            uid = record.Uid,
            name = asset and asset.DisplayName or record.AssetCategory,
            icon = asset and asset.Icon or "",
            rarity = rarityName,
            rarityColor = asset and asset.Rarity and asset.Rarity.Color
                or Color3.fromRGB(177, 188, 199),
            rarityNumber = rarityNumber,
            area = record.AreaId or "Unknown",
            size = tonumber(record.AssetScale) or 1,
            state = record.State == "Claimed" and "Contested" or record.State,
            target = record.Uid == targetUid,
            eligible = available and (self:_isRarityTarget(rarityName) or indexTarget),
            reason = indexTarget and "Missing from Index" or rarityName .. " target",
        })
    end
    table.sort(eggs, function(left, right)
        if left.target ~= right.target then
            return left.target == true
        end
        if left.rarityNumber ~= right.rarityNumber then
            return left.rarityNumber > right.rarityNumber
        end
        return left.name < right.name
    end)
    for _, egg in ipairs(eggs) do
        egg.rarityNumber = nil
    end
    self.publishStatus({
        visible = self.enabled,
        stage = stage,
        detail = detail,
        targets = targets,
        eggs = eggs,
        securedEggs = self.getSecuredEggs(),
    })
end

function AutoFarm:_active(token)
    return self.enabled and not self.paused and token == self.token
end

function AutoFarm:_rarity(record)
    local asset = self.assets.Directory[record.AssetCategory]
    local rarity = asset and asset.Rarity
    return rarity and rarity.RarityNumber or 0,
        rarity and (rarity.DisplayName or rarity._id) or "Unknown"
end

function AutoFarm:_isRarityTarget(rarityName)
    return self.targetRarities[rarityName] == true
        or (rarityName == "Divine" and (self.targetRarities.Eternal or self.targetRarities.Secret))
end

function AutoFarm:_isIndexTarget(record)
    return self.completeIndex
        and not self.isIndexed(record.AssetCategory)
        and not self.isIndexPending(record.AssetCategory)
end

function AutoFarm:_carrierRoot(record)
    if not self.players or type(self.players.GetPlayerByUserId) ~= "function" then
        return nil
    end
    local player = self.players:GetPlayerByUserId(record.CarrierUserId)
    local character = player and player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return root and root:IsA("BasePart") and root or nil
end

function AutoFarm:_selectTarget(mode)
    local position = rootPosition(self.localPlayer)
    local best
    for _, record in ipairs(self.eggCmds.GetAreaEggSnapshot().Records) do
        if
            record.State == "Slot"
            or record.State == "Dropped"
            or (isCarried(record) and record.CarrierUserId ~= self.localPlayer.UserId)
        then
            local rarityNumber, rarityName = self:_rarity(record)
            local indexTarget = mode ~= "rare" and self:_isIndexTarget(record)
            local rareTarget = mode ~= "index" and self:_isRarityTarget(rarityName)
            if rareTarget or indexTarget then
                if rareTarget then
                    self.markGlobalSpawn(rarityName)
                end
                local carrierRoot = isCarried(record) and self:_carrierRoot(record) or nil
                local bottomCFrame = record.BottomCFrame
                local targetPosition = carrierRoot and carrierRoot.Position
                    or (typeof(bottomCFrame) == "CFrame" and bottomCFrame.Position or nil)
                local distance = position
                        and targetPosition
                        and (position - targetPosition).Magnitude
                    or math.huge
                if
                    targetPosition
                    and (
                        not best
                        or (rareTarget and not best.rareTarget)
                        or (
                            rareTarget == best.rareTarget
                            and (
                                (indexTarget and not best.indexTarget)
                                or (
                                    indexTarget == best.indexTarget
                                    and (
                                        rarityNumber > best.rarityNumber
                                        or (rarityNumber == best.rarityNumber and distance < best.distance)
                                        or (
                                            rarityNumber == best.rarityNumber
                                            and distance == best.distance
                                            and record.Uid < best.record.Uid
                                        )
                                    )
                                )
                            )
                        )
                    )
                then
                    best = {
                        distance = distance,
                        indexTarget = indexTarget,
                        rareTarget = rareTarget,
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
        if isCarried(record) and record.CarrierUserId == self.localPlayer.UserId then
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

function AutoFarm:hasPriorityTarget()
    return self:_selectCarried() ~= nil or self:_selectTarget("rare") ~= nil
end

function AutoFarm:_pursueCarrier(record, token)
    local deadline = self.workspace:GetServerTimeNow() + 30
    while self:_active(token) and self.workspace:GetServerTimeNow() <= deadline do
        local current = self.eggCmds.GetAreaEggRecord(record.Uid)
        if not current then
            return nil, "egg-removed"
        end
        if current.CarrierUserId == self.localPlayer.UserId or not isCarried(current) then
            return current
        end
        local carrierRoot = self:_carrierRoot(current)
        if not carrierRoot then
            return nil, "carrier-unavailable"
        end
        self:_publish(
            "Contesting carrier",
            "Staying close so Hit Aura can force a drop, then taking the egg.",
            current.Uid
        )
        self.navigator:walkTo(carrierRoot.Position, function()
            local latest = self.eggCmds.GetAreaEggRecord(record.Uid)
            return self:_active(token)
                and latest ~= nil
                and isCarried(latest)
                and latest.CarrierUserId ~= self.localPlayer.UserId
        end, 12)
        self.wait(0.1)
    end
    return nil, self:_active(token) and "pursuit-timeout" or "cancelled"
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
            local escapePosition = self.getEscapePosition(current)
            if typeof(escapePosition) == "Vector3" then
                self.defer(function()
                    if self:_active(token) then
                        self.navigator:headToward(escapePosition)
                    end
                end)
            end
            local ok, carried, carryReason =
                pcall(self.eggCmds.RequestCarryAreaEgg, current.Uid, self:_slotKey(current))
            if ok and carried == true then
                return true
            end
            if ok and carryReason == "Get closer to the egg" then
                self.navigator:moveToDirect(current.BottomCFrame.Position, function()
                    local latest = self.eggCmds.GetAreaEggRecord(record.Uid)
                    return self:_active(token)
                        and latest ~= nil
                        and (latest.State == "Slot" or latest.State == "Dropped")
                end, 1)
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

function AutoFarm:_leaveTreadmill()
    if not self.onTreadmill and not self.isOnTreadmill() then
        return
    end
    self.onTreadmill = false
    pcall(self.leaveTreadmill)
    if type(self.navigator.jump) == "function" then
        self.navigator:jump()
        self.wait(0.1)
    end
end

function AutoFarm:_idleOnTreadmill(token)
    if not self.idleTreadmill or self.onTreadmill or self:_selectCarried() then
        return
    end
    local position = self.getIdlePosition()
    if typeof(position) ~= "Vector3" then
        return
    end
    self:_publish("Training while idle", "No farm action is ready. Walking onto your treadmill.")
    if type(self.navigator.jump) == "function" then
        self.navigator:jump()
    end
    local reached = self.navigator:moveToDirect(position, function()
        return self:_active(token) and self:_selectCarried() == nil
    end, 4)
    self.onTreadmill = reached == true
end

function AutoFarm:_waitForClaim(uid, token)
    local deadline = self.workspace:GetServerTimeNow() + 10
    while self:_active(token) and self.workspace:GetServerTimeNow() <= deadline do
        if self.eggCmds.GetAreaEggRecord(uid) == nil then
            return true
        end
        self.wait(0.1)
    end
    return false
end

function AutoFarm:_waitForReset(token)
    local remaining = math.max(0, tonumber(self.getResetSeconds()) or 0)
    if remaining > 0 then
        self:_idleOnTreadmill(token)
    end
    while self:_active(token) and remaining > 0 do
        self:_publish(
            "Reset in progress",
            ("Eggs are refreshing globally. Waiting %d seconds before scanning or hopping."):format(
                math.ceil(remaining)
            )
        )
        self.wait(math.min(1, remaining))
        remaining = math.max(0, tonumber(self.getResetSeconds()) or 0)
    end
    return self:_active(token)
end

function AutoFarm:_hop(token)
    if self:_selectCarried() or self:_selectTarget("rare") then
        self:_startRun()
        return
    end
    if self.shouldRunBlossom() then
        return
    end
    if self:_selectTarget("index") then
        self:_startRun()
        return
    end
    if (tonumber(self.getResetSeconds()) or 0) > 0 then
        self.spawn(function()
            self:_run(token)
        end)
        return
    end
    local indexTargetsRemain = self.completeIndex and self.hasMissingIndex()
    local rareSpawnKnown = (self.targetRarities.Eternal and self.isGlobalSpawnKnown("Eternal"))
        or (self.targetRarities.Secret and self.isGlobalSpawnKnown("Secret"))
    if not indexTargetsRemain and not rareSpawnKnown then
        self:_idleOnTreadmill(token)
        self.waitingForEggUpdate = token
        self:_publish(
            "Waiting for global spawn",
            "No selected global egg spawn has been observed yet. Staying in this server."
        )
        return
    end
    local mayHop = rareSpawnKnown and self.serverHopping
    if not mayHop then
        self:_idleOnTreadmill(token)
        self.waitingForEggUpdate = token
        self:_publish(
            "Waiting for targets",
            "No selected egg is available here. Waiting for the server egg state to change."
        )
        return
    end
    self.serverHop:run(self.maxPing, function(succeeded)
        if succeeded or not self:_active(token) then
            return
        end
        self:_publish(
            "Waiting to retry",
            "No eligible server answered yet. Trying again in 5 seconds."
        )
        self.spawn(function()
            self.wait(5)
            if self:_active(token) then
                self:_run(token)
            end
        end)
    end, function()
        return self:_active(token) and (tonumber(self.getResetSeconds()) or 0) <= 0
    end, self.targetPopulation)
end

function AutoFarm:_run(token)
    if not self:_active(token) or not self:_waitForReset(token) then
        return
    end
    pcall(self.eggCmds.RequestAreaEggSnapshot)
    self:_publish("Scanning server", "Checking every egg against your selected priorities.")
    local target = self:_selectCarried()
    local alreadyCarried = target ~= nil
    if not target then
        target = self:_selectTarget("rare")
    end
    if not target and self.shouldRunBlossom() then
        self:_publish(
            "Auto Blossom",
            "No Divine, Eternal, or Secret egg is ready. Farming Great Bloom before Index eggs."
        )
        return
    end
    if not target then
        target = self:_selectTarget("index")
    end
    if not target then
        self:_log("info", "no matching egg; hopping", {
            eternal = self.targetRarities.Eternal,
            secret = self.targetRarities.Secret,
        })
        self:_publish(
            "Finding another server",
            "No selected rarity spawned here. Requesting another server."
        )
        self:_hop(token)
        return
    end

    self:_leaveTreadmill()
    local record = target.record
    self.claimCategory = record.AssetCategory
    if not alreadyCarried and isCarried(record) then
        local pursued, pursuitReason = self:_pursueCarrier(record, token)
        if not pursued then
            self:_log("warn", "carrier pursuit ended", {
                reason = pursuitReason,
                uid = record.Uid,
            })
            if self:_active(token) then
                self:_hop(token)
            end
            return
        end
        record = pursued
        alreadyCarried = record.CarrierUserId == self.localPlayer.UserId
    end
    if not alreadyCarried then
        self:_log("info", "target selected", {
            area = record.AreaId,
            category = record.AssetCategory,
            rarity = target.rarityName,
            uid = record.Uid,
        })
        self:_publish(
            "Walking to target",
            ("%s %s · %s"):format(target.rarityName, record.AssetCategory, record.AreaId),
            record.Uid
        )
        local function targetAvailable()
            local latest = self.eggCmds.GetAreaEggRecord(record.Uid)
            return self:_active(token)
                and latest ~= nil
                and (latest.State == "Slot" or latest.State == "Dropped")
        end
        local reached, reason =
            self.navigator:walkTo(record.BottomCFrame.Position, targetAvailable, 2)
        if not reached and reason == "timeout" and targetAvailable() then
            reached, reason =
                self.navigator:moveToDirect(record.BottomCFrame.Position, targetAvailable, 2)
        end
        if not reached then
            local latest = self.eggCmds.GetAreaEggRecord(record.Uid)
            if
                self:_active(token)
                and (latest == nil or (latest.State ~= "Slot" and latest.State ~= "Dropped"))
            then
                self:_startRun()
                return
            end
            self:_log("warn", "target walk failed", { reason = reason, uid = record.Uid })
            self:_publish(
                "Rebuilding route",
                "The target path was blocked. Retrying inside this server.",
                record.Uid
            )
            self.wait(1)
            if self:_active(token) then
                self:_startRun()
            end
            return
        end

        self:_publish(
            "Claiming egg",
            "In pickup range. Waiting for the server to confirm carry.",
            record.Uid
        )
        local carried, carryReason = self:_claim(record, token)
        if not carried then
            self:_log("warn", "claim failed", { reason = carryReason, uid = record.Uid })
            if self:_active(token) then
                self:_hop(token)
            end
            return
        end
    end

    self:_publish(
        "Returning with egg",
        "Walking to the safe boundary and avoiding the treadmill.",
        record.Uid
    )
    local secured = false
    local escaped = false
    while self:_active(token) and not secured do
        local crossedEscape = false
        local escape = not escaped and self.getEscapePosition(record) or nil
        local home = escape or self:_homePosition()
        if home then
            self.claimed = false
            local returned, returnReason = self.navigator:stepTo(home, function()
                local latest = self.eggCmds.GetAreaEggRecord(record.Uid)
                return self:_active(token)
                    and not self.claimed
                    and latest ~= nil
                    and latest.State == "Carried"
                    and latest.CarrierUserId == self.localPlayer.UserId
            end, 8)
            if returned and escape then
                escaped = true
                crossedEscape = true
            elseif returned or self.claimed then
                secured = self:_waitForClaim(record.Uid, token)
            else
                local latest = self.eggCmds.GetAreaEggRecord(record.Uid)
                if not latest then
                    secured = true
                elseif latest.State == "Slot" or latest.State == "Dropped" then
                    self:_publish(
                        "Recovering egg",
                        "The boss interrupted the return. Reclaiming the same egg immediately.",
                        record.Uid
                    )
                    self:_startRun()
                    return
                elseif
                    latest.State ~= "Carried"
                    or latest.CarrierUserId ~= self.localPlayer.UserId
                then
                    self.waitingForEggUpdate = token
                    self:_publish(
                        "Tracking boss",
                        "Waiting for the same egg to leave the boss, then reclaiming it.",
                        record.Uid
                    )
                    return
                else
                    self:_log("warn", "return walk failed", {
                        reason = returnReason,
                        uid = record.Uid,
                    })
                    self:_publish(
                        "Retrying return",
                        "The route stalled. Rebuilding the safe path without dropping the egg.",
                        record.Uid
                    )
                end
            end
        else
            self:_log("warn", "home unavailable; retrying", { uid = record.Uid })
            self:_publish(
                "Waiting for base",
                "Base data is still loading. The carried egg stays prioritized.",
                record.Uid
            )
        end
        if not secured and not crossedEscape then
            self.wait(2)
        end
    end
    if not secured then
        return
    end

    self:_log("info", "egg secured; rescanning", { uid = record.Uid })
    if type(self.onSecured) == "function" then
        pcall(self.onSecured, record)
    end
    self:_publish("Egg secured", "Deposit confirmed. Checking this server for another target.")
    self.wait(1)
    if self:_active(token) then
        self:_startRun()
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

function AutoFarm:setPaused(paused)
    paused = paused == true
    if self.paused == paused then
        return
    end
    self.paused = paused
    self.token += 1
    self.waitingForEggUpdate = nil
    if paused then
        self:_leaveTreadmill()
        self:_publish(
            "Auto Blossom",
            "Rare eggs are clear. Great Bloom has priority before Index farming."
        )
    elseif self.enabled then
        self:_startRun()
    end
end

function AutoFarm:setCompleteIndex(enabled)
    enabled = enabled == true
    if self.completeIndex == enabled then
        return
    end
    self.completeIndex = enabled
    if self.enabled then
        self.token += 1
        self:_startRun()
    end
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

function AutoFarm:setTargetPopulation(value)
    self.targetPopulation = math.max(0, tonumber(value) or 6)
end

function AutoFarm:setIdleTreadmill(enabled)
    enabled = enabled == true
    if self.idleTreadmill == enabled then
        return
    end
    self.idleTreadmill = enabled
    if not enabled then
        self:_leaveTreadmill()
    end
    if self.enabled then
        self.token += 1
        self.waitingForEggUpdate = nil
        self:_startRun()
    end
end

function AutoFarm:setServerHopping(enabled)
    enabled = enabled == true
    if self.serverHopping == enabled then
        return
    end
    self.serverHopping = enabled
    if self.enabled then
        self.token += 1
        self.waitingForEggUpdate = nil
        self:_startRun()
    end
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
    if not enabled then
        self.paused = false
    end
    self.token += 1
    self.waitingForEggUpdate = nil
    if not enabled then
        self:_leaveTreadmill()
    end
    self:_log("info", enabled and "enabled" or "disabled")
    if enabled then
        self:_publish("Starting", "Reading the current server and preparing the farm.")
        self:_startRun()
    elseif type(self.publishStatus) == "function" then
        self.publishStatus(false)
    end
end

function AutoFarm:stop()
    self.enabled = false
    self.paused = false
    self.token += 1
    self:_leaveTreadmill()
    if type(self.publishStatus) == "function" then
        self.publishStatus(false)
    end
    if self.claimConnection then
        pcall(self.claimConnection.Disconnect, self.claimConnection)
        self.claimConnection = nil
    end
    if self.eggUpdateConnection then
        pcall(self.eggUpdateConnection.Disconnect, self.eggUpdateConnection)
        self.eggUpdateConnection = nil
    end
end

return AutoFarm
