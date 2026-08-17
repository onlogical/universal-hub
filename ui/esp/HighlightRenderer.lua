local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local VisualPolicy = importDependency("ui/esp/VisualPolicy", "./VisualPolicy")
local ColorPolicy = importDependency("ui/esp/ColorPolicy", "./ColorPolicy")
local HighlightRenderer = {}
HighlightRenderer.__index = HighlightRenderer

local function restoreExecutorThread()
    local setter = setthreadidentity or setidentity or setthreadcontext
    if type(setter) == "function" then
        pcall(setter, 8)
    end
end

local function onExecutorThread(callback)
    if type(callback) ~= "function" then
        return callback
    end
    return function(...)
        restoreExecutorThread()
        return callback(...)
    end
end

-- A hard cap keeps adversarial character hierarchies from producing unbounded Instances.
HighlightRenderer.HIGHLIGHT_BUDGET = 255
HighlightRenderer.SUBJECT_HIGHLIGHT_BUDGET = 17
HighlightRenderer.HIGHLIGHT_DISTANCE = 1000
HighlightRenderer.HIGHLIGHT_DISTANCE_HYSTERESIS = 100
HighlightRenderer.DISTANCE_REFRESH_INTERVAL = 0.25

local COLORS = VisualPolicy.COLORS

local function disconnect(connection)
    if type(connection) == "function" then
        connection()
    elseif connection then
        connection:Disconnect()
    end
end

local function clearConnections(connections)
    if not connections then
        return
    end
    for _, connection in ipairs(connections) do
        disconnect(connection)
    end
    table.clear(connections)
end

local function hold(connections, handle)
    if handle then
        table.insert(connections, handle)
    end
end

local function safeDestroy(instance)
    if instance then
        instance:Destroy()
    end
end

local function findChild(character, className, name)
    if not character then
        return nil
    end
    if character.FindFirstChildOfClass then
        local child = character:FindFirstChildOfClass(className)
        if child then
            return child
        end
    end
    if name and character.FindFirstChild then
        return character:FindFirstChild(name)
    end
    return nil
end

local function label(create, parent, name, size, color, position)
    local node = create("TextLabel")
    node.Name = name
    node.AnchorPoint = Vector2.new(0.5, 0)
    node.BackgroundTransparency = 1
    node.Font = Enum.Font.GothamBold
    node.Position = position
    node.Size = UDim2.new(1, -20, 0, size + 3)
    node.TextColor3 = color
    node.TextSize = size
    node.TextStrokeColor3 = Color3.new(0, 0, 0)
    node.TextStrokeTransparency = 0.2
    node.TextTruncate = Enum.TextTruncate.None
    node.TextXAlignment = Enum.TextXAlignment.Center
    node.Parent = parent
    return node
end

function HighlightRenderer.new(context)
    assert(context and context.guiParent, "HighlightRenderer requires guiParent")
    assert(context.store, "HighlightRenderer requires a store")
    assert(context.players, "HighlightRenderer requires Players")
    assert(context.runService and context.runService.Heartbeat,
        "HighlightRenderer requires RunService.Heartbeat")

    local rawCreate = context.createInstance or Instance.new
    local self = setmetatable({
        context = context,
        create = function(...)
            restoreExecutorThread()
            return rawCreate(...)
        end,
        policy = {},
        subjects = {},
        extraKeys = {},
        playerConnections = {},
        playerPolicyConnections = {},
        policyConnections = {},
        active = false,
        destroyed = false,
        highlightCount = 0,
        nextSubjectOrder = 0,
        distanceAccumulator = 0,
    }, HighlightRenderer)

    self.unsubscribe = context.store:Subscribe(onExecutorThread(function(state)
        self:_applyState(state)
    end))
    return self
end

function HighlightRenderer:_settings()
    local state = self.context.store:Get()
    return state.settings or {}
end

function HighlightRenderer:_ensureRoot()
    restoreExecutorThread()
    if self.root then
        return self.root
    end
    local root = self.create("Folder")
    root.Name = "UniversalHubNativeWorld"
    root.Parent = self.context.guiParent
    self.root = root
    return root
end

function HighlightRenderer:_playerTone(player, character)
    local getter = self.policy.getPlayerTone
    if getter then
        local ok, tone = pcall(getter, player, character)
        return ok and tone or nil, true
    end
    local predicate = self.policy.isPlayerEligible
    if not predicate then
        return "enemy", false
    end
    local ok, eligible = pcall(predicate, player, character)
    return ok and eligible == true and "enemy" or nil, false
