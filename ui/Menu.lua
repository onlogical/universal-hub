local HubMenu = {}
HubMenu.__index = HubMenu

local function restoreExecutorThread()
    local setter = setthreadidentity or setidentity or setthreadcontext
    if type(setter) == "function" then
        pcall(setter, 8)
    end
end

local SHELL = Color3.fromRGB(18, 18, 19)
local SURFACE = Color3.fromRGB(24, 24, 26)
local DIVIDER = Color3.fromRGB(48, 48, 52)
local BORDER = Color3.fromRGB(68, 68, 73)
local TEXT = Color3.fromRGB(244, 247, 249)
local MUTED = Color3.fromRGB(177, 188, 199)
local DIM = Color3.fromRGB(103, 115, 126)
local ACCENT = Color3.fromRGB(255, 118, 87)
local INK = Color3.fromRGB(28, 11, 8)
local SECTION_COLOR = {
    added = Color3.fromRGB(98, 214, 173),
    changed = Color3.fromRGB(255, 167, 145),
    fixed = Color3.fromRGB(157, 199, 235),
    removed = Color3.fromRGB(255, 163, 176),
    security = Color3.fromRGB(255, 190, 92),
}

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

local function formatDate(value)
    local year, month, day = tostring(value or ""):match("^(%d+)%-(%d+)%-(%d+)$")
    if not month then
        return tostring(value or "")
    end
    return string.format("%s %d", MONTHS[tonumber(month)], tonumber(day))
end

local function applyType(instance, size, weight)
    instance.Font = Enum.Font.BuilderSans
    instance.TextSize = size
    instance.TextStrokeTransparency = 1
    instance.BorderSizePixel = 0
    instance.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", weight)
end

local function createText(parent, name, size, weight, color)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.BackgroundTransparency = 1
    label.TextColor3 = color
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.TextWrapped = true
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.Size = UDim2.new(1, 0, 0, 0)
    applyType(label, size, weight)
    label.Parent = parent
    return label
end

local function createGhost(parent, name, text)
    local button = Instance.new("TextButton")
    button.Name = name
    button.AutoButtonColor = false
    button.BackgroundTransparency = 1
    button.Text = text
    button.TextColor3 = DIM
    button.AutomaticSize = Enum.AutomaticSize.XY
    button.Size = UDim2.fromOffset(0, 28)
    applyType(button, 13, Enum.FontWeight.Medium)
    button.Parent = parent
    button.MouseEnter:Connect(function()
        button.TextColor3 = TEXT
    end)
    button.MouseLeave:Connect(function()
        button.TextColor3 = DIM
    end)
    return button
end

local function createFill(parent, name, text)
    local button = Instance.new("TextButton")
    button.Name = name
    button.AutoButtonColor = false
    button.BackgroundColor3 = ACCENT
    button.Text = text
    button.TextColor3 = INK
    button.Size = UDim2.fromOffset(72, 28)
    applyType(button, 13, Enum.FontWeight.Bold)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = button
    button.Parent = parent
    return button
end

