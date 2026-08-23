local AntiTrap = {}
AntiTrap.__index = AntiTrap

function AntiTrap.new(options)
    assert(options and options.collectionService and options.localPlayer)
    return setmetatable({
        collectionService = options.collectionService,
        localPlayer = options.localPlayer,
        connections = {},
        touched = {},
        enabled = false,
    }, AntiTrap)
end

function AntiTrap:_neutralize(trap)
    local function neutralize(instance)
        if instance:IsA("BasePart") and self.touched[instance] == nil then
            self.touched[instance] = instance.CanTouch
            instance.CanTouch = false
        end
    end
    neutralize(trap)
    for _, instance in ipairs(trap:GetDescendants()) do
        neutralize(instance)
    end
end

function AntiTrap:_bindCharacter(character)
    if self.characterConnection then
        self.characterConnection:Disconnect()
    end
    local function clear()
        if self.enabled and character:GetAttribute("IsTrapped") == true then
            character:SetAttribute("IsTrapped", false)
        end
    end
    self.characterConnection = character:GetAttributeChangedSignal("IsTrapped"):Connect(clear)
    clear()
end

function AntiTrap:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then
        return
    end
    self.enabled = enabled
    if enabled then
        for _, trap in ipairs(self.collectionService:GetTagged("PlacedTrap")) do
            self:_neutralize(trap)
        end
        table.insert(
            self.connections,
            self.collectionService:GetInstanceAddedSignal("PlacedTrap"):Connect(function(trap)
                self:_neutralize(trap)
            end)
        )
        table.insert(
            self.connections,
            self.localPlayer.CharacterAdded:Connect(function(character)
                self:_bindCharacter(character)
            end)
        )
        if self.localPlayer.Character then
            self:_bindCharacter(self.localPlayer.Character)
        end
        return
    end

    for _, connection in ipairs(self.connections) do
        pcall(connection.Disconnect, connection)
    end
    table.clear(self.connections)
    if self.characterConnection then
        pcall(self.characterConnection.Disconnect, self.characterConnection)
        self.characterConnection = nil
    end
    for part, canTouch in pairs(self.touched) do
        if part.Parent then
            pcall(function()
                part.CanTouch = canTouch
            end)
        end
    end
    table.clear(self.touched)
end

function AntiTrap:stop()
    self:setEnabled(false)
end

return AntiTrap
