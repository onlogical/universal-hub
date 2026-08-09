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

local NativeVisualPolicy = importDependency("modules/NativeVisualPolicy", "./NativeVisualPolicy")
local EspColorPolicy = importDependency("modules/EspColorPolicy", "./EspColorPolicy")
local Overlay = {}
Overlay.__index = Overlay

local PRESENTATION_TOKENS = {
    font = {
        control = Drawing.Fonts.Plex,
        heading = Drawing.Fonts.Plex,
    },
    control = {
        borderThickness = 1,
        fovCircleSides = 96,
        fovCircleThickness = 1.5,
        fovThumbRadius = 8,
        progressTrackHeight = 4,
        rateThumbRadius = 7,
        segmentCornerRadius = 4,
        sliderCircleSides = 32,
        sliderTrackHeight = 5,
        switchCircleSides = 24,
        switchInnerRadius = 9,
        switchInnerTrackHeight = 18,
        switchKnobRadius = 9,
        switchKnobRimRadius = 9.5,
        switchOuterRadius = 11,
        switchOuterTrackHeight = 22,
        switchTrackWidth = 20,
    },
    layout = {
        cardContentInset = 16,
        cardInset = 20,
        contentTopWithTabs = 158,
        contentTopWithoutTabs = 72,
        contentWidth = 350,
        headerContentInset = 20,
        headerHeight = 64,
        initialHeight = 790,
        innerControlWidth = 350,
        shellRightInset = 44,
        shellTopInset = 20,
        shellWidth = 390,
        shadowX = 3,
        shadowY = 4,
        statusDotRightInset = 18,
        statusDotTop = 45,
        statusTop = 36,
        tabBarHeight = 44,
        tabsTop = 84,
        titleTop = 13,
    },
    opacity = {
        divider = 0.58,
        edge = 0.72,
        focus = 0.96,
        fovCircle = 0.8,
        hitbox = 0.01,
        quietControl = 0.98,
        subDivider = 0.38,
    },
    type = {
        display = 18,
        eyebrow = 9,
        header = 16,
        label = 13,
        meta = 10,
        primary = 12,
        rateValue = 15,
        row = 12,
        section = 16,
        status = 11,
    },
}

local COLORS = {
    accent = Color3.fromRGB(160, 225, 194),
    accentSurface = Color3.fromRGB(30, 53, 44),
    border = Color3.fromRGB(39, 41, 46),
    danger = Color3.fromRGB(255, 118, 87),
    elevated = Color3.fromRGB(31, 33, 37),
    header = Color3.fromRGB(25, 26, 30),
    hover = Color3.fromRGB(37, 39, 43),
    panel = Color3.fromRGB(24, 26, 29),
    panelShadow = Color3.fromRGB(12, 14, 16),
    secondary = Color3.fromRGB(190, 192, 195),
    signal = Color3.fromRGB(98, 214, 173),
    team = Color3.fromRGB(101, 157, 214),
    tertiary = Color3.fromRGB(128, 132, 138),
    text = Color3.fromRGB(243, 243, 244),
    track = Color3.fromRGB(55, 56, 61),
    tokens = PRESENTATION_TOKENS,
    toggleActive = Color3.fromRGB(160, 225, 194),
}

local function playerColor(observation, visible)
    local presentation = observation.presentation
    if type(presentation) == "table" and presentation.color ~= nil then
        return presentation.color
    end
    if observation.tone == "team" then
        return COLORS.team
    end
    return visible == true and COLORS.signal or COLORS.danger
end

local WORLD_LAYER = {
    chams = 10,
    player = 11,
    health = 12,
    playerDetail = 13,
    utilityZone = 20,
    utility = 21,
    utilityText = 22,
}

local BODY_CUBE_FACES = {
    { 1, 2, 3, 4 },
    { 5, 8, 7, 6 },
    { 1, 5, 6, 2 },
    { 4, 3, 7, 8 },
    { 1, 4, 8, 5 },
    { 2, 6, 7, 3 },
}
local UTILITY_CUBE_EDGES = {
    { 1, 2 },
    { 2, 3 },
    { 3, 4 },
    { 4, 1 },
    { 5, 6 },
    { 6, 7 },
    { 7, 8 },
    { 8, 5 },
    { 1, 5 },
    { 2, 6 },
    { 3, 7 },
    { 4, 8 },
}