local function mountWhatsNew(parent, onAction)
    local layer = Instance.new("ScreenGui")
    layer.Name = "UniversalHubWhatsNew"
    layer.DisplayOrder = 1100
    layer.IgnoreGuiInset = true
    layer.ResetOnSpawn = false
    layer.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    layer.Enabled = false
    layer.Parent = parent

    local dim = Instance.new("TextButton")
    dim.Name = "Backdrop"
    dim.AutoButtonColor = false
    dim.Text = ""
    dim.TextTransparency = 1
    dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    dim.BackgroundTransparency = 0.46
    dim.BorderSizePixel = 0
    dim.Size = UDim2.fromScale(1, 1)
    dim.Parent = layer

    local card = Instance.new("Frame")
    card.Name = "Card"
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(0.5, 0.5)
    card.Size = UDim2.fromOffset(520, 420)
    card.BackgroundColor3 = SHELL
    card.BorderSizePixel = 0
    card.ClipsDescendants = true
    card.Parent = layer
    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 10)
    cardCorner.Parent = card
    local cardStroke = Instance.new("UIStroke")
    cardStroke.Color = BORDER
    cardStroke.Transparency = 0.2
    cardStroke.Thickness = 1
    cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    cardStroke.Parent = card

    local header = Instance.new("Frame")
    header.Name = "Header"
    header.BackgroundColor3 = SURFACE
    header.BorderSizePixel = 0
    header.Size = UDim2.new(1, 0, 0, 48)
    header.Parent = card
    local heading = createText(header, "Title", 16, Enum.FontWeight.Bold, TEXT)
    heading.AutomaticSize = Enum.AutomaticSize.None
    heading.Position = UDim2.fromOffset(16, 14)
    heading.Size = UDim2.fromOffset(220, 20)
    heading.Text = "What's New"
    heading.TextYAlignment = Enum.TextYAlignment.Center
    local close = Instance.new("TextButton")
    close.Name = "Close"
    close.AutoButtonColor = false
    close.BackgroundTransparency = 1
    close.Text = "×"
    close.TextColor3 = DIM
    close.AnchorPoint = Vector2.new(1, 0)
    close.Position = UDim2.new(1, -10, 0, 10)
    close.Size = UDim2.fromOffset(28, 28)
    applyType(close, 20, Enum.FontWeight.Regular)
    close.Parent = header
    close.MouseEnter:Connect(function()
        close.TextColor3 = TEXT
    end)
    close.MouseLeave:Connect(function()
        close.TextColor3 = DIM
    end)

    local split = Instance.new("Frame")
    split.Name = "Split"
    split.BackgroundTransparency = 1
    split.BorderSizePixel = 0
    split.Position = UDim2.fromOffset(0, 48)
    split.Size = UDim2.new(1, 0, 1, -92)
    split.Parent = card

    local rail = Instance.new("ScrollingFrame")
    rail.Name = "Rail"
    rail.BackgroundColor3 = SURFACE
    rail.BorderSizePixel = 0
    rail.AutomaticCanvasSize = Enum.AutomaticSize.Y
    rail.CanvasSize = UDim2.new(0, 0, 0, 0)
    rail.ScrollBarThickness = 5
    rail.ScrollBarImageColor3 = MUTED
    rail.ScrollBarImageTransparency = 0.15
    rail.ScrollingDirection = Enum.ScrollingDirection.Y
    rail.Size = UDim2.new(0, 132, 1, 0)
    rail.Parent = split
    local railPad = Instance.new("UIPadding")
    railPad.PaddingTop = UDim.new(0, 12)
    railPad.PaddingBottom = UDim.new(0, 12)
    railPad.PaddingLeft = UDim.new(0, 10)
    railPad.PaddingRight = UDim.new(0, 10)
    railPad.Parent = rail
    local railLayout = Instance.new("UIListLayout")
    railLayout.FillDirection = Enum.FillDirection.Vertical
    railLayout.Padding = UDim.new(0, 6)
    railLayout.SortOrder = Enum.SortOrder.LayoutOrder
    railLayout.Parent = rail

    local gutter = Instance.new("Frame")
    gutter.Name = "Gutter"
    gutter.BackgroundColor3 = DIVIDER
    gutter.BackgroundTransparency = 0.25
    gutter.BorderSizePixel = 0
    gutter.Position = UDim2.fromOffset(132, 0)
    gutter.Size = UDim2.new(0, 1, 1, 0)
    gutter.Parent = split

    local notes = Instance.new("ScrollingFrame")
    notes.Name = "Notes"
    notes.BackgroundTransparency = 1
    notes.BorderSizePixel = 0
    notes.AutomaticCanvasSize = Enum.AutomaticSize.Y
    notes.CanvasSize = UDim2.new(0, 0, 0, 0)
    notes.ScrollBarThickness = 5
    notes.ScrollBarImageColor3 = MUTED
    notes.ScrollBarImageTransparency = 0.15
    notes.ScrollingDirection = Enum.ScrollingDirection.Y
    notes.Position = UDim2.fromOffset(133, 0)
    notes.Size = UDim2.new(1, -133, 1, 0)
    notes.Parent = split
    local notesPad = Instance.new("UIPadding")
    notesPad.PaddingTop = UDim.new(0, 20)
    notesPad.PaddingBottom = UDim.new(0, 20)
    notesPad.PaddingLeft = UDim.new(0, 20)
    notesPad.PaddingRight = UDim.new(0, 14)
    notesPad.Parent = notes
    local notesLayout = Instance.new("UIListLayout")
    notesLayout.FillDirection = Enum.FillDirection.Vertical
    notesLayout.Padding = UDim.new(0, 0)
    notesLayout.SortOrder = Enum.SortOrder.LayoutOrder
    notesLayout.Parent = notes

    local footer = Instance.new("Frame")
    footer.Name = "Footer"
    footer.BackgroundColor3 = SURFACE
    footer.BorderSizePixel = 0
    footer.AnchorPoint = Vector2.new(0, 1)
    footer.Position = UDim2.fromScale(0, 1)
    footer.Size = UDim2.new(1, 0, 0, 44)
    footer.Parent = card
    local mute = createGhost(footer, "Mute", "Don't show again")
    mute.Position = UDim2.fromOffset(16, 8)
    local gotIt = createFill(footer, "GotIt", "Got it")
    gotIt.AnchorPoint = Vector2.new(1, 0)
    gotIt.Position = UDim2.new(1, -16, 0, 8)

    local selectedVersion = ""
    local railButtons = {}

    local function paintRail()
        for version, button in pairs(railButtons) do
            local active = version == selectedVersion
            local versionLabel = button:FindFirstChild("Version")
            local titleLabel = button:FindFirstChild("Title")
            if versionLabel then
                versionLabel.TextColor3 = active and TEXT or MUTED
            end
            if titleLabel then
                titleLabel.TextColor3 = active and MUTED or DIM
            end
            local mark = button:FindFirstChild("Active")
            if mark then
                mark.BackgroundTransparency = active and 0 or 1
            end
        end
    end

    local function showVersion(version)
        selectedVersion = version
        paintRail()
        for _, child in ipairs(notes:GetChildren()) do
            if child:IsA("Frame") then
                child.Visible = child.Name == "Release_" .. version
            end
        end
        notes.CanvasPosition = Vector2.new(0, 0)
    end

    dim.MouseButton1Click:Connect(function()
        onAction("whatsNewDismiss")
    end)
    close.MouseButton1Click:Connect(function()
        onAction("whatsNewDismiss")
    end)
    mute.MouseButton1Click:Connect(function()
        onAction("whatsNewDontShowAgain")
    end)
    gotIt.MouseButton1Click:Connect(function()
        onAction("whatsNewAcknowledge")
    end)

    local function render(notice)
        notice = notice or {}
        layer.Enabled = notice.visible == true
        if notice.visible ~= true then
            return
        end
        local releases = notice.releases
        if type(releases) ~= "table" or #releases == 0 then
            releases = notice.entries or {}
        end
        local fresh = notice.fresh or {}
        selectedVersion = type(notice.current) == "string" and notice.current or (releases[1] and releases[1].version) or ""
        table.clear(railButtons)
        for _, child in ipairs(rail:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end
        for _, child in ipairs(notes:GetChildren()) do
            if child:IsA("Frame") then
                child:Destroy()
            end
        end
        for index, release in ipairs(releases) do
            local version = tostring(release.version or "")
            local button = Instance.new("TextButton")
            button.Name = "Version_" .. version
            button.AutoButtonColor = false
            button.BackgroundTransparency = 1
            button.Text = ""
            button.Size = UDim2.new(1, 0, 0, 40)
            button.LayoutOrder = index
            button.Parent = rail
            local active = Instance.new("Frame")
            active.Name = "Active"
            active.BackgroundColor3 = ACCENT
            active.BackgroundTransparency = 1
            active.BorderSizePixel = 0
            active.Position = UDim2.fromOffset(-6, 8)
            active.Size = UDim2.fromOffset(2, 24)
            active.Parent = button
            local versionLabel = createText(button, "Version", 13, Enum.FontWeight.Bold, MUTED)
            versionLabel.AutomaticSize = Enum.AutomaticSize.None
            versionLabel.Position = UDim2.fromOffset(6, 4)
            versionLabel.Size = UDim2.new(1, -14, 0, 16)
            versionLabel.Text = tostring(release.displayVersion or version)
            versionLabel.TextYAlignment = Enum.TextYAlignment.Center
            local titleLabel = createText(button, "Title", 11, Enum.FontWeight.Medium, DIM)
            titleLabel.AutomaticSize = Enum.AutomaticSize.None
            titleLabel.Position = UDim2.fromOffset(6, 20)
            titleLabel.Size = UDim2.new(1, -14, 0, 16)
            titleLabel.Text = tostring(release.title or "")
            titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
            titleLabel.TextYAlignment = Enum.TextYAlignment.Center
            if fresh[version] then
                local pip = Instance.new("Frame")
                pip.Name = "Fresh"
                pip.BackgroundColor3 = ACCENT
                pip.BorderSizePixel = 0
                pip.AnchorPoint = Vector2.new(1, 0.5)
                pip.Position = UDim2.new(1, 0, 0.5, 0)
                pip.Size = UDim2.fromOffset(5, 5)
                pip.Parent = button
                local pipCorner = Instance.new("UICorner")
                pipCorner.CornerRadius = UDim.new(1, 0)
                pipCorner.Parent = pip
            end
            button.MouseButton1Click:Connect(function()
                showVersion(version)
            end)
            railButtons[version] = button

            local entry = Instance.new("Frame")
            entry.Name = "Release_" .. version
            entry.BackgroundTransparency = 1
            entry.BorderSizePixel = 0
            entry.AutomaticSize = Enum.AutomaticSize.Y
            entry.Size = UDim2.new(1, 0, 0, 0)
            entry.Visible = false
            entry.LayoutOrder = 1
            entry.Parent = notes
            local entryLayout = Instance.new("UIListLayout")
            entryLayout.FillDirection = Enum.FillDirection.Vertical
            entryLayout.Padding = UDim.new(0, 20)
            entryLayout.SortOrder = Enum.SortOrder.LayoutOrder
            entryLayout.Parent = entry
            local headingBlock = Instance.new("Frame")
            headingBlock.Name = "Heading"
            headingBlock.BackgroundTransparency = 1
            headingBlock.BorderSizePixel = 0
            headingBlock.AutomaticSize = Enum.AutomaticSize.Y
            headingBlock.Size = UDim2.new(1, 0, 0, 0)
            headingBlock.LayoutOrder = 1
            headingBlock.Parent = entry
            local headingLayout = Instance.new("UIListLayout")
            headingLayout.FillDirection = Enum.FillDirection.Vertical
            headingLayout.Padding = UDim.new(0, 2)
            headingLayout.SortOrder = Enum.SortOrder.LayoutOrder
            headingLayout.Parent = headingBlock
            local headingLine = createText(headingBlock, "Title", 22, Enum.FontWeight.ExtraBold, TEXT)
            headingLine.LayoutOrder = 1
            headingLine.Text = tostring(release.title or "")
            local meta = createText(headingBlock, "Meta", 12, Enum.FontWeight.Medium, DIM)
            meta.LayoutOrder = 2
            local stamped = formatDate(release.date)
            if release.channel == "beta" then
                stamped = stamped .. " · Beta"
            end
            meta.Text = stamped
            local order = 2
            for _, section in ipairs(release.sections or {}) do
                local block = Instance.new("Frame")
                block.Name = "Section"
                block.BackgroundTransparency = 1
                block.BorderSizePixel = 0
                block.AutomaticSize = Enum.AutomaticSize.Y
                block.Size = UDim2.new(1, 0, 0, 0)
                block.LayoutOrder = order
                block.Parent = entry
                order += 1
                local blockLayout = Instance.new("UIListLayout")
                blockLayout.FillDirection = Enum.FillDirection.Vertical
                blockLayout.Padding = UDim.new(0, 8)
                blockLayout.SortOrder = Enum.SortOrder.LayoutOrder
                blockLayout.Parent = block
                local label = createText(block, "Label", 14, Enum.FontWeight.ExtraBold, SECTION_COLOR[section.id] or MUTED)
                label.LayoutOrder = 1
                label.Text = tostring(section.label or "")
                local items = Instance.new("Frame")
                items.Name = "Items"
                items.BackgroundTransparency = 1
                items.BorderSizePixel = 0
                items.AutomaticSize = Enum.AutomaticSize.Y
                items.Size = UDim2.new(1, 0, 0, 0)
                items.LayoutOrder = 2
                items.Parent = block
                local itemsLayout = Instance.new("UIListLayout")
                itemsLayout.FillDirection = Enum.FillDirection.Vertical
                itemsLayout.Padding = UDim.new(0, 10)
                itemsLayout.SortOrder = Enum.SortOrder.LayoutOrder
                itemsLayout.Parent = items
                local groups = section.groups
                if type(groups) ~= "table" or #groups == 0 then
                    groups = {
                        {
                            tab = "",
                            items = {},
                        },
                    }
                    for _, item in ipairs(section.items or {}) do
                        table.insert(groups[1].items, {
                            name = tostring(item),
                            note = "",
                        })
                    end
                end
                for groupIndex, group in ipairs(groups) do
                    local cluster = Instance.new("Frame")
                    cluster.Name = "Tab"
                    cluster.BackgroundTransparency = 1
                    cluster.BorderSizePixel = 0
                    cluster.AutomaticSize = Enum.AutomaticSize.Y
                    cluster.Size = UDim2.new(1, 0, 0, 0)
                    cluster.LayoutOrder = groupIndex
                    cluster.Parent = items
                    local clusterLayout = Instance.new("UIListLayout")
                    clusterLayout.FillDirection = Enum.FillDirection.Vertical
                    clusterLayout.Padding = UDim.new(0, 6)
                    clusterLayout.SortOrder = Enum.SortOrder.LayoutOrder
                    clusterLayout.Parent = cluster
                    local nextOrder = 1
                    if type(group.tab) == "string" and group.tab ~= "" then
                        local tabLabel = createText(cluster, "Tab", 12, Enum.FontWeight.ExtraBold, TEXT)
                        tabLabel.LayoutOrder = nextOrder
                        tabLabel.Text = group.tab
                        nextOrder += 1
                    end
                    for featureIndex, feature in ipairs(group.items or {}) do
                        local row = Instance.new("Frame")
                        row.Name = "Item"
                        row.BackgroundTransparency = 1
                        row.BorderSizePixel = 0
                        row.AutomaticSize = Enum.AutomaticSize.Y
                        row.Size = UDim2.new(1, 0, 0, 0)
                        row.LayoutOrder = nextOrder + featureIndex - 1
                        row.Parent = cluster
                        local rowLayout = Instance.new("UIListLayout")
                        rowLayout.FillDirection = Enum.FillDirection.Vertical
                        rowLayout.Padding = UDim.new(0, 2)
                        rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
                        rowLayout.Parent = row
                        local nameRow = Instance.new("Frame")
                        nameRow.Name = "Feature"
                        nameRow.BackgroundTransparency = 1
                        nameRow.BorderSizePixel = 0
                        nameRow.AutomaticSize = Enum.AutomaticSize.Y
                        nameRow.Size = UDim2.new(1, 0, 0, 0)
                        nameRow.LayoutOrder = 1
                        nameRow.Parent = row
                        local bullet = Instance.new("Frame")
                        bullet.Name = "Bullet"
                        bullet.BackgroundColor3 = MUTED
                        bullet.BorderSizePixel = 0
                        bullet.Position = UDim2.fromOffset(0, 6)
                        bullet.Size = UDim2.fromOffset(4, 4)
                        bullet.Parent = nameRow
                        local bulletCorner = Instance.new("UICorner")
                        bulletCorner.CornerRadius = UDim.new(1, 0)
                        bulletCorner.Parent = bullet
                        local name = createText(nameRow, "Name", 13, Enum.FontWeight.Medium, MUTED)
                        name.Position = UDim2.fromOffset(12, 0)
                        name.Size = UDim2.new(1, -12, 0, 0)
                        local label = tostring(feature.name or feature.text or "")
                        if type(feature.note) == "string" and feature.note ~= "" then
                            label = label .. " - " .. feature.note
                        end
                        name.Text = label
                    end
                end
            end
        end
        showVersion(selectedVersion)
    end

    return {
        gui = layer,
        update = render,
        destroy = function()
            layer:Destroy()
        end,
    }
end

local function withExecutorScheduler(fn)
    restoreExecutorThread()
    local delay, defer, spawn = task.delay, task.defer, task.spawn
    local function wrapCallback(callback)
        if type(callback) ~= "function" then
            return callback
        end
        return function(...)
            restoreExecutorThread()
            return callback(...)
        end
    end
    pcall(function()
        task.delay = function(duration, callback, ...)
            return delay(duration, wrapCallback(callback), ...)
        end
        task.defer = function(callback, ...)
            return defer(wrapCallback(callback), ...)
        end
        task.spawn = function(callback, ...)
            return spawn(wrapCallback(callback), ...)
        end
    end)
    local ok, result = pcall(fn)
    pcall(function()
        task.delay = delay
        task.defer = defer
        task.spawn = spawn
    end)
    if not ok then
        error(result, 0)
    end
    return result
end

function HubMenu.new(context)
    assert(type(context) == "table", "HubMenu requires context")
    assert(type(context.prismMenu) == "table" and type(context.prismMenu.mountUniversalHubMenu) == "function", "HubMenu requires the compiled Prism artifact")
    assert(type(context.presentation) == "table" and type(context.presentation.mount) == "function", "HubMenu requires a game presentation")
    assert(type(context.catalog) == "table" and type(context.catalog.new) == "function", "HubMenu requires PresentationCatalog")
    assert(context.store, "HubMenu requires Store")
    assert(typeof(context.uiParent) == "Instance", "HubMenu requires a gethui() parent")
    restoreExecutorThread()

    local existing = context.uiParent:FindFirstChild("UniversalHubNative")
    if existing then
        existing:Destroy()
    end
    local existingNotice = context.uiParent:FindFirstChild("UniversalHubWhatsNew")
    if existingNotice then
        existingNotice:Destroy()
    end

    local createInstance = context.createInstance or Instance.new
    local screenGui = createInstance("ScreenGui")
    screenGui.Name = "UniversalHubNative"
    screenGui.DisplayOrder = 1000
    screenGui.IgnoreGuiInset = true
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Enabled = context.menuEnabled ~= false
    screenGui.Parent = context.uiParent

    local publishedPreview
    context.publishPreviewObservation = function(observation)
        publishedPreview = observation
    end
    context.reportPreviewStatus = function(stage, detail)
        context.previewStatus = { stage = stage, detail = detail }
    end
    local catalog = context.catalog.new(context)
    context.presentation.mount(catalog)
    catalog:finalize()
    local model = catalog:model(context.store:Get())
    local handle = withExecutorScheduler(function()
        return context.prismMenu.mountUniversalHubMenu(screenGui, model)
    end)
    local whatsNew = mountWhatsNew(context.uiParent, function(name)
        catalog:action(name)
    end)
    whatsNew.update(model.whatsNew)
    local self = setmetatable({
        catalog = catalog,
        context = context,
        destroyed = false,
        gui = screenGui,
        handle = handle,
        whatsNew = whatsNew,
        model = model,
        previewObservation = function()
            return publishedPreview
        end,
    }, HubMenu)
    self.unsubscribe = context.store:Subscribe(function(state)
        if self.destroyed then
            return
        end
        withExecutorScheduler(function()
            self.model = self.catalog:model(state)
            self.handle.update(self.model)
            if self.whatsNew then
                self.whatsNew.update(self.model.whatsNew)
            end
        end)
        if self.context.setInputCaptured then
            self.context.setInputCaptured(state.menuVisible ~= false)
        end
    end)
    return self
end

local function activePreview(model)
    for _, page in ipairs(model and model.pages or {}) do
        if page.preview and page.preview.kind == "character" then
            return page.preview
        end
    end
    return nil
end

function HubMenu:previewObservations()
    if self.destroyed or self.context.store:Get().menuVisible == false then
        return nil, nil
    end
    local published = self.previewObservation and self.previewObservation() or nil
    if not published or not published.bounds or not published.bodyParts then
        return nil, nil
    end
    self.previewPlayer = self.previewPlayer or {
        Name = game:GetService("Players").LocalPlayer.Name,
    }
    local preview = activePreview(self.model) or {}
    return {
        {
            player = self.previewPlayer,
            visible = true,
            health = 72,
            maxHealth = 100,
            weapon = preview.weaponLabel,
            tone = preview.tone,
            previewRenderer = preview.worldRenderer,
            bounds = published.bounds,
            bodyParts = published.bodyParts,
        },
    }, nil
end

function HubMenu:isCaptured()
    return not self.destroyed and self.context.store:Get().menuVisible ~= false
end

function HubMenu:destroy()
    if self.destroyed then
        return
    end
    self.destroyed = true
    restoreExecutorThread()
    if self.unsubscribe then
        self.unsubscribe()
        self.unsubscribe = nil
    end
    if self.context.setInputCaptured then
        self.context.setInputCaptured(false)
    end
    if self.context.publishPreviewObservation then
        self.context.publishPreviewObservation(nil)
        self.context.publishPreviewObservation = nil
    end
    if self.whatsNew then
        self.whatsNew.destroy()
        self.whatsNew = nil
    end
    if self.handle then
        withExecutorScheduler(function()
            self.handle.destroy()
        end)
        self.handle = nil
    end
    if self.gui then
        self.gui:Destroy()
        self.gui = nil
    end
end

return HubMenu
