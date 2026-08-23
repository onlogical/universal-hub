local HighlightEsp = {}
HighlightEsp.__index = HighlightEsp

local function updateLabelMap(labels, cameraPosition)
    for _, entry in pairs(labels) do
        local adornee = entry.billboard.Adornee
        if adornee and adornee.Parent then
            local distance = (cameraPosition - adornee.Position).Magnitude
            local proximityBoost = math.clamp((80 - distance) / 20, 0, 4)
            entry.label.TextSize = math.clamp(entry.baseSize + proximityBoost, 16, 24)
        end
    end
end

function HighlightEsp.new(options)
    assert(
        options
            and options.assets
            and options.collectionService
            and options.eggCmds
            and options.runService
            and options.workspace
    )
    local self = setmetatable({
        assets = options.assets,
        collectionService = options.collectionService,
        eggCmds = options.eggCmds,
        runService = options.runService,
        workspace = options.workspace,
        createHighlight = options.createHighlight or function()
            return Instance.new("Highlight")
        end,
        createLabel = options.createLabel or function(target)
            local adornee = target:IsA("BasePart") and target
                or target.PrimaryPart
                or target:FindFirstChildWhichIsA("BasePart", true)
            if not adornee then
                return nil
            end
            local billboard = Instance.new("BillboardGui")
            billboard.Name = "UniversalHubEspLabel"
            billboard.Adornee = adornee
            billboard.AlwaysOnTop = true
            billboard.MaxDistance = 600
            billboard.Size = UDim2.fromOffset(180, 42)
            billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
            billboard.Parent = target
            local label = Instance.new("TextLabel")
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.GothamBold
            label.Size = UDim2.fromScale(1, 1)
            label.TextScaled = false
            label.TextSize = 14
            label.TextStrokeTransparency = 0.25
            label.TextWrapped = true
            label.Parent = billboard
            return billboard, label
        end,
        depthMode = options.depthMode or Enum.HighlightDepthMode.AlwaysOnTop,
        outlineColor = options.outlineColor or Color3.new(1, 1, 1),
        trapColor = options.trapColor or Color3.fromRGB(255, 70, 70),
        eggHighlights = {},
        eggLabels = {},
        trapHighlights = {},
        trapLabels = {},
        eggConnections = {},
        trapConnections = {},
        minimumRarity = 1,
        minimumSize = 0.5,
        labelElapsed = 0,
        eggsEnabled = false,
        trapsEnabled = false,
    }, HighlightEsp)
    self.heartbeatConnection = options.runService.Heartbeat:Connect(function(elapsed)
        self:_updateLabelSizes(elapsed)
    end)
    return self
end

function HighlightEsp:_updateLabelSizes(elapsed)
    self.labelElapsed += elapsed or 0
    if self.labelElapsed < 0.1 then
        return
    end
    self.labelElapsed = 0
    local camera = self.workspace.CurrentCamera
    if camera then
        local cameraPosition = camera.CFrame.Position
        updateLabelMap(self.eggLabels, cameraPosition)
        updateLabelMap(self.trapLabels, cameraPosition)
    end
end

function HighlightEsp:_destroy(map, key, labels)
    local highlight = map[key]
    map[key] = nil
    if highlight then
        pcall(highlight.Destroy, highlight)
    end
    local entry = labels and labels[key]
    if entry then
        labels[key] = nil
        pcall(entry.billboard.Destroy, entry.billboard)
    end
end

function HighlightEsp:_highlight(map, key, target, color, name)
    local highlight = map[key]
    if not highlight then
        highlight = self.createHighlight()
        highlight.Name = name
        highlight.DepthMode = self.depthMode
        highlight.FillTransparency = 0.55
        highlight.OutlineTransparency = 0
        highlight.OutlineColor = self.outlineColor
        highlight.Adornee = target
        highlight.Parent = target
        map[key] = highlight
    end
    highlight.FillColor = color
end

function HighlightEsp:_label(map, key, target, text, color, textSize)
    local entry = map[key]
    if not entry then
        local billboard, label = self.createLabel(target)
        if not billboard then
            return
        end
        entry = { billboard = billboard, label = label }
        map[key] = entry
    end
    entry.baseSize = textSize or 14
    entry.label.Text = text
    entry.label.TextColor3 = color
    entry.label.TextSize = math.max(entry.baseSize, 16)
end