local function convexHull(points)
    if #points < 3 then
        return points
    end
    table.sort(points, function(left, right)
        return left.X == right.X and left.Y < right.Y or left.X < right.X
    end)
    local unique = {}
    for _, point in ipairs(points) do
        local previous = unique[#unique]
        if not previous or previous.X ~= point.X or previous.Y ~= point.Y then
            table.insert(unique, point)
        end
    end
    if #unique < 3 then
        return unique
    end
    local function cross(origin, left, right)
        return (left.X - origin.X) * (right.Y - origin.Y)
            - (left.Y - origin.Y) * (right.X - origin.X)
    end
    local lower = {}
    for _, point in ipairs(unique) do
        while #lower >= 2 and cross(lower[#lower - 1], lower[#lower], point) <= 0 do
            table.remove(lower)
        end
        table.insert(lower, point)
    end
    local upper = {}
    for index = #unique, 1, -1 do
        local point = unique[index]
        while #upper >= 2 and cross(upper[#upper - 1], upper[#upper], point) <= 0 do
            table.remove(upper)
        end
        table.insert(upper, point)
    end
    table.remove(lower)
    table.remove(upper)
    for _, point in ipairs(upper) do
        table.insert(lower, point)
    end
    return lower
end

local BODY_CUBE_OPACITY = 0.18
local NATIVE_PREVIEW_FILL_TRANSPARENCY = NativeVisualPolicy.FILL_TRANSPARENCY
local EVENT_SIGNALS = {
    click = "Clicked",
    drag = "Dragged",
    pointerdown = "PointerDown",
    pointerenter = "PointerEntered",
    pointerleave = "PointerLeft",
    pointerup = "PointerUp",
}

local function wrapElement(element, canvas)
    local object = element:getObject()
    local callbacks = {}
    local node
    local methods = {}

    function methods:on(eventName, callback)
        local signalName = assert(EVENT_SIGNALS[eventName], "Unknown Limn element event: " .. tostring(eventName))
        assert(type(callback) == "function", "Limn element event handler must be a function")
        callbacks[eventName] = callback
        element:setInteractive(true)
        return element[signalName]:Connect(function(event)
            callback(node, event.position, event.input, event.delta)
        end)
    end

    function methods:set(properties)
        element:patch(properties)
        return node
    end

    methods.patch = methods.set

    function methods:destroy()
        element:destroy()
    end

    methods.Destroy = methods.destroy
    methods.Remove = methods.destroy

    function methods:getObject()
        return object
    end

    function methods:paintCaptured(zIndex, callback)
        return canvas:paintCaptured(element, zIndex, callback)
    end

    node = setmetatable({
        callbacks = callbacks,
    }, {
        __index = function(_, key)
            local method = methods[key]
            if method ~= nil then
                return method
            end
            return object[key]
        end,
        __newindex = function(_, key, value)
            element:set(key, value)
        end,
    })
    return node
end

local function createCanvasView(runtime)
    local canvas = runtime:createCanvas()
    local surface = {
        canvas = canvas,
    }

    function surface:create(kind, properties, options)
        local interactive = options ~= nil
            and (options.interactive == true or options.pointerEvents == true)
        return wrapElement(canvas:create(kind, properties, {
            interactive = interactive,
        }), canvas)
    end

    function surface:paint(zIndex, callback)
        return canvas:paint(zIndex, callback)
    end

    function surface:bindInput(inputService)
        return canvas:bindInput(inputService)
    end

    function surface:destroy()
        canvas:destroy()
    end

    return surface
end

local function clampCenteredUtilityLabel(position, viewportSize, textBounds)
    if not viewportSize then
        return position
    end
    local halfWidth = math.max(textBounds and textBounds.X * 0.5 or 0, 32)
    local halfHeight = math.max(textBounds and textBounds.Y * 0.5 or 0, 7)
    local marginX = halfWidth + 4
    local marginY = halfHeight + 4
    return Vector2.new(
        math.clamp(position.X, marginX, math.max(marginX, viewportSize.X - marginX)),
        math.clamp(position.Y, marginY, math.max(marginY, viewportSize.Y - marginY))
    )
end

local function setVisible(nodes, visible)
    for _, node in pairs(nodes) do
        if type(node) == "table" and node.Visible == nil then
            setVisible(node, visible)
        else
            node.Visible = visible
        end
    end
end

function Overlay.new(context)
    assert(context and context.limn, "Hub overlay requires a Limn runtime")
    assert(context.store, "Hub overlay requires a reactive store")

    local primitiveSupport = {}
    for _, kind in ipairs({ "Square", "Circle", "Text", "Triangle", "Quad", "Line" }) do
        primitiveSupport[kind] = context.limn:supportsPrimitive(kind)
    end
    local optionSupport = {
        chams = primitiveSupport.Quad,
    }
    local self = setmetatable({
        activeSliderVisuals = setmetatable({}, { __mode = "k" }),
        captured = false,
        context = context,
        controlColors = setmetatable({}, { __mode = "k" }),
        controls = {},
        destroyed = false,
        observations = {},
        optionSupport = optionSupport,
        primitiveSupport = primitiveSupport,
        playerNodes = {},
        utilityNodes = {},
        chamPaint = {
            enabled = false,
            observations = {},
        },
        utilityZonePaint = {
            enabled = false,
            observations = {},
        },
        worldGui = nil,
    }, Overlay)

    local missingPrimitives = {}
    for _, kind in ipairs({ "Square", "Circle", "Text", "Triangle" }) do
        if not primitiveSupport[kind] then
            table.insert(missingPrimitives, kind)
        end
    end
    self.missingPrimitives = missingPrimitives
    if #missingPrimitives > 0 then
        self.available = false
        warn(
            "[Universal Hub]",
            "overlay disabled; unsupported drawing primitives:",
            table.concat(missingPrimitives, ", ")
        )
        return self
    end

    self.available = true
    self.surface = createCanvasView(context.limn)
    self.canvas = self.surface.canvas
    if context.inputService and not context.worldOnly then
        self.surface:bindInput(context.inputService)
    end
    if not context.worldOnly then
        self:_build()
        local presentationRuntime = context.presentationRuntime.new({
        activeSliderVisuals = self.activeSliderVisuals,
        capabilities = context.capabilities,
        cosmeticsSupported = context.cosmetics ~= false,
        context = context,
        controls = self.controls,
        createKeybindControl = function(options)
            return context.limn:createKeybindControl(self.canvas, options)
        end,
        createSegmentedControl = function(options)
            return context.limn:createSegmentedControl(self.canvas, options)
        end,
        interactive = function(node)
            return self:_interactive(node)
        end,
        node = function(kind, properties, pointerEvents)
            return self.surface:create(kind, properties, {
                pointerEvents = pointerEvents == true,
            })
        end,
        optionSupport = self.optionSupport,
        refreshVisibility = function()
            self:_setMenuVisible(context.store:Get().menuVisible ~= false)
        end,
        requestLayout = function()
            self:_layout()
        end,
        requestRender = function()
            self:_renderState(context.store:Get())
        end,
        setControlColor = function(node, color)
            self:_setControlColor(node, color)
        end,
        text = function(properties, pointerEvents)
            return self:_text(properties, pointerEvents)
        end,
        theme = COLORS,
    }, context.presentationParts)
        self.presentationHost = context.presentationHost.mount(presentationRuntime, context.presentation)
        self:_layout()
    end
    self.immediateChams = pcall(function()
        self.chamPaintConnection = self.surface:paint(WORLD_LAYER.chams, function(renderer)
            self:_paintChams(renderer)
        end)
    end)
    if self.immediateChams then
        self.optionSupport.chams = true
    end
    self.immediateUtilityZones = pcall(function()
        self.utilityPaintConnection = self.surface:paint(WORLD_LAYER.utilityZone, function(renderer)
            self:_paintUtilityZones(renderer)
        end)
    end)
    if not context.worldOnly then
        self.unsubscribe = context.store:Subscribe(function(state)
            self:_renderState(state)
        end)
    end
    return self
end

function Overlay:_capture(node)
    return node
end

function Overlay:_interactive(node)
    self.controlColors[node] = node.Color
    node:on("pointerenter", function(target)
        if target.Visible then
            target.Color = COLORS.hover
        end
    end)
    node:on("pointerleave", function(target)
        target.Color = self.controlColors[target]
    end)
    return self:_capture(node)
end

function Overlay:_setControlColor(node, color)
    self.controlColors[node] = color
    node.Color = color
end

function Overlay:_text(properties, pointerEvents)
    properties.Font = properties.Font or Drawing.Fonts.Plex
    properties.Visible = properties.Visible ~= false
    return self.surface:create("Text", properties, {
        pointerEvents = pointerEvents == true,
    })
end

function Overlay:_build()
    local surface = self.surface
    local controls = self.controls
    local layoutTokens = PRESENTATION_TOKENS.layout

    controls.panelShadow = surface:create("Square", {
        Color = COLORS.panelShadow,
        Filled = true,
        Size = Vector2.new(layoutTokens.shellWidth, layoutTokens.initialHeight),
        Transparency = 0.32,
        Visible = true,
        ZIndex = 198,
    }, { pointerEvents = false })
    controls.panel = self:_capture(surface:create("Square", {
        Color = COLORS.panel,
        Filled = true,
        Size = Vector2.new(layoutTokens.shellWidth, layoutTokens.initialHeight),
        Transparency = 1,
        Visible = true,
        ZIndex = 200,
    }))
    controls.panelBorder = surface:create("Square", {
        Color = COLORS.border,
        Filled = false,
        Size = Vector2.new(layoutTokens.shellWidth, layoutTokens.initialHeight),
        Thickness = 1,
        Transparency = 0.9,
        Visible = true,
        ZIndex = 206,
    }, { pointerEvents = false })
    controls.headerSurface = surface:create("Square", {
        Color = COLORS.header,
        Filled = true,
        Size = Vector2.new(layoutTokens.shellWidth, layoutTokens.headerHeight),
        Transparency = 1,
        Visible = true,
        ZIndex = 201,
    }, { pointerEvents = false })
    controls.headerRail = surface:create("Square", {
        Color = COLORS.accent,
        Filled = true,
        Size = Vector2.zero,
        Visible = false,
        ZIndex = 202,
    }, { pointerEvents = false })
    controls.panel:on("pointerdown", function(_node, point)
        self.panelDragOffset = point - controls.panel.Position
    end)
    controls.panel:on("drag", function(_node, point)
        if not self.panelDragOffset then
            return
        end
        self.panelPosition = point - self.panelDragOffset
        self:_layout()
    end)
    controls.title = self:_text({
        Color = COLORS.text,
        Size = PRESENTATION_TOKENS.type.header,
        Text = "Universal Hub · " .. (self.context.gameLabel or "Universal"),
        ZIndex = 202,
    })
    controls.status = self:_text({
        Color = COLORS.secondary,
        Size = PRESENTATION_TOKENS.type.status,
        Text = "Inspecting client",
        ZIndex = 202,
    })
    controls.statusDot = surface:create("Circle", {
        Color = COLORS.accent,
        Filled = true,
        NumSides = 20,
        Radius = 3,
        Visible = false,
        ZIndex = 203,
    }, { pointerEvents = false })
end

function Overlay:_layout()
    local camera = self.context.getCamera()
    if not camera then
        return
    end

    local controls = self.controls
    local panelSize = controls.panel.Size
    local layoutTokens = PRESENTATION_TOKENS.layout
    local defaultPosition = Vector2.new(
        math.max(layoutTokens.shellRightInset, camera.ViewportSize.X - panelSize.X - layoutTokens.shellRightInset),
        layoutTokens.shellTopInset
    )
    local requestedPosition = self.panelPosition or defaultPosition
    local x = math.clamp(requestedPosition.X, 0, math.max(0, camera.ViewportSize.X - panelSize.X))
    local y = math.clamp(requestedPosition.Y, 0, math.max(0, camera.ViewportSize.Y - panelSize.Y))
    if self.panelPosition then
        self.panelPosition = Vector2.new(x, y)
    end
    controls.panel.Position = Vector2.new(x, y)
    controls.panelShadow.Position = Vector2.new(x + layoutTokens.shadowX, y + layoutTokens.shadowY)
    controls.panelBorder.Position = Vector2.new(x, y)
    controls.headerSurface.Position = Vector2.new(x, y)
    controls.headerRail.Position = Vector2.new(x, y)
    controls.title.Position = Vector2.new(x + layoutTokens.headerContentInset, y + layoutTokens.titleTop)
    controls.status.Position = Vector2.new(x + layoutTokens.headerContentInset, y + layoutTokens.statusTop)
    controls.statusDot.Position = Vector2.new(
        x + panelSize.X - layoutTokens.statusDotRightInset,
        y + layoutTokens.statusDotTop
    )
    self.presentationHost:layout(x, y)
end

function Overlay:_setMenuVisible(visible)
    local controls = self.controls
    for _, name in ipairs({
        "panel",
        "panelShadow",
        "panelBorder",
        "headerSurface",
        "title",
        "status",
    }) do
        controls[name].Visible = visible
    end
    self.presentationHost:setVisible(visible)
    if self.captured ~= visible then
        self.captured = visible
        if self.context.setInputCaptured then
            self.context.setInputCaptured(visible)
        end
    end
end

function Overlay:_renderState(state)
    if self.destroyed then
        return
    end

    local controls = self.controls
    controls.status.Text = state.status or "Ready"
    controls.status.Color = state.error and COLORS.danger or COLORS.secondary
    controls.statusDot.Color = state.error and COLORS.danger or COLORS.signal
    self:_layout()
    self.presentationHost:render(state)
    self:_layout()
    self.presentationHost:render(state)
    self:_setMenuVisible(state.menuVisible ~= false)
end

function Overlay:_ensureBombBillboard()
    if self.worldGui or not self.context.uiParent then
        return self.worldGui
    end

    local createInstance = self.context.createInstance or Instance.new
    local billboard = createInstance("BillboardGui")
    billboard.Name = "UniversalHubBombTimer"
    billboard.AlwaysOnTop = false
    billboard.Enabled = false
    billboard.LightInfluence = 0
    billboard.MaxDistance = 350
    billboard.Size = UDim2.fromOffset(64, 22)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
    billboard.Parent = self.context.uiParent

    local panel = createInstance("Frame")
    panel.Name = "Panel"
    panel.BackgroundColor3 = COLORS.panel
    panel.BackgroundTransparency = 0.04
    panel.BorderSizePixel = 0
    panel.Size = UDim2.fromScale(1, 1)
    panel.Parent = billboard

    local corner = createInstance("UICorner")
    corner.CornerRadius = UDim.new(0, 3)
    corner.Parent = panel

    local stroke = createInstance("UIStroke")
    stroke.Color = COLORS.border
    stroke.Thickness = 1
    stroke.Parent = panel

    local accent = createInstance("Frame")
    accent.Name = "Accent"
    accent.BackgroundColor3 = COLORS.accent
    accent.BorderSizePixel = 0
    accent.Position = UDim2.fromOffset(4, 4)
    accent.Size = UDim2.new(0, 3, 1, -8)
    accent.Parent = panel

    local title = createInstance("TextLabel")
    title.Name = "Title"
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.Code
    title.Position = UDim2.new(0, 12, 0, 0)
    title.Size = UDim2.new(0.42, -12, 1, 0)
    title.Text = "BOMB"
    title.TextColor3 = COLORS.secondary
    title.TextSize = 10
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = panel

    local timer = createInstance("TextLabel")
    timer.Name = "Timer"
    timer.BackgroundTransparency = 1
    timer.Font = Enum.Font.Code
    timer.Position = UDim2.new(0.42, 0, 0, 0)
    timer.Size = UDim2.new(0.58, -8, 1, 0)
    timer.Text = "0.0s"
    timer.TextColor3 = COLORS.text
    timer.TextSize = 13
    timer.TextXAlignment = Enum.TextXAlignment.Right
    timer.Parent = panel

    self.worldGui = {
        accent = accent,
        billboard = billboard,
        panel = panel,
        stroke = stroke,
        timer = timer,
        title = title,
    }
    return self.worldGui
end

function Overlay:_renderBomb(observation, settings)
    local visible = settings.bombTimer == true
        and type(observation) == "table"
        and observation.visible == true
        and observation.adornee ~= nil
    if not visible then
        if self.worldGui then
            self.worldGui.billboard.Enabled = false
        end
        return
    end

    local gui = self:_ensureBombBillboard()
    if not gui then
        return
    end
    local presentation = observation.presentation or {}
    gui.billboard.Adornee = observation.adornee
    gui.billboard.AlwaysOnTop = presentation.alwaysOnTop == true
    gui.billboard.Enabled = presentation.visible ~= false
    gui.billboard.Size = UDim2.fromOffset(presentation.width or 64, presentation.height or 22)
    local urgent = (observation.remaining or 0) <= 10
    gui.timer.Text = ("%.1fs"):format(math.max(observation.remaining or 0, 0))
    gui.timer.TextColor3 = urgent and COLORS.danger or COLORS.text
    gui.timer.TextSize = presentation.textSize or 13
    gui.accent.BackgroundColor3 = urgent and COLORS.danger or COLORS.accent
    gui.stroke.Color = urgent and COLORS.danger or COLORS.border
end

function Overlay:_getPlayerNodes(player)
    local nodes = self.playerNodes[player]
    if nodes then
        return nodes
    end

    nodes = {
        bodyParts = {},
        nativeHull = {},
        box = self.surface:create("Square", {
            Color = COLORS.danger,
            Filled = false,
            Thickness = 1.5,
            Visible = false,
            ZIndex = WORLD_LAYER.chams,
        }, { pointerEvents = false }),
        name = self:_text({
            Center = true,
            Color = COLORS.text,
            Outline = true,
            Size = 13,
            Text = "",
            Visible = false,
            ZIndex = WORLD_LAYER.player,
        }),
        healthTrack = self.surface:create("Square", {
            Color = COLORS.border,
            Filled = true,
            Visible = false,
            ZIndex = WORLD_LAYER.player,
        }, { pointerEvents = false }),
        healthFill = self.surface:create("Square", {
            Color = COLORS.accent,
            Filled = true,
            Visible = false,
            ZIndex = WORLD_LAYER.health,
        }, { pointerEvents = false }),
        healthTip = self.surface:create("Square", {
            Color = COLORS.text,
            Filled = true,
            Visible = false,
            ZIndex = WORLD_LAYER.playerDetail,
        }, { pointerEvents = false }),
        healthValue = self:_text({
            Center = false,
            Color = COLORS.accent,
            Outline = true,
            Size = 14,
            Text = "",
            Visible = false,
            ZIndex = WORLD_LAYER.playerDetail,
        }),
        weapon = self:_text({
            Center = true,
            Color = COLORS.secondary,
            Outline = true,
            Size = 12,
            Text = "",
            Visible = false,
            ZIndex = WORLD_LAYER.player,
        }),
    }
    self.playerNodes[player] = nodes
    return nodes
end

function Overlay:_syncBodyPartNodes(nodes, count)
    while #nodes.bodyParts < count do
        local cube = {
            faces = {},
        }
        if not self.immediateChams and self.optionSupport.chams ~= false then
            for _faceIndex = 1, #BODY_CUBE_FACES do
                table.insert(
                    cube.faces,
                    self.surface:create("Quad", {
                        Color = COLORS.danger,
                        Filled = true,
                        Transparency = BODY_CUBE_OPACITY,
                        Visible = false,
                        ZIndex = WORLD_LAYER.chams,
                    }, { pointerEvents = false })
                )
            end
        end
        table.insert(nodes.bodyParts, cube)
    end

    for index = count + 1, #nodes.bodyParts do
        setVisible(nodes.bodyParts[index], false)
    end
end

function Overlay:_ensureNativeBodyPartOutlines(cube)
    if cube.outlines or not self.primitiveSupport.Quad then
        return
    end
    cube.outlines = {}
    for _faceIndex = 1, #BODY_CUBE_FACES do
        table.insert(
            cube.outlines,
            self.surface:create("Quad", {
                Color = COLORS.danger,
                Filled = false,
                Thickness = NativeVisualPolicy.OUTLINE_THICKNESS,
                Transparency = 0,
                Visible = false,
                ZIndex = WORLD_LAYER.player,
            }, { pointerEvents = false })
        )
    end
end

function Overlay:_syncNativeHull(nodes, count)
    while #nodes.nativeHull < count do
        table.insert(nodes.nativeHull, self.surface:create("Line", {
            Color = COLORS.danger,
            Thickness = NativeVisualPolicy.OUTLINE_THICKNESS,
            Transparency = 0,
            Visible = false,
            ZIndex = WORLD_LAYER.player,
        }, { pointerEvents = false }))
    end
    for index = count + 1, #nodes.nativeHull do
        nodes.nativeHull[index].Visible = false
    end
end

function Overlay:_getUtilityNodes(index)
    local nodes = self.utilityNodes[index]
    if nodes then
        return nodes
    end

    nodes = {
        marker = self.surface:create("Square", {
            Color = COLORS.accent,
            Filled = false,
            Size = Vector2.new(8, 8),
            Thickness = 1.5,
            Visible = false,
            ZIndex = WORLD_LAYER.utility,
        }, { pointerEvents = false }),
        label = self:_text({
            Center = true,
            Color = COLORS.text,
            Outline = true,
            Size = 12,
            Text = "",
            Visible = false,
            ZIndex = WORLD_LAYER.utilityText,
        }),
    }
    if not self.immediateUtilityZones and self.primitiveSupport.Quad then
        nodes.zones = {}
    end
    self.utilityNodes[index] = nodes
    return nodes
end

function Overlay:_syncUtilityZones(nodes, count)
    if not nodes.zones then
        return
    end
    while #nodes.zones < count do
        table.insert(nodes.zones, self.surface:create("Quad", {
            Color = COLORS.danger,
            Filled = true,
            Transparency = 0.14,
            Visible = false,
            ZIndex = WORLD_LAYER.utilityZone,
        }, { pointerEvents = false }))
    end
    for index = count + 1, #nodes.zones do
        nodes.zones[index].Visible = false
    end
end

function Overlay:_syncUtilityWireframe(nodes, count)
    if not self.primitiveSupport.Line then
        return
    end
    nodes.wireframe = nodes.wireframe or {}
    while #nodes.wireframe < count do
        table.insert(nodes.wireframe, self.surface:create("Line", {
            Color = COLORS.danger,
            Thickness = 2,
            Visible = false,
            ZIndex = WORLD_LAYER.utility,
        }, { pointerEvents = false }))
    end
    for index = count + 1, #nodes.wireframe do
        nodes.wireframe[index].Visible = false
    end
end

function Overlay:_paintChams(renderer)
    local paint = self.chamPaint
    if not paint.enabled then
        return
    end

    for _, observation in ipairs(paint.observations) do
        if observation.previewRenderer ~= "native" and observation.bounds then
            for _, bodyPart in ipairs(observation.bodyParts or {}) do
                local corners = bodyPart.corners
                local eligiblePart = not (observation.previewRenderer == "native"
                    and paint.excludeAccessories == true
                    and bodyPart.accessory == true)
                if eligiblePart and type(corners) == "table" and #corners == 8 then
                    local fallbackColor = observation.previewRenderer == "native"
                        and (observation.tone == "team"
                            and NativeVisualPolicy.COLORS.team
                            or NativeVisualPolicy.COLORS.danger)
                        or playerColor(observation, bodyPart.visible)
                    local color = EspColorPolicy.color(paint.settings, "fill", fallbackColor, observation.tone)
                    for _, cornerIndices in ipairs(BODY_CUBE_FACES) do
                        local pointA = corners[cornerIndices[1]]
                        local pointB = corners[cornerIndices[2]]
                        local pointC = corners[cornerIndices[3]]
                        local pointD = corners[cornerIndices[4]]
                        local transparency = EspColorPolicy.fillAlpha(
                            paint.settings,
                            observation.previewRenderer == "native"
                                and (1 - NATIVE_PREVIEW_FILL_TRANSPARENCY)
                                or BODY_CUBE_OPACITY,
                            observation.tone
                        )
                        renderer.FilledQuad(pointA, pointB, pointC, pointD, color, transparency)
                    end
                end
            end
        end
    end
end

function Overlay:_paintUtilityZones(renderer)
    local paint = self.utilityZonePaint
    if not paint.enabled then
        return
    end

    for _, observation in ipairs(paint.observations) do
        local tone = observation.tone
        local color = tone == "danger" and COLORS.danger
            or (tone == "smoke" and COLORS.secondary or COLORS.signal)
        local opacity = tone == "smoke" and 0.08 or 0.14
        for _, polygon in ipairs(observation.polygons or {}) do
            if type(polygon) == "table" and #polygon == 4 then
                renderer.FilledTriangle(polygon[1], polygon[2], polygon[3], color, opacity)
                renderer.FilledTriangle(polygon[1], polygon[3], polygon[4], color, opacity)
            end
        end
    end
end

function Overlay:_renderUtilities(observations, enabled)
    observations = observations or {}
    self.utilityZonePaint.enabled = enabled == true
    self.utilityZonePaint.observations = observations
    for index, observation in ipairs(observations) do
        local nodes = self:_getUtilityNodes(index)
        local tone = observation.tone
        local color = tone == "danger" and COLORS.danger
            or (tone == "smoke" and COLORS.secondary or COLORS.signal)
        local corners = observation.wireframeCorners
        local wireframeVisible = enabled
            and self.primitiveSupport.Line
            and observation.markerStyle == "wireframeCube"
            and observation.onScreen == true
            and type(corners) == "table"
            and #corners == 8
        local markerVisible = enabled
            and not wireframeVisible
            and observation.onScreen == true
            and observation.screenPosition ~= nil
        local labelPosition
        if markerVisible then
            nodes.marker.Position = observation.screenPosition - Vector2.new(4, 4)
            labelPosition = observation.screenPosition + Vector2.new(0, 8)
        elseif wireframeVisible then
            labelPosition = observation.labelPosition
                or (observation.screenPosition - Vector2.new(0, 16))
        end
        if wireframeVisible then
            self:_syncUtilityWireframe(nodes, #UTILITY_CUBE_EDGES)
            for edgeIndex, cornerIndices in ipairs(UTILITY_CUBE_EDGES) do
                local edge = nodes.wireframe[edgeIndex]
                edge.From = corners[cornerIndices[1]]
                edge.To = corners[cornerIndices[2]]
                edge.Color = color
                edge.Visible = true
            end
        elseif nodes.wireframe then
            for _, edge in ipairs(nodes.wireframe) do
                edge.Visible = false
            end
        end
        nodes.marker.Color = color
        nodes.marker.Visible = markerVisible
        nodes.label.Color = wireframeVisible and COLORS.text or color
        nodes.label.Size = wireframeVisible and 14 or 12
        nodes.label.Text = observation.label or ""
        if wireframeVisible and labelPosition then
            local camera = self.context.getCamera()
            labelPosition = clampCenteredUtilityLabel(
                labelPosition,
                camera and camera.ViewportSize,
                nodes.label.TextBounds
            )
        end
        if labelPosition then
            nodes.label.Position = labelPosition
        end
        nodes.label.Visible = markerVisible or wireframeVisible

        local polygons = enabled and observation.polygons or {}
        if not self.immediateUtilityZones and nodes.zones then
            self:_syncUtilityZones(nodes, #polygons)
            for polygonIndex, polygon in ipairs(polygons) do
                local zone = nodes.zones[polygonIndex]
                local visible = type(polygon) == "table" and #polygon == 4
                if visible then
                    zone.PointA = polygon[1]
                    zone.PointB = polygon[2]
                    zone.PointC = polygon[3]
                    zone.PointD = polygon[4]
                end
                zone.Color = color
                zone.Transparency = tone == "smoke" and 0.08 or 0.14
                zone.Visible = visible
            end
        end
    end

    for index = #observations + 1, #self.utilityNodes do
        setVisible(self.utilityNodes[index], false)
    end
end

function Overlay:render(observations, mousePosition, utilityObservations)
    if self.destroyed or not self.available then
        return
    end

    observations = observations or {}
    self.observations = observations
    local state = self.context.store:Get()
    local settings = state.settings
    self.chamPaint.enabled = self.immediateChams
        and settings.chams == true
        and self.optionSupport.chams ~= false
    self.chamPaint.observations = observations
    self.chamPaint.excludeAccessories = settings.chamsExcludeAccessories == true
    self.chamPaint.settings = settings
    self:_renderBomb(state.bombObservation, settings)
    if self.presentationHost then
        self.presentationHost:setMousePosition(mousePosition)
    end
    local seen = {}

    for _, observation in ipairs(observations) do
        if observation.bounds then
            local nodes = self:_getPlayerNodes(observation.player)
            local bounds = observation.bounds
            local visible = observation.visible == true
            local nativePreview = observation.previewRenderer == "native"
            local nativeColor = observation.tone == "team"
                and NativeVisualPolicy.COLORS.team
                or NativeVisualPolicy.COLORS.danger
            local fallbackColor = nativePreview and nativeColor or playerColor(observation, visible)
            local outlineColor = EspColorPolicy.color(settings, "outline", fallbackColor, observation.tone)
            local nameColor = EspColorPolicy.color(settings, "name", fallbackColor, observation.tone)
            local weaponColor = EspColorPolicy.color(settings, "weapon", fallbackColor, observation.tone)
            local bodyParts = observation.bodyParts or {}
            local perPartPreview = settings.chamsPerPart == true
                or settings.chamsExcludeAccessories == true
            local hullPoints = {}
            seen[observation.player] = true

            self:_syncBodyPartNodes(nodes, #bodyParts)
            for index, bodyPart in ipairs(bodyParts) do
                local cube = nodes.bodyParts[index]
                local corners = bodyPart.corners
                local validCorners = type(corners) == "table" and #corners == 8
                local eligiblePart = not (nativePreview
                    and settings.chamsExcludeAccessories == true
                    and bodyPart.accessory == true)
                local cubeVisible = settings.chams == true
                    and not nativePreview
                    and self.optionSupport.chams ~= false
                    and validCorners
                    and eligiblePart
                local outlineVisible = nativePreview
                    and perPartPreview
                    and settings.boxes == true
                    and validCorners
                    and eligiblePart
                if nativePreview and not perPartPreview and settings.boxes == true
                    and validCorners and eligiblePart
                then
                    for _, point in ipairs(corners) do
                        table.insert(hullPoints, point)
                    end
                end
                local cubeFallback = nativePreview
                    and nativeColor
                    or playerColor(observation, bodyPart.visible)
                local cubeColor = nativePreview
                    and EspColorPolicy.color(settings, "outline", cubeFallback, observation.tone)
                    or EspColorPolicy.color(settings, "fill", cubeFallback, observation.tone)

                if not self.immediateChams then
                    for faceIndex, cornerIndices in ipairs(BODY_CUBE_FACES) do
                        local face = cube.faces[faceIndex]
                        if face and cubeVisible then
                            face.PointA = corners[cornerIndices[1]]
                            face.PointB = corners[cornerIndices[2]]
                            face.PointC = corners[cornerIndices[3]]
                            face.PointD = corners[cornerIndices[4]]
                        end
                        if face then
                            face.Color = cubeColor
                            face.Transparency = EspColorPolicy.fillAlpha(
                                settings,
                                nativePreview and (1 - NATIVE_PREVIEW_FILL_TRANSPARENCY) or BODY_CUBE_OPACITY,
                                observation.tone
                            )
                            face.Visible = cubeVisible
                        end
                    end
                end

                if nativePreview then
                    self:_ensureNativeBodyPartOutlines(cube)
                end
                for faceIndex, outline in ipairs(cube.outlines or {}) do
                    local cornerIndices = BODY_CUBE_FACES[faceIndex]
                    if outlineVisible then
                        outline.PointA = corners[cornerIndices[1]]
                        outline.PointB = corners[cornerIndices[2]]
                        outline.PointC = corners[cornerIndices[3]]
                        outline.PointD = corners[cornerIndices[4]]
                    end
                    outline.Color = cubeColor
                    outline.Visible = outlineVisible
                end
            end

            local hull = nativePreview and not perPartPreview and convexHull(hullPoints) or {}
            self:_syncNativeHull(nodes, #hull)
            for index, line in ipairs(nodes.nativeHull) do
                local visibleHull = index <= #hull and #hull >= 3
                if visibleHull then
                    line.From = hull[index]
                    line.To = hull[index % #hull + 1]
                end
                line.Color = outlineColor
                line.Visible = visibleHull
            end

            nodes.box.Position = bounds.position
            nodes.box.Size = bounds.size
            nodes.box.Color = outlineColor
            nodes.box.Visible = settings.boxes == true and not nativePreview

            nodes.name.Position = Vector2.new(bounds.position.X + bounds.size.X * 0.5, bounds.position.Y - 15)
            nodes.name.Color = nameColor
            nodes.name.Text = observation.player.Name
            nodes.name.Visible = settings.names == true

            local maximumHealth = math.max(observation.maxHealth or 100, 1)
            local healthFraction = math.clamp((observation.health or 0) / maximumHealth, 0, 1)
            local innerHeight = math.max(bounds.size.Y - 2, 0)
            local fillHeight = innerHeight * healthFraction
            nodes.healthTrack.Position = Vector2.new(bounds.position.X - 10, bounds.position.Y)
            nodes.healthTrack.Size = Vector2.new(6, bounds.size.Y)
            nodes.healthTrack.Visible = settings.health == true
            nodes.healthFill.Position =
                Vector2.new(bounds.position.X - 9, bounds.position.Y + 1 + innerHeight - fillHeight)
            nodes.healthFill.Size = Vector2.new(4, fillHeight)
            nodes.healthFill.Color = EspColorPolicy.healthColor(settings, healthFraction, COLORS.danger, COLORS.signal, observation.tone)
            nodes.healthFill.Visible = settings.health == true and fillHeight > 0
            nodes.healthTip.Position = Vector2.new(bounds.position.X - 10, nodes.healthFill.Position.Y - 1)
            nodes.healthTip.Size = Vector2.new(6, 2)
            nodes.healthTip.Visible = settings.health == true and fillHeight > 0
            nodes.healthValue.Position = Vector2.new(
                bounds.position.X,
                bounds.position.Y + bounds.size.Y + 3
            )
            nodes.healthValue.Color = nodes.healthFill.Color
            nodes.healthValue.Text = ("%d HP"):format(math.ceil(observation.health or 0))
            nodes.healthValue.Visible = settings.health == true and fillHeight > 0

            nodes.weapon.Position = Vector2.new(
                bounds.position.X + bounds.size.X * 0.5,
                bounds.position.Y + bounds.size.Y + 18
            )
            nodes.weapon.Text = observation.weapon or ""
            nodes.weapon.Color = weaponColor
            nodes.weapon.Visible = settings.weapon == true and observation.weapon ~= nil
        end
    end

    for player, nodes in pairs(self.playerNodes) do
        if not seen[player] then
            setVisible(nodes, false)
        end
    end
    self:_renderUtilities(utilityObservations, settings.utilityEsp == true)
end

function Overlay:isCaptured()
    return self.captured
end

function Overlay:destroy()
    if self.destroyed then
        return
    end
    self.destroyed = true

    if not self.context.worldOnly and self.context.setInputCaptured then
        self.context.setInputCaptured(false)
    end
    if self.unsubscribe then
        self.unsubscribe()
    end
    if self.worldGui then
        self.worldGui.billboard:Destroy()
        self.worldGui = nil
    end
    if self.chamPaintConnection then
        self.chamPaintConnection:Disconnect()
        self.chamPaintConnection = nil
    end
    if self.utilityPaintConnection then
        self.utilityPaintConnection:Disconnect()
        self.utilityPaintConnection = nil
    end
    if self.presentationHost then
        self.presentationHost:destroy()
        self.presentationHost = nil
    end
    if self.surface then
        self.surface:destroy()
        self.surface = nil
        self.canvas = nil
    end
    table.clear(self.playerNodes)
    table.clear(self.utilityNodes)
end

return Overlay
