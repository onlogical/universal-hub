local GunGameRuntime = {}
GunGameRuntime.__index = GunGameRuntime

local SCAN_INTERVAL = 0.1
local RETRY_INTERVAL = 0.5

function GunGameRuntime.pickupType(instance)
    if not instance
        or instance.Name ~= "_drop"
        or type(instance.IsA) ~= "function"
        or not instance:IsA("BasePart")
        or type(instance.FindFirstChild) ~= "function"
    then
        return nil
    end
    if instance:FindFirstChild("Health") then
        return "Health"
    end
    if instance:FindFirstChild("AmmoBalanced") then
        return "AmmoBalanced"
    end
    return nil
end

function GunGameRuntime.shouldCollect(kind, fighter)
    if kind == "Health" then
        local entity = fighter and fighter.Entity
        local humanoid = entity and entity.Humanoid
        return humanoid ~= nil
            and type(humanoid.Health) == "number"
            and type(humanoid.MaxHealth) == "number"
            and humanoid.Health > 0
            and humanoid.Health < humanoid.MaxHealth
    end
    if kind ~= "AmmoBalanced" then
        return false
    end
    local item = fighter and fighter.EquippedItem
    local data = item and item.Data
    local info = item and item.Info
    if type(data) ~= "table" or type(info) ~= "table" then
        return item ~= nil
    end
    local knownCapacity = false
    if type(data.Ammo) == "number" and type(info.MaxAmmo) == "number" then
        knownCapacity = true
        if data.Ammo < info.MaxAmmo then
            return true
        end
    end
    if type(data.AmmoReserve) == "number" and type(info.MaxAmmoReserve) == "number" then
        knownCapacity = true
        if data.AmmoReserve < info.MaxAmmoReserve then
            return true
        end
    end
    return not knownCapacity
end

function GunGameRuntime.new(options)
    assert(options and options.store, "Gun Game runtime requires Store")
    assert(options.workspace, "Gun Game runtime requires Workspace")
    assert(options.getFighter, "Gun Game runtime requires a fighter getter")
    assert(options.isGunGame, "Gun Game runtime requires native mode state")

    local self = setmetatable({
        attemptedAt = setmetatable({}, { __mode = "k" }),
        candidates = {},
        clock = options.clock or os.clock,
        connections = {},
        fireTouchInterest = options.fireTouchInterest,
        getFighter = options.getFighter,
        isActive = options.isActive,
        isGunGame = options.isGunGame,
        isInCombat = options.isInCombat,
        nextScanAt = 0,
        spawn = options.spawn or task.spawn,
        stopped = false,
        store = options.store,
        wait = options.wait or task.wait,
        workspace = options.workspace,
    }, GunGameRuntime)

    local function addCandidate(candidate)
        if self.stopped then
            return
        end
        local kind = GunGameRuntime.pickupType(candidate)
        if kind then
            self.candidates[candidate] = kind
        end
    end
    local function removeCandidate(candidate)
        self.candidates[candidate] = nil
        self.attemptedAt[candidate] = nil
    end

    if type(options.workspace.GetChildren) == "function" then
        for _, candidate in ipairs(options.workspace:GetChildren()) do
            addCandidate(candidate)
        end
    end
    if options.workspace.ChildAdded and type(options.workspace.ChildAdded.Connect) == "function" then
        table.insert(self.connections, options.workspace.ChildAdded:Connect(addCandidate))
    end
    if options.workspace.ChildRemoved and type(options.workspace.ChildRemoved.Connect) == "function" then
        table.insert(self.connections, options.workspace.ChildRemoved:Connect(removeCandidate))
    end

    return self
end

function GunGameRuntime:update()
    if self.stopped then
        return
    end
    local settings = self.store:Get().settings
    if settings.autoPickup ~= true
        or not self.isGunGame()
        or type(self.fireTouchInterest) ~= "function"
        or self.isActive and not self.isActive()
        or self.isInCombat and not self.isInCombat()
    then
        return
    end
    local now = self.clock()
    if now < self.nextScanAt then
        return
    end
    self.nextScanAt = now + SCAN_INTERVAL
    local fighter = self.getFighter()
    local entity = fighter and fighter.Entity
    local touchPart = entity and entity.RootPart
    if not touchPart then
        return
    end
    for candidate, kind in pairs(self.candidates) do
        local lastAttemptAt = self.attemptedAt[candidate]
        if kind
            and candidate.Parent == self.workspace
            and GunGameRuntime.shouldCollect(kind, fighter)
            and (lastAttemptAt == nil or now - lastAttemptAt >= RETRY_INTERVAL)
        then
            self.attemptedAt[candidate] = now
            self.spawn(function()
                if self.stopped or candidate.Parent ~= self.workspace then
                    return
                end
                local touched = pcall(self.fireTouchInterest, touchPart, candidate, 1)
                if touched then
                    self.wait()
                    pcall(self.fireTouchInterest, touchPart, candidate, 0)
                end
            end)
        end
    end
end

function GunGameRuntime:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    for _, connection in ipairs(self.connections) do
        if connection and type(connection.Disconnect) == "function" then
            connection:Disconnect()
        end
    end
    table.clear(self.connections)
    table.clear(self.candidates)
    table.clear(self.attemptedAt)
end

return GunGameRuntime