end

function HighlightRenderer:_eligible(player, character)
    if player == self.context.localPlayer or player == self.context.players.LocalPlayer then
        return false, nil
    end
    local tone, declared = self:_playerTone(player, character)
    if declared then
        local settings = self:_settings()
        local selected = tone == "team" and settings.showTeammates == true
            or tone ~= "team" and settings.showEnemies ~= false
        return tone ~= nil and selected, tone
    end
    return tone ~= nil, tone
end

local function isA(instance, className)
    return instance and instance.IsA and instance:IsA(className) == true
end

function HighlightRenderer:_newHighlight(subject, adornee)
    restoreExecutorThread()
    if self.highlightCount >= HighlightRenderer.HIGHLIGHT_BUDGET
        or #subject.highlights >= (subject.highlightBudget or 1) then
        return nil
    end
    local highlight = self.create("Highlight")
    highlight.Name = "SubjectHighlight"
    highlight.Adornee = adornee
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = self:_ensureRoot()
    table.insert(subject.highlights, highlight)
    self.highlightCount = self.highlightCount + 1
    return highlight
end

function HighlightRenderer:_clearHighlights(subject)
    for _, highlight in ipairs(subject.highlights) do
        safeDestroy(highlight)
        self.highlightCount = math.max(0, self.highlightCount - 1)
    end
    table.clear(subject.highlights)
end

function HighlightRenderer:_configureHighlights(subject)
    local settings = self:_settings()
    local perPart = (settings.boxes == true or settings.chams == true)
        and settings.chamsPerPart == true
    local excludeAccessories = settings.chamsExcludeAccessories == true
    if subject.highlightConfigured and subject.perPart == perPart
        and subject.excludeAccessories == excludeAccessories
        and (#subject.highlights > 0
            or (perPart and (subject.highlightBudget or 0) <= 0)
            or not (settings.boxes == true or settings.chams == true))
    then
        return
    end
    subject.highlightConfigured = true
    subject.perPart = perPart
    subject.excludeAccessories = excludeAccessories
    clearConnections(subject.hierarchyConnections)
    subject.rebuildHighlights = nil
    self:_clearHighlights(subject)

    if not perPart then
        subject.perPartApplied = false
        subject.highlightBudget = 1
        self:_newHighlight(subject, subject.character)
        return
    end
    if (subject.highlightBudget or 0) <= 0 then
        subject.perPartApplied = false
        return
    end

    subject.perPartApplied = true
    local function rebuild()
        restoreExecutorThread()
        if not self.active or not self.subjects[subject.key] then
            return
        end
        self:_clearHighlights(subject)
        local bodyParts = {}
        local accessoryParts = {}
        if subject.character.GetDescendants then
            for _, descendant in ipairs(subject.character:GetDescendants()) do
                if isA(descendant, "BasePart") then
                    local accessoryOwned = false
                    local ancestor = descendant.Parent
                    while ancestor and ancestor ~= subject.character do
                        if isA(ancestor, "Accessory") then
                            accessoryOwned = true
                            break
                        end
                        ancestor = ancestor.Parent
                    end
                    table.insert(accessoryOwned and accessoryParts or bodyParts, descendant)
                end
            end
        else
            local children = subject.character.GetChildren and subject.character:GetChildren() or {}
            for _, child in ipairs(children) do
                if isA(child, "BasePart") then
                    table.insert(bodyParts, child)
                elseif isA(child, "Accessory") then
                    local handle = child.FindFirstChild and child:FindFirstChild("Handle")
                    if isA(handle, "BasePart") then
                        table.insert(accessoryParts, handle)
                    end
                end
            end
        end
        for _, part in ipairs(bodyParts) do
            self:_newHighlight(subject, part)
        end
        if not excludeAccessories then
            for _, part in ipairs(accessoryParts) do
                self:_newHighlight(subject, part)
            end
        end
        self:_styleHighlights(subject)
    end
    subject.rebuildHighlights = rebuild
    local descendantAdded = subject.character.DescendantAdded or subject.character.ChildAdded
    local descendantRemoving = subject.character.DescendantRemoving or subject.character.ChildRemoved
    if descendantAdded then
        table.insert(subject.hierarchyConnections, descendantAdded:Connect(onExecutorThread(rebuild)))
    end
    if descendantRemoving then
        table.insert(subject.hierarchyConnections, descendantRemoving:Connect(onExecutorThread(rebuild)))
    end
    rebuild()
