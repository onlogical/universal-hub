local AutoBlossom = {}
AutoBlossom.__index = AutoBlossom

function AutoBlossom.new(options)
    assert(options and options.collectionService and options.localPlayer and options.navigator)
    local self = setmetatable({
        batAttribute = options.batAttribute or "IsBat",
        canFarm = options.canFarm or function()
            return true
        end,
        collectionService = options.collectionService,
        hitCooldown = tonumber(options.hitCooldown) or 0.6,
        hitRange = tonumber(options.hitRange) or 10,
        localPlayer = options.localPlayer,
        navigator = options.navigator,
        onWorkChanged = options.onWorkChanged,
        spawn = options.spawn or task.spawn,
        treeTag = options.treeTag or "SakuraBloomTree",
        wait = options.wait or task.wait,
        enabled = false,
        running = false,
        working = false,
        token = 0,
    }, AutoBlossom)
    if type(self.collectionService.GetInstanceAddedSignal) == "function" then
        self.treeAddedConnection = self.collectionService
            :GetInstanceAddedSignal(self.treeTag)
            :Connect(function()
                if self.enabled then
                    self:_startRun()
                end
            end)
    end
    return self
end

function AutoBlossom:_active(token)
    return self.enabled and self.token == token
end

function AutoBlossom:_root()
    local character = self.localPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart") or nil
end

function AutoBlossom:_nearestTree()
    local root = self:_root()
    if not root then
        return nil
    end
    local nearest
    local nearestDistance = math.huge
    for _, tree in ipairs(self.collectionService:GetTagged(self.treeTag)) do
        if tree.Parent and tree:IsA("Model") and tree.Name ~= "SakuraTreeFalling" then
            local distance = (root.Position - tree:GetPivot().Position).Magnitude
            if distance < nearestDistance then
                nearest = tree
                nearestDistance = distance
            end
        end
    end
    return nearest
end

function AutoBlossom:hasWork()
    return self.canFarm() and self:_nearestTree() ~= nil
end

function AutoBlossom:_setWorking(working)
    working = working == true
    if self.working == working then
        return
    end
    self.working = working
    if type(self.onWorkChanged) == "function" then
        self.onWorkChanged(working)
    end
end

function AutoBlossom:_equipBat()
    local character = self.localPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return false
    end
    local equipped = character:FindFirstChildOfClass("Tool")
    if equipped and equipped:GetAttribute(self.batAttribute) == true then
        return true
    end
    local backpack = self.localPlayer:FindFirstChildOfClass("Backpack")
    for _, tool in ipairs(backpack and backpack:GetChildren() or {}) do
        if tool:GetAttribute(self.batAttribute) == true then
            humanoid:EquipTool(tool)
            return true
        end
    end
    return false
end

function AutoBlossom:_run(token)
    while self:_active(token) do
        if not self.canFarm() then
            self:_setWorking(false)
            return
        end
        local tree = self:_nearestTree()
        if not tree then
            self:_setWorking(false)
            return
        end
        self:_setWorking(true)
        if not self:_active(token) then
            return
        end
        self:_equipBat()
        local radius = tonumber(tree:GetAttribute("Radius")) or 0
        self.navigator:walkTo(tree:GetPivot().Position, function()
            return self:_active(token) and tree.Parent ~= nil
        end, math.max(1, radius + self.hitRange - 1))
        if self:_active(token) then
            self.wait(self.hitCooldown)
        end
    end
    self:_setWorking(false)
end

function AutoBlossom:_startRun()
    if self.running or not self.enabled then
        return
    end
    self.running = true
    local token = self.token
    self.spawn(function()
        local ok = pcall(self._run, self, token)
        self.running = false
        if not ok then
            self:_setWorking(false)
        end
    end)
end

function AutoBlossom:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then
        if enabled then
            self:_startRun()
        end
        return
    end
    self.enabled = enabled
    self.token += 1
    if enabled then
        self:_startRun()
    else
        self:_setWorking(false)
    end
end

function AutoBlossom:stop()
    self:setEnabled(false)
    if self.treeAddedConnection then
        pcall(self.treeAddedConnection.Disconnect, self.treeAddedConnection)
        self.treeAddedConnection = nil
    end
end

return AutoBlossom
