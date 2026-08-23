local HitAura = {}
HitAura.__index = HitAura

local COOLDOWN = 0.6
local RANGE = 17

function HitAura.new(options)
    assert(options and options.eggCmds and options.localPlayer and options.network)
    assert(options.players and options.runService and options.workspace and options.endpoint)
    return setmetatable({
        eggCmds = options.eggCmds,
        endpoint = options.endpoint,
        localPlayer = options.localPlayer,
        network = options.network,
        players = options.players,
        runService = options.runService,
        workspace = options.workspace,
        enabled = false,
        friendCache = {},
        ignoreFriends = true,
        lastHitAt = -math.huge,
        sequence = 0,
    }, HitAura)
end

function HitAura:_equippedBat()
    local character = self.localPlayer.Character
    if not character then
        return nil
    end
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Tool") and child:GetAttribute("IsBat") == true then
            return child
        end
    end
    return nil
end

function HitAura:_isFriend(player)
    local cached = self.friendCache[player.UserId]
    if cached == nil then
        local succeeded, result =
            pcall(self.localPlayer.IsFriendsWith, self.localPlayer, player.UserId)
        cached = not succeeded or result == true
        self.friendCache[player.UserId] = cached
    end
    return cached
end

function HitAura:_target()
    local carriers = {}
    for _, record in ipairs(self.eggCmds.GetAreaEggSnapshot().Records) do
        if record.State == "Carried" and record.CarrierUserId then
            carriers[record.CarrierUserId] = true
        end
    end
    local character = self.localPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        return nil
    end
    local closest
    local closestDistance = RANGE
    for _, player in ipairs(self.players:GetPlayers()) do
        if player ~= self.localPlayer and carriers[player.UserId] then
            local targetCharacter = player.Character
            local targetRoot = targetCharacter
                and targetCharacter:FindFirstChild("HumanoidRootPart")
            local humanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
            local distance = targetRoot and (targetRoot.Position - root.Position).Magnitude
                or math.huge
            if humanoid and humanoid.Health > 0 and distance <= closestDistance then
                if not self.ignoreFriends or not self:_isFriend(player) then
                    closest = player
                    closestDistance = distance
                end
            end
        end
    end
    return closest
end

function HitAura:_step()
    if not self.enabled or not self:_equippedBat() then
        return
    end
    local now = self.workspace:GetServerTimeNow()
    if now - self.lastHitAt < COOLDOWN then
        return
    end
    local target = self:_target()
    if not target then
        return
    end
    self.lastHitAt = now
    self.sequence += 1
    local traceId = ("%s:%s:%s"):format(
        self.localPlayer.UserId,
        self.sequence,
        math.floor(now * 1000)
    )
    self.network.Fire(self.endpoint, target, traceId)
end

function HitAura:setIgnoreFriends(enabled)
    self.ignoreFriends = enabled == true
end

function HitAura:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then
        return
    end
    self.enabled = enabled
    if enabled then
        self.connection = self.runService.Heartbeat:Connect(function()
            self:_step()
        end)
        return
    end
    if self.connection then
        self.connection:Disconnect()
        self.connection = nil
    end
end

function HitAura:stop()
    self:setEnabled(false)
end

return HitAura