end

function HighlightRenderer:_perPartRelevant(settings)
    return self.active
        and (settings.boxes == true or settings.chams == true)
        and settings.chamsPerPart == true
end

function HighlightRenderer:_localRootPart()
    local localPlayer = self.context.localPlayer or self.context.players.LocalPlayer
    local character = localPlayer and localPlayer.Character
    if not character then
        return nil
    end
    local namedRoot = character.FindFirstChild and character:FindFirstChild("HumanoidRootPart")
    return character.PrimaryPart or namedRoot or findChild(character, "BasePart")
end

local function distanceSquared(first, second)
    if not first or not second or first.Position == nil or second.Position == nil then
        return nil
    end
    local ok, displacement = pcall(function()
        return first.Position - second.Position
    end)
    if not ok or displacement == nil then
        return nil
    end
    local magnitude = displacement.Magnitude
    return type(magnitude) == "number" and magnitude * magnitude or nil
end

function HighlightRenderer:_refreshHighlightDistances()
    if not self:_perPartRelevant(self:_settings()) then
        return
    end
    local localRoot = self:_localRootPart()
    local enterDistanceSquared = HighlightRenderer.HIGHLIGHT_DISTANCE ^ 2
    local exitDistanceSquared = (HighlightRenderer.HIGHLIGHT_DISTANCE
        + HighlightRenderer.HIGHLIGHT_DISTANCE_HYSTERESIS) ^ 2
    local candidates = {}
    for _, subject in pairs(self.subjects) do
        local subjectDistanceSquared = distanceSquared(localRoot, subject.rootPart)
        local threshold = subject.withinHighlightDistance and exitDistanceSquared or enterDistanceSquared
        subject.withinHighlightDistance = subjectDistanceSquared ~= nil
            and subjectDistanceSquared <= threshold
        subject.highlightDistanceSquared = subjectDistanceSquared
        if subject.withinHighlightDistance then
            table.insert(candidates, subject)
        end
    end
    table.sort(candidates, function(first, second)
        if first.highlightDistanceSquared == second.highlightDistanceSquared then
            return first.order < second.order
        end
        return first.highlightDistanceSquared < second.highlightDistanceSquared
    end)

    local poolCount = math.min(#candidates, HighlightRenderer.HIGHLIGHT_BUDGET)
    local baseBudget = poolCount > 0 and math.min(
        HighlightRenderer.SUBJECT_HIGHLIGHT_BUDGET,
        math.floor(HighlightRenderer.HIGHLIGHT_BUDGET / poolCount)
    ) or 0
    local remainder = baseBudget < HighlightRenderer.SUBJECT_HIGHLIGHT_BUDGET
        and HighlightRenderer.HIGHLIGHT_BUDGET - baseBudget * poolCount or 0
    local budgets = {}
    for index = 1, poolCount do
        budgets[candidates[index]] = baseBudget + (index <= remainder and 1 or 0)
    end
    local budgetChanged = {}
    for _, subject in pairs(self.subjects) do
        local nextBudget = budgets[subject] or 0
        if subject.highlightBudget ~= nextBudget then
            subject.highlightBudget = nextBudget
            subject.highlightConfigured = false
            table.insert(budgetChanged, subject)
        end
    end
    -- Release changed allocations before rebuilding so table iteration order cannot
    -- let an old, farther allocation starve a newly nearer subject at the hard cap.
    for _, subject in ipairs(budgetChanged) do
        self:_clearHighlights(subject)
    end
    for _, subject in pairs(self.subjects) do
        self:_configureHighlights(subject)
    end
end

function HighlightRenderer:_stopDistanceRefresh()
    disconnect(self.distanceConnection)
    self.distanceConnection = nil
    self.distanceAccumulator = 0
end

function HighlightRenderer:_syncDistanceRefresh()
    if not self:_perPartRelevant(self:_settings()) then
        self:_stopDistanceRefresh()
        for _, subject in pairs(self.subjects) do
            subject.withinHighlightDistance = nil
            subject.highlightDistanceSquared = nil
        end
        return
    end
    if self.distanceConnection then
        return
    end
    self:_refreshHighlightDistances()
    self.distanceConnection = self.context.runService.Heartbeat:Connect(onExecutorThread(function(deltaTime)
        if not self:_perPartRelevant(self:_settings()) then
            self:_stopDistanceRefresh()
            return
        end
        self.distanceAccumulator += deltaTime
        if self.distanceAccumulator < HighlightRenderer.DISTANCE_REFRESH_INTERVAL then
            return
        end
        self.distanceAccumulator %= HighlightRenderer.DISTANCE_REFRESH_INTERVAL
        self:_refreshHighlightDistances()
    end))
end

function HighlightRenderer:_rebalanceHighlights()
    if not self.active then
        return
    end
    if self:_perPartRelevant(self:_settings()) then
        self:_refreshHighlightDistances()
        return
    end
    for _, subject in pairs(self.subjects) do
        if subject.highlightBudget ~= 1 then
            subject.highlightBudget = 1
            subject.highlightConfigured = false
        end
        self:_configureHighlights(subject)
    end
end

function HighlightRenderer:_styleHighlights(subject, color)
    restoreExecutorThread()
    local settings = self:_settings()
    color = color or subject.highlightColor or COLORS.danger
    subject.highlightColor = color
    local outlineColor = ColorPolicy.color(settings, "outline", color, subject.tone)
    local fillColor = ColorPolicy.color(settings, "fill", color, subject.tone)
    local fillAlpha = ColorPolicy.fillAlpha(settings, 1 - VisualPolicy.FILL_TRANSPARENCY, subject.tone)
    for _, highlight in ipairs(subject.highlights) do
        highlight.Enabled = settings.boxes == true or settings.chams == true
        highlight.OutlineColor = outlineColor
        highlight.OutlineTransparency = settings.boxes == true and 0 or 1
        highlight.FillColor = fillColor
        highlight.FillTransparency = settings.chams == true and 1 - fillAlpha or 1
    end
end

function HighlightRenderer:_connectCharacterPolicy(subject)
    clearConnections(subject.policyConnections)
    local connector = subject.player and self.policy.connectCharacterChanged
    if connector then
        hold(subject.policyConnections, connector(subject.player, subject.character, onExecutorThread(function()
            if self.active and self.subjects[subject.key] == subject then
                self:_invalidatePlayer(subject.player)
            end
        end)))
    end
end

function HighlightRenderer:_makeSubject(key, descriptor, player)
    restoreExecutorThread()
    if not self.active or self.subjects[key] or not descriptor or not descriptor.character then
        return nil
    end
    local tone
    if player then
        local eligible
        eligible, tone = self:_eligible(player, descriptor.character)
        if not eligible then
            return nil
        end
    end

    local character = descriptor.character
    local humanoid = descriptor.humanoid or findChild(character, "Humanoid", "Humanoid")
    local namedRoot = character.FindFirstChild and character:FindFirstChild("HumanoidRootPart")
    local rootPart = descriptor.rootPart or character.PrimaryPart or namedRoot
        or findChild(character, "BasePart")

    self:_ensureRoot()
    local billboard = self.create("BillboardGui")
    billboard.Name = "SubjectBillboard"
    billboard.Adornee = rootPart
    billboard.AlwaysOnTop = true
    billboard.ClipsDescendants = false
    billboard.LightInfluence = 0
    billboard.MaxDistance = HighlightRenderer.HIGHLIGHT_DISTANCE
    billboard.ResetOnSpawn = false
    billboard.Size = UDim2.fromOffset(240, 132)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.25, 0)
    billboard.Parent = self.context.guiParent

    local canvas = self.create("Frame")
    canvas.Name = "BodyCanvas"
    canvas.BackgroundTransparency = 1
    canvas.Size = UDim2.fromScale(1, 1)
    canvas.Parent = billboard

    local name = label(self.create, canvas, "Name", 13, COLORS.text, UDim2.new(0.5, 6, 0, 2))
    local healthValue = label(self.create, canvas, "HealthValue", 12, COLORS.signal, UDim2.new(0.5, 6, 0, 98))
    local weapon = label(self.create, canvas, "Weapon", 12, COLORS.secondary, UDim2.new(0.5, 6, 0, 114))

    local healthTrack = self.create("Frame")
    healthTrack.Name = "HealthRail"
    healthTrack.BackgroundColor3 = COLORS.track
    healthTrack.BorderSizePixel = 0
    healthTrack.Position = UDim2.fromOffset(4, 20)
    healthTrack.Size = UDim2.fromOffset(6, 76)
    healthTrack.Parent = canvas

    local trackCorner = self.create("UICorner")
    trackCorner.CornerRadius = UDim.new(0, 3)
    trackCorner.Parent = healthTrack

    local railStroke = self.create("UIStroke")
    railStroke.Color = Color3.fromRGB(12, 14, 16)
    railStroke.Thickness = 1
    railStroke.Parent = healthTrack

    local healthFill = self.create("Frame")
    healthFill.Name = "Fill"
    healthFill.AnchorPoint = Vector2.new(0, 1)
    healthFill.BackgroundColor3 = COLORS.signal
    healthFill.BorderSizePixel = 0
    healthFill.Position = UDim2.new(0, 1, 1, 0)
    healthFill.Size = UDim2.new(0, 4, 1, 0)
    healthFill.Parent = healthTrack

    local fillCorner = self.create("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 3)
    fillCorner.Parent = healthFill

    self.nextSubjectOrder += 1
    local subject = {
        key = key,
        order = self.nextSubjectOrder,
        highlightBudget = 0,
        player = player,
        character = character,
        humanoid = humanoid,
        rootPart = rootPart,
        descriptor = descriptor,
        connections = {},
        policyConnections = {},
        hierarchyConnections = {},
        highlights = {},
        billboard = billboard,
        name = name,
        healthValue = healthValue,
        weapon = weapon,
        healthTrack = healthTrack,
        healthFill = healthFill,
        presentation = {},
        tone = tone,
    }
    self.subjects[key] = subject
    self:_rebalanceHighlights()
    self:_connectCharacterPolicy(subject)

    if humanoid then
        if humanoid.HealthChanged then
            table.insert(subject.connections, humanoid.HealthChanged:Connect(onExecutorThread(function()
                self:_updateHealth(subject)
            end)))
        elseif humanoid.GetPropertyChangedSignal then
            table.insert(subject.connections, humanoid:GetPropertyChangedSignal("Health"):Connect(onExecutorThread(function()
                self:_updateHealth(subject)
            end)))
        end
        if humanoid.GetPropertyChangedSignal then
            table.insert(subject.connections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(onExecutorThread(function()
                self:_updateHealth(subject)
            end)))
        end
    end
    self:_updateSubject(subject)
    return subject
end

function HighlightRenderer:_removeSubject(key)
    restoreExecutorThread()
    local subject = self.subjects[key]
    if not subject then
        return
    end
    self.subjects[key] = nil
    clearConnections(subject.connections)
    clearConnections(subject.policyConnections)
    clearConnections(subject.hierarchyConnections)
    self:_clearHighlights(subject)
    safeDestroy(subject.billboard)
    self:_rebalanceHighlights()
end

function HighlightRenderer:_weapon(subject, observation)
    if observation and observation.weapon ~= nil then
        return observation.weapon
    end
    if subject.descriptor.weapon ~= nil then
        return subject.descriptor.weapon
    end
    local getter = self.policy.getWeapon
    if getter then
        local ok, value = pcall(getter, subject.player, subject.character, observation)
        if ok then
            return value
        end
    end
    return nil
end

function HighlightRenderer:_updateHealth(subject, observation)
    if not self.active or not self.subjects[subject.key] then
        return
    end
    local humanoid = subject.humanoid
    local health = observation and observation.health
    if type(health) ~= "number" then
        health = humanoid and humanoid.Health or 0
    end
    local maximum = observation and observation.maxHealth
    if type(maximum) ~= "number" then
        maximum = humanoid and humanoid.MaxHealth or 0
    end
    local infinite = health == math.huge
    local fraction
    if infinite or maximum == math.huge then
        fraction = 1
    elseif maximum > 0 then
        fraction = math.clamp(health / maximum, 0, 1)
    else
        fraction = 0
    end
    local color = ColorPolicy.healthColor(self:_settings(), fraction, COLORS.danger, COLORS.signal, subject.tone)
    subject.healthFill.Size = UDim2.new(0, 4, fraction, 0)
    subject.healthFill.BackgroundColor3 = color
    subject.healthValue.TextColor3 = color
    subject.healthValue.Text = infinite and "∞ HP" or ("%d HP"):format(math.ceil(health))
end

function HighlightRenderer:_updateSubject(subject, observation)
    restoreExecutorThread()
    local settings = self:_settings()
    local presentation = observation and observation.presentation or subject.presentation or {}
    subject.presentation = presentation
    local tone = observation and observation.tone or subject.tone
    local color = presentation.color or (tone and COLORS[tone])
        or ((observation and observation.visible == true) and COLORS.signal or COLORS.danger)

    self:_configureHighlights(subject)
    self:_styleHighlights(subject, color)

    subject.name.Text = presentation.name or subject.descriptor.name
        or (subject.player and subject.player.Name) or tostring(subject.key)
    subject.name.TextColor3 = ColorPolicy.color(settings, "name", color, tone)
    subject.name.Visible = settings.names == true
    local hasHealth = subject.humanoid ~= nil
        or (observation and type(observation.health) == "number")
    subject.healthTrack.Visible = settings.health == true and hasHealth
    subject.healthValue.Visible = settings.health == true and hasHealth
    local weapon = self:_weapon(subject, observation)
    subject.weapon.Text = weapon == nil and "" or tostring(weapon)
    subject.weapon.TextColor3 = ColorPolicy.color(settings, "weapon", color, tone)
    subject.weapon.Visible = settings.weapon == true and weapon ~= nil and tostring(weapon) ~= ""
    subject.billboard.Enabled = subject.rootPart ~= nil
        and (subject.name.Visible or subject.healthTrack.Visible or subject.weapon.Visible)
    self:_updateHealth(subject, observation)
end

function HighlightRenderer:_attachCharacter(player, character)
    self:_removeSubject(player)
    self:_makeSubject(player, { character = character }, player)
end

function HighlightRenderer:_invalidatePlayer(player)
    restoreExecutorThread()
    if not self.active then
        return
    end
    local character = player.Character
    local subject = self.subjects[player]
    local eligible, tone = false, nil
    if character then
        eligible, tone = self:_eligible(player, character)
    end
    if not character or not eligible then
        self:_removeSubject(player)
    elseif not subject or subject.character ~= character then
        self:_attachCharacter(player, character)
    else
        subject.tone = tone
        self:_updateSubject(subject)
    end
end

function HighlightRenderer:_connectPlayerPolicy(player)
    clearConnections(self.playerPolicyConnections[player])
    local connections = {}
    self.playerPolicyConnections[player] = connections
    if self.policy.connectPlayerChanged then
        hold(connections, self.policy.connectPlayerChanged(player, onExecutorThread(function()
            self:_invalidatePlayer(player)
        end)))
    end
end

function HighlightRenderer:_trackPlayer(player)
    if player == self.context.localPlayer or player == self.context.players.LocalPlayer
        or self.playerConnections[player] then
        return
    end
    local connections = {}
    self.playerConnections[player] = connections
    self:_connectPlayerPolicy(player)
    if player.CharacterAdded then
        table.insert(connections, player.CharacterAdded:Connect(onExecutorThread(function(character)
            if self.active then
                self:_attachCharacter(player, character)
            end
        end)))
    end
    if player.CharacterRemoving then
        table.insert(connections, player.CharacterRemoving:Connect(onExecutorThread(function(character)
            local subject = self.subjects[player]
            if subject and subject.character == character then
                self:_removeSubject(player)
            end
        end)))
    end
    if player.Character then
        self:_attachCharacter(player, player.Character)
    end
end

function HighlightRenderer:_untrackPlayer(player)
    self:_removeSubject(player)
    local connections = self.playerConnections[player]
    self.playerConnections[player] = nil
    clearConnections(connections)
    clearConnections(self.playerPolicyConnections[player])
    self.playerPolicyConnections[player] = nil
end

function HighlightRenderer:_invalidatePolicy()
    if not self.active then
        return
    end
    local players = {}
    for player in pairs(self.playerConnections) do
        table.insert(players, player)
    end
    for _, player in ipairs(players) do
        self:_invalidatePlayer(player)
    end
    for _, subject in pairs(self.subjects) do
        self:_updateSubject(subject)
    end
end

function HighlightRenderer:_subscribePolicyChanged()
    if self.policy.subscribeChanged then
        hold(self.policyConnections, self.policy.subscribeChanged(onExecutorThread(function()
            self:_invalidatePolicy()
        end)))
    end
end

function HighlightRenderer:_subscribeExtras()
    local subscribe = self.policy.subscribeExtras
    if not subscribe then
        return
    end
    self.extraCleanup = subscribe(onExecutorThread(function(descriptor)
        if descriptor and descriptor.key ~= nil then
            self.extraKeys[descriptor.key] = true
            self:_removeSubject(descriptor.key)
            self:_makeSubject(descriptor.key, descriptor, nil)
        end
    end), onExecutorThread(function(keyOrDescriptor)
        local key = type(keyOrDescriptor) == "table" and keyOrDescriptor.key or keyOrDescriptor
        if key ~= nil then
            self.extraKeys[key] = nil
            self:_removeSubject(key)
        end
    end))
end

function HighlightRenderer:_clearExtras()
    local keys = {}
    for key in pairs(self.extraKeys) do
        table.insert(keys, key)
    end
    table.clear(self.extraKeys)
    for _, key in ipairs(keys) do
        self:_removeSubject(key)
    end
end

function HighlightRenderer:_activate()
    if self.active then
        return
    end
    self.active = true
    self:_ensureRoot()
    local players = self.context.players
    self.playerAdded = players.PlayerAdded:Connect(onExecutorThread(function(player)
        self:_trackPlayer(player)
    end))
    self.playerRemoving = players.PlayerRemoving:Connect(onExecutorThread(function(player)
        self:_untrackPlayer(player)
    end))
    for _, player in ipairs(players:GetPlayers()) do
        self:_trackPlayer(player)
    end
    self:_subscribePolicyChanged()
    self:_subscribeExtras()
    self:_syncDistanceRefresh()
end

function HighlightRenderer:_deactivate()
    if not self.active then
        return
    end
    self.active = false
    self:_stopDistanceRefresh()
    disconnect(self.playerAdded)
    disconnect(self.playerRemoving)
    self.playerAdded = nil
    self.playerRemoving = nil
    clearConnections(self.policyConnections)
    if self.extraCleanup then
        self.extraCleanup()
        self.extraCleanup = nil
    end
    self:_clearExtras()
    local players = {}
    for player in pairs(self.playerConnections) do
        table.insert(players, player)
    end
    for _, player in ipairs(players) do
        self:_untrackPlayer(player)
    end
    local keys = {}
    for key in pairs(self.subjects) do
        table.insert(keys, key)
    end
    for _, key in ipairs(keys) do
        self:_removeSubject(key)
    end
    safeDestroy(self.root)
    self.root = nil
end

function HighlightRenderer:_applyState(state)
    restoreExecutorThread()
    if self.destroyed then
        return
    end
    local highlights = self.context.highlightsSupported ~= false
        and state.settings and state.settings.worldRenderer == "native"
    if highlights then
        local showEnemies = state.settings.showEnemies ~= false
        local showTeammates = state.settings.showTeammates == true
        local membershipChanged = self.active
            and (self.showEnemies ~= showEnemies or self.showTeammates ~= showTeammates)
        self.showEnemies = showEnemies
        self.showTeammates = showTeammates
        self:_activate()
        self:_syncDistanceRefresh()
        if membershipChanged then
            self:_invalidatePolicy()
        else
            for _, subject in pairs(self.subjects) do
                self:_updateSubject(subject)
            end
        end
    else
        self.showEnemies = true
        self.showTeammates = false
        self:_deactivate()
    end
end

function HighlightRenderer:setPolicy(policy)
    self.policy = policy or {}
    if not self.active then
        return
    end
    clearConnections(self.policyConnections)
    if self.extraCleanup then
        self.extraCleanup()
        self.extraCleanup = nil
    end
    self:_clearExtras()
    local players = self.context.players:GetPlayers()
    for _, player in ipairs(players) do
        if self.playerConnections[player] then
            self:_connectPlayerPolicy(player)
            self:_invalidatePlayer(player)
            local subject = self.subjects[player]
            if subject then
                self:_connectCharacterPolicy(subject)
            end
        end
    end
    self:_subscribePolicyChanged()
    self:_subscribeExtras()
end

function HighlightRenderer:render(observations)
    local unclaimed = {}
    for _, observation in ipairs(observations or {}) do
        local key = observation.key or observation.player
        local subject = not self.destroyed and self.active and key and self.subjects[key]
        if subject then
            self:_updateSubject(subject, observation)
        else
            table.insert(unclaimed, observation)
        end
    end
    return unclaimed
end

function HighlightRenderer:destroy()
    if self.destroyed then
        return
    end
    self.destroyed = true
    if self.unsubscribe then
        self.unsubscribe()
        self.unsubscribe = nil
    end
    self:_deactivate()
end

return HighlightRenderer