function HighlightEsp:_refreshEgg(uid)
    if not self.eggsEnabled then
        self:_destroy(self.eggHighlights, uid, self.eggLabels)
        return
    end
    local model = self.workspace:FindFirstChild(uid, true)
    local record = self.eggCmds.GetAreaEggRecord(uid)
    local asset = record and self.assets.Directory[record.AssetCategory]
    local rarity = asset and asset.Rarity
    if
        not model
        or not rarity
        or (rarity.RarityNumber or 0) < self.minimumRarity
        or (record.AssetScale or 0) < self.minimumSize
    then
        self:_destroy(self.eggHighlights, uid, self.eggLabels)
        return
    end
    self:_highlight(self.eggHighlights, uid, model, rarity.Color, "UniversalHubEggHighlight")
    self:_label(
        self.eggLabels,
        uid,
        model,
        ("%s\n%s • %.1fx"):format(
            tostring(record.AssetCategory),
            tostring(rarity.DisplayName or rarity._id or "Egg"),
            record.AssetScale
        ),
        rarity.Color,
        math.clamp(12 + record.AssetScale * 3, 14, 22)
    )
end

function HighlightEsp:_refreshEggs()
    local present = {}
    for _, record in ipairs(self.eggCmds.GetAreaEggSnapshot().Records) do
        present[record.Uid] = true
        self:_refreshEgg(record.Uid)
    end
    for uid in pairs(self.eggHighlights) do
        if not present[uid] then
            self:_destroy(self.eggHighlights, uid, self.eggLabels)
        end
    end
end

function HighlightEsp:setEggsEnabled(enabled)
    enabled = enabled == true
    if self.eggsEnabled == enabled then
        return
    end
    self.eggsEnabled = enabled
    if enabled then
        table.insert(
            self.eggConnections,
            self.workspace.DescendantAdded:Connect(function(instance)
                if self.eggCmds.GetAreaEggRecord(instance.Name) then
                    self:_refreshEgg(instance.Name)
                end
            end)
        )
        table.insert(
            self.eggConnections,
            self.workspace.DescendantRemoving:Connect(function(instance)
                local highlight = self.eggHighlights[instance.Name]
                if highlight and highlight.Adornee == instance then
                    self:_destroy(self.eggHighlights, instance.Name, self.eggLabels)
                end
            end)
        )
        table.insert(
            self.eggConnections,
            self.eggCmds.AreaEggUpdated:Connect(function(record)
                self:_refreshEgg(record.Uid)
            end)
        )
        self:_refreshEggs()
        return
    end
    for _, connection in ipairs(self.eggConnections) do
        pcall(connection.Disconnect, connection)
    end
    table.clear(self.eggConnections)
    for uid in pairs(self.eggHighlights) do
        self:_destroy(self.eggHighlights, uid, self.eggLabels)
    end
end

function HighlightEsp:setMinimumRarity(value)
    value = math.clamp(tonumber(value) or 1, 1, 10)
    if self.minimumRarity ~= value then
        self.minimumRarity = value
        self:_refreshEggs()
    end
end

function HighlightEsp:setMinimumSize(value)
    value = math.clamp(tonumber(value) or 0.5, 0.5, 3)
    if self.minimumSize ~= value then
        self.minimumSize = value
        self:_refreshEggs()
    end
end

function HighlightEsp:_refreshTrap(trap)
    if self.trapsEnabled then
        self:_highlight(
            self.trapHighlights,
            trap,
            trap,
            self.trapColor,
            "UniversalHubTrapHighlight"
        )
        local owner = trap:GetAttribute("Owner")
        self:_label(
            self.trapLabels,
            trap,
            trap,
            owner and ("Trap\n%s"):format(tostring(owner)) or "Trap",
            self.trapColor
        )
    else
        self:_destroy(self.trapHighlights, trap, self.trapLabels)
    end
end

function HighlightEsp:setTrapsEnabled(enabled)
    enabled = enabled == true
    if self.trapsEnabled == enabled then
        return
    end
    self.trapsEnabled = enabled
    if enabled then
        for _, trap in ipairs(self.collectionService:GetTagged("PlacedTrap")) do
            self:_refreshTrap(trap)
        end
        table.insert(
            self.trapConnections,
            self.collectionService:GetInstanceAddedSignal("PlacedTrap"):Connect(function(trap)
                self:_refreshTrap(trap)
            end)
        )
        table.insert(
            self.trapConnections,
            self.collectionService:GetInstanceRemovedSignal("PlacedTrap"):Connect(function(trap)
                self:_destroy(self.trapHighlights, trap, self.trapLabels)
            end)
        )
        return
    end
    for _, connection in ipairs(self.trapConnections) do
        pcall(connection.Disconnect, connection)
    end
    table.clear(self.trapConnections)
    for trap in pairs(self.trapHighlights) do
        self:_destroy(self.trapHighlights, trap, self.trapLabels)
    end
end

function HighlightEsp:stop()
    self:setEggsEnabled(false)
    self:setTrapsEnabled(false)
    if self.heartbeatConnection then
        pcall(self.heartbeatConnection.Disconnect, self.heartbeatConnection)
        self.heartbeatConnection = nil
    end
end

return HighlightEsp
