local StandardPanels = {}
StandardPanels.__index = StandardPanels

local ACTIVE_CONTROL_LAYER = 206
local CONTENT_WIDTH = 276
local FOV_TRACK_WIDTH = 252
local HITBOX_TRANSPARENCY = 0.01
local RATE_TRACK_WIDTH = 256
local RATE_THUMB_RADIUS = 6

local function setVisible(nodes, visible)
    for _, node in pairs(nodes or {}) do
        if type(node) == "table" and node.Visible ~= nil then
            node.Visible = visible
        elseif type(node) == "table" then
            setVisible(node, visible)
        end
    end
end

local function registerActiveSliderPaint(hit, draw)
    local connected, connection = pcall(function()
        return hit:paintCaptured(ACTIVE_CONTROL_LAYER, function(painter, event)
            draw(painter, event.position)
        end)
    end)
    return connected and connection ~= nil
end

local function setRetainedSliderVisible(state, fill, knob, visible)
    fill.Visible = visible
    knob.Visible = visible
    if visible then
        state.activeSliderVisuals[fill] = nil
        state.activeSliderVisuals[knob] = nil
        state.bridge.refreshVisibility()
    else
        state.activeSliderVisuals[fill] = true
        state.activeSliderVisuals[knob] = true
    end
end

local function paintActiveSlider(painter, track, fillWidth, knobX, knobRadius, fillColor, knobColor)
    painter.FilledRectangle(
        track.Position,
        Vector2.new(math.max(0, fillWidth), 4),
        fillColor,
        1,
        0
    )
    painter.FilledCircle(
        Vector2.new(knobX, track.Position.Y + track.Size.Y * 0.5),
        knobRadius,
        knobColor,
        1,
        32
    )
end

local function slider(state, options)
    return {
        hit = state.bridge.node("Square", options.hit, true),
        track = state.bridge.node("Square", options.track, false),
        fill = state.bridge.node("Square", options.fill, false),
        knob = state.bridge.node("Circle", options.knob, false),
    }
end

local function card(state, options)
    return {
        background = state.bridge.node("Square", options.background, false),
        border = state.bridge.node("Square", options.border, false),
    }
end

function StandardPanels.new(bridge, available)
    local aimControlsSupported = available.silentAim == true
        or available.shotAim == true
        or available.triggerBot == true
        or available.aimSmoothness == true
        or available.headshotRate == true
        or available.missRate == true
    return setmetatable({
        activeSliderVisuals = bridge.activeSliderVisuals,
        aimControlsSupported = aimControlsSupported,
        available = available,
        bridge = bridge,
        controls = bridge.controls,
        groups = {},
        groupById = {},
        optionSupport = bridge.optionSupport or {},
        parents = {},
        rates = {},
        theme = bridge.theme,
    }, StandardPanels)
end

function StandardPanels:aim()
    if self.aimBuilt or not self.aimControlsSupported then
        return
    end
    self.aimBuilt = true
    local state = self
    local controls = state.controls
    local colors = state.theme

    local weaponCard = card(state, {
        background = {
            Color = colors.elevated, Filled = true, Size = Vector2.new(CONTENT_WIDTH, 32), Visible = true, ZIndex = 201,
        },
        border = {
            Color = colors.border, Filled = false, Size = Vector2.new(CONTENT_WIDTH, 32), Thickness = 1, Transparency = 0.72, Visible = true, ZIndex = 202,
        },
    })
    controls.weaponSurface = weaponCard.background
    controls.weaponBorder = weaponCard.border
    controls.weaponLabel = state.bridge.text({
        Color = colors.secondary,
        Size = 13,
        Text = "Weapon",
        ZIndex = 202,
    })
    controls.weaponValue = state.bridge.text({
        Center = true,
        Color = colors.accent,
        Size = 13,
        Text = "Spectating",
        ZIndex = 202,
    })

    local fovCard = card(state, {
        background = {
            Color = colors.elevated, Filled = true, Size = Vector2.new(CONTENT_WIDTH, 86), Visible = true, ZIndex = 201,
        },
        border = {
            Color = colors.border, Filled = false, Size = Vector2.new(CONTENT_WIDTH, 86), Thickness = 1, Transparency = 0.72, Visible = true, ZIndex = 202,
        },
    })
    controls.fovCard = fovCard.background
    controls.fovCardBorder = fovCard.border
    controls.fovLabel = state.bridge.text({
        Color = colors.text,
        Size = 14,
        Text = "FOV",
        ZIndex = 202,
    })
    controls.fovValue = state.bridge.text({
        Center = true,
        Color = colors.secondary,
        Size = 13,
        Text = "",
        ZIndex = 202,
    })
    controls.fovAmount = state.bridge.text({
        Color = colors.text,
        Size = 13,
        Text = "500 px",
        ZIndex = 203,
    })
    controls.fovModeButton = state.bridge.interactive(state.bridge.node("Square", {
        Color = colors.elevated,
        Filled = true,
        Size = Vector2.new(60, 30),
        Visible = true,
        ZIndex = 201,
    }, true))
    controls.fovModeButton:on("click", function()
        local settings = state.bridge.context.store:Get().settings
        state.bridge.context.setOption("fullScreenAim", not settings.fullScreenAim)
    end)
    local fovSlider = slider(state, {
        hit = { Color = colors.panel, Filled = true, Size = Vector2.new(FOV_TRACK_WIDTH, 28), Transparency = HITBOX_TRANSPARENCY, Visible = true, ZIndex = 202 },
        track = { Color = colors.border, Filled = true, Size = Vector2.new(FOV_TRACK_WIDTH, 4), Visible = true, ZIndex = 203 },
        fill = { Color = colors.accent, Filled = true, Visible = true, ZIndex = 204 },
        knob = { Color = colors.text, Filled = true, NumSides = 32, Radius = 7, Visible = true, ZIndex = 205 },
    })
    controls.sliderHit = fovSlider.hit
    controls.sliderTrack = fovSlider.track
    controls.sliderFill = fovSlider.fill
    controls.sliderKnob = fovSlider.knob
    controls.fovCircle = state.bridge.node("Circle", {
        Color = colors.accent,
        Filled = false,
        NumSides = 96,
        Radius = 180,
        Thickness = 1.5,
        Transparency = 0.8,
        Visible = true,
        ZIndex = 50,
    }, false)

    local function setFov(point, persist)
        local current = state.bridge.context.store:Get()
        if current.settings.fullScreenAim then
            return
        end
        local alpha = math.clamp((point.X - state.sliderStartX) / FOV_TRACK_WIDTH, 0, 1)
        local settings = current.settings
        state.bridge.context.setFov(
            settings.minimumFov + (settings.maximumFov - settings.minimumFov) * alpha,
            persist
        )
    end
    local function fovSliderEnabled()
        return state.bridge.context.store:Get().settings.fullScreenAim ~= true
    end
    local fovActivePaint = registerActiveSliderPaint(controls.sliderHit, function(painter, point)
        if not fovSliderEnabled() then
            return
        end
        local alpha = math.clamp((point.X - state.sliderStartX) / FOV_TRACK_WIDTH, 0, 1)
        local knobX = state.sliderStartX + FOV_TRACK_WIDTH * alpha
        paintActiveSlider(
            painter,
            controls.sliderTrack,
            FOV_TRACK_WIDTH * alpha,
            knobX,
            7,
            colors.accent,
            colors.text
        )
    end)
    controls.sliderHit:on("pointerdown", function(_node, point)
        setFov(point, false)
        if fovActivePaint and fovSliderEnabled() then
            setRetainedSliderVisible(state, controls.sliderFill, controls.sliderKnob, false)
        end
    end)
    controls.sliderHit:on("drag", function(_node, point)
        setFov(point, false)
        if fovActivePaint and fovSliderEnabled() then
            setRetainedSliderVisible(state, controls.sliderFill, controls.sliderKnob, false)
        end
    end)
    controls.sliderHit:on("pointerup", function(_node, point)
        setFov(point, true)
        if fovActivePaint then
            setRetainedSliderVisible(state, controls.sliderFill, controls.sliderKnob, true)
        end
    end)
end

function StandardPanels:rate(id, label)
    if not self.available[id] or self.controls.rates[id] then
        return
    end
    local state = self
    local colors = state.theme
    local control = {
        background = state.bridge.node("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(CONTENT_WIDTH, 54),
            Visible = true,
            ZIndex = 201,
        }, false),
        border = state.bridge.node("Square", {
            Color = colors.border,
            Filled = false,
            Size = Vector2.new(CONTENT_WIDTH, 54),
            Thickness = 1,
            Transparency = 0.72,
            Visible = true,
            ZIndex = 202,
        }, false),
        slider = slider(state, {
            hit = { Color = colors.panel, Filled = true, Size = Vector2.new(RATE_TRACK_WIDTH, 28), Transparency = HITBOX_TRANSPARENCY, Visible = true, ZIndex = 202 },
            track = { Color = colors.border, Filled = true, Size = Vector2.new(RATE_TRACK_WIDTH, 4), Visible = true, ZIndex = 203 },
            fill = { Color = colors.accent, Filled = true, Visible = true, ZIndex = 204 },
            knob = { Color = colors.text, Filled = true, NumSides = 32, Radius = RATE_THUMB_RADIUS, Visible = true, ZIndex = 205 },
        }),
        label = state.bridge.text({
            Color = colors.text,
            Size = 13,
            Text = label,
            ZIndex = 203,
        }),
        value = state.bridge.text({
            Center = true,
            Color = colors.secondary,
            Size = 12,
            Text = "0%",
            ZIndex = 203,
        }),
        valueSurface = state.bridge.node("Square", {
            Color = colors.panel,
            Filled = true,
            Size = Vector2.new(42, 24),
            Visible = true,
            ZIndex = 202,
        }, false),
        valueBorder = state.bridge.node("Square", {
            Color = colors.border,
            Filled = false,
            Size = Vector2.new(42, 24),
            Thickness = 1,
            Transparency = 0.72,
            Visible = true,
            ZIndex = 203,
        }, false),
    }
    control.hit = control.slider.hit
    control.track = control.slider.track
    control.fill = control.slider.fill
    control.knob = control.slider.knob
    local activePaint = registerActiveSliderPaint(control.hit, function(painter, point)
        local alpha = math.clamp((point.X - control.hit.Position.X) / RATE_TRACK_WIDTH, 0, 1)
        local thumbTravel = RATE_TRACK_WIDTH - RATE_THUMB_RADIUS * 2
        local thumbX = control.track.Position.X + RATE_THUMB_RADIUS + thumbTravel * alpha
        paintActiveSlider(
            painter,
            control.track,
            thumbX - control.track.Position.X,
            thumbX,
            RATE_THUMB_RADIUS,
            colors.accent,
            colors.text
        )
    end)
    local function setRate(point, persist)
        local alpha = math.clamp((point.X - control.hit.Position.X) / RATE_TRACK_WIDTH, 0, 1)
        state.bridge.context.setRate(id, math.round(alpha * 100), persist)
    end
    control.hit:on("pointerdown", function(_node, point)
        setRate(point, false)
        if activePaint then
            setRetainedSliderVisible(state, control.fill, control.knob, false)
        end
    end)
    control.hit:on("drag", function(_node, point)
        setRate(point, false)
        if activePaint then
            setRetainedSliderVisible(state, control.fill, control.knob, false)
        end
    end)
    control.hit:on("pointerup", function(_node, point)
        setRate(point, true)
        if activePaint then
            setRetainedSliderVisible(state, control.fill, control.knob, true)
        end
    end)
    state.controls.rates[id] = control
    table.insert(state.rates, id)
end

function StandardPanels:section(id, label, lineOffset, includesRates)
    assert(not self.groupById[id], "Duplicate presentation section: " .. id)
    local group = {
        id = id,
        label = label,
        lineOffset = lineOffset or 70,
        includesRates = includesRates == true,
        maxRow = 0,
        rows = {},
    }
    self.groupById[id] = group
    table.insert(self.groups, group)
end

local function buildSection(state, group)
    if state.controls.sections[group.id] then
        return
    end
    state.controls.sections[group.id] = {
        label = state.bridge.text({
            Color = state.theme.accent,
            Size = 11,
            Text = group.label,
            ZIndex = 203,
        }),
        line = state.bridge.node("Square", {
            Color = state.theme.border,
            Filled = true,
            Size = Vector2.new(218, 1),
            Visible = true,
            ZIndex = 202,
        }, false),
    }
end

function StandardPanels:option(sectionId, rowIndex, id, label, parent)
    if not self.available[id] then
        return
    end
    local state = self
    local group = assert(state.groupById[sectionId], "Unknown presentation section: " .. sectionId)
    buildSection(state, group)
    group.rows[rowIndex] = group.rows[rowIndex] or {}
    table.insert(group.rows[rowIndex], id)
    group.maxRow = math.max(group.maxRow, rowIndex)
    state.parents[id] = parent

    local colors = state.theme
    local row = state.bridge.interactive(state.bridge.node("Square", {
        Color = colors.elevated,
        Filled = true,
        Size = Vector2.new(134, 30),
        Visible = true,
        ZIndex = 202,
    }, true))
    local labelNode = state.bridge.text({
        Color = colors.text,
        Size = 13,
        Text = label,
        ZIndex = 203,
    })
    local value = state.bridge.text({
        Center = true,
        Color = colors.secondary,
        Size = 12,
        Text = "Off",
        ZIndex = 203,
    })
    local function switchNode(kind, properties)
        return state.bridge.node(kind, properties, false)
    end
    local outline = switchNode("Square", {
        Color = colors.border,
        Filled = false,
        Size = Vector2.new(134, 30),
        Thickness = 1,
        Transparency = 0.72,
        Visible = true,
        ZIndex = 203,
    })
    local switchShadowTrack = switchNode("Square", {
        Color = colors.panelShadow, Filled = true, Size = Vector2.new(18, 22), Visible = true, ZIndex = 203,
    })
    local switchShadowLeft = switchNode("Circle", {
        Color = colors.panelShadow, Filled = true, NumSides = 24, Radius = 11, Visible = true, ZIndex = 203,
    })
    local switchShadowRight = switchNode("Circle", {
        Color = colors.panelShadow, Filled = true, NumSides = 24, Radius = 11, Visible = true, ZIndex = 203,
    })
    local switchTrack = switchNode("Square", {
        Color = colors.border, Filled = true, Size = Vector2.new(18, 22), Visible = true, ZIndex = 204,
    })
    local switchLeft = switchNode("Circle", {
        Color = colors.border, Filled = true, NumSides = 24, Radius = 11, Visible = true, ZIndex = 204,
    })
    local switchRight = switchNode("Circle", {
        Color = colors.border, Filled = true, NumSides = 24, Radius = 11, Visible = true, ZIndex = 204,
    })
    local switchFillTrack = switchNode("Square", {
        Color = colors.elevated, Filled = true, Size = Vector2.new(18, 18), Visible = true, ZIndex = 205,
    })
    local switchFillLeft = switchNode("Circle", {
        Color = colors.elevated, Filled = true, NumSides = 24, Radius = 9, Visible = true, ZIndex = 205,
    })
    local switchFillRight = switchNode("Circle", {
        Color = colors.elevated, Filled = true, NumSides = 24, Radius = 9, Visible = true, ZIndex = 205,
    })
    local switchKnobRim = switchNode("Circle", {
        Color = colors.border, Filled = true, NumSides = 24, Radius = 9.5, Visible = true, ZIndex = 206,
    })
    local switchKnob = switchNode("Circle", {
        Color = colors.text, Filled = true, NumSides = 24, Radius = 8.5, Visible = true, ZIndex = 207,
    })
    local marker
    if parent then
        marker = switchNode("Square", {
            Color = colors.border,
            Filled = true,
            Size = Vector2.new(2, 14),
            Visible = true,
            ZIndex = 203,
        })
    end
    row:on("click", function()
        if state.optionSupport[id] == false then
            return
        end
        local current = state.bridge.context.store:Get()
        state.bridge.context.setOption(id, not current.settings[id])
    end)
    state.controls.options[id] = {
        outline = outline,
        row = row,
        label = labelNode,
        marker = marker,
        switch = {
            fillLeft = switchFillLeft,
            fillRight = switchFillRight,
            fillTrack = switchFillTrack,
            knob = switchKnob,
            knobRim = switchKnobRim,
            left = switchLeft,
            right = switchRight,
            shadowLeft = switchShadowLeft,
            shadowRight = switchShadowRight,
            shadowTrack = switchShadowTrack,
            track = switchTrack,
        },
        value = value,
    }
end

function StandardPanels:layout(x, y, cursor)
    local controls = self.controls
    if self.aimBuilt then
        controls.weaponSurface.Position = Vector2.new(x + 12, y + 54)
        controls.weaponBorder.Position = controls.weaponSurface.Position
        controls.weaponLabel.Position = Vector2.new(x + 24, y + 64)
        controls.weaponValue.Position = Vector2.new(x + 244, y + 64)
        controls.fovCard.Position = Vector2.new(x + 12, y + 92)
        controls.fovCardBorder.Position = controls.fovCard.Position
        controls.fovLabel.Position = Vector2.new(x + 24, y + 102)
        controls.fovAmount.Position = Vector2.new(x + 248, y + 102)
        controls.fovModeButton.Position = Vector2.new(x + 24, y + 140)
        controls.fovValue.Position = Vector2.new(x + 54, y + 145)
        self.sliderStartX = x + 24
        controls.sliderHit.Position = Vector2.new(self.sliderStartX, y + 114)
        controls.sliderTrack.Position = Vector2.new(self.sliderStartX, y + 127)
        controls.sliderFill.Position = controls.sliderTrack.Position
        cursor = y + 184
    end

    for _, group in ipairs(self.groups) do
        local section = controls.sections[group.id]
        if section then
            section.label.Position = Vector2.new(x + 12, cursor)
            section.line.Position = Vector2.new(x + group.lineOffset, cursor + 7)
            cursor = cursor + 22
        end

        if group.includesRates then
            for _, id in ipairs(self.rates) do
                local control = controls.rates[id]
                control.background.Position = Vector2.new(x + 12, cursor)
                control.border.Position = control.background.Position
                control.label.Position = Vector2.new(x + 22, cursor + 8)
                control.valueSurface.Visible = false
                control.valueBorder.Visible = false
                control.value.Position = Vector2.new(x + 258, cursor + 8)
                control.hit.Position = Vector2.new(x + 22, cursor + 22)
                control.track.Position = Vector2.new(x + 22, cursor + 35)
                control.fill.Position = control.track.Position
                cursor = cursor + 58
            end
        end

        for rowIndex = 1, group.maxRow do
            local optionRow = group.rows[rowIndex] or {}
            local availableCount = 0
            for _, optionName in ipairs(optionRow) do
                if controls.options[optionName] then
                    availableCount = availableCount + 1
                end
            end
            local column = 0
            local rowWidth = availableCount == 1 and CONTENT_WIDTH or 134
            for _, optionName in ipairs(optionRow) do
                local option = controls.options[optionName]
                if option then
                    column = column + 1
                    local rowX = x + 12 + (column - 1) * 142
                    option.row.Position = Vector2.new(rowX, cursor)
                    option.row.Size = Vector2.new(rowWidth, 32)
                    option.outline.Position = option.row.Position
                    option.outline.Size = option.row.Size
                    if option.marker then
                        option.marker.Position = Vector2.new(rowX + 10, cursor + 9)
                    end
                    option.label.Position = Vector2.new(rowX + (option.marker and 24 or 12), cursor + 10)
                    option.value.Position = Vector2.new(rowX + rowWidth - 60, cursor + 10)
                    local switchX = rowX + rowWidth - 30
                    local switchY = cursor + 16
                    option.switch.shadowTrack.Position = Vector2.new(switchX - 9, switchY - 10)
                    option.switch.shadowLeft.Position = Vector2.new(switchX - 9, switchY + 1)
                    option.switch.shadowRight.Position = Vector2.new(switchX + 9, switchY + 1)
                    option.switch.track.Position = Vector2.new(switchX - 9, switchY - 11)
                    option.switch.left.Position = Vector2.new(switchX - 9, switchY)
                    option.switch.right.Position = Vector2.new(switchX + 9, switchY)
                    option.switch.fillTrack.Position = Vector2.new(switchX - 9, switchY - 9)
                    option.switch.fillLeft.Position = Vector2.new(switchX - 9, switchY)
                    option.switch.fillRight.Position = Vector2.new(switchX + 9, switchY)
                end
            end
            if column > 0 then
                cursor = cursor + 36
            end
        end
        if section then
            cursor = cursor + 6
        end
    end
    return cursor
end

function StandardPanels:setVisible(visible)
    local controls = self.controls
    if self.aimBuilt then
        for _, name in ipairs({
            "weaponLabel",
            "weaponSurface",
            "weaponBorder",
            "weaponValue",
            "fovCard",
            "fovCardBorder",
            "fovLabel",
            "fovAmount",
            "fovValue",
            "fovModeButton",
            "sliderHit",
            "sliderTrack",
            "sliderFill",
            "sliderKnob",
        }) do
            controls[name].Visible = visible
        end
    end
    for _, option in pairs(controls.options) do
        setVisible(option, visible)
        option.value.Visible = visible
            and (option.value.Text == "N/A" or option.value.Text == "Standby")
    end
    for _, rate in pairs(controls.rates) do
        setVisible(rate, visible)
    end
    for _, group in ipairs(self.groups) do
        if controls.sections[group.id] then
            setVisible(controls.sections[group.id], visible)
        end
    end
end

function StandardPanels:render(current)
    local settings = current.settings
    local controls = self.controls
    local colors = self.theme
    if self.aimBuilt then
        controls.weaponValue.Text = current.activeWeapon or "Spectating"
        controls.weaponValue.Color = current.activeWeapon and colors.accent or colors.secondary
    end

    for optionName, option in pairs(controls.options) do
        local enabled = settings[optionName] == true
        local parent = self.parents[optionName]
        local supported = self.optionSupport[optionName] ~= false
        local available = supported and (not parent or settings[parent] == true)
        self.bridge.setControlColor(option.row, available and colors.elevated or colors.panel)
        option.label.Color = available and colors.text or colors.secondary
        option.outline.Color = colors.border
        option.outline.Transparency = available and 0.72 or 0.42
        local switchColor = available and enabled and colors.toggleActive or colors.border
        option.switch.track.Color = switchColor
        option.switch.left.Color = switchColor
        option.switch.right.Color = switchColor
        option.switch.fillTrack.Color = switchColor
        option.switch.fillLeft.Color = switchColor
        option.switch.fillRight.Color = switchColor
        option.switch.knobRim.Color = available and colors.border or colors.panel
        option.switch.knob.Color = available and colors.text or colors.secondary
        local switchCenterX = option.switch.track.Position.X + 9
        local switchCenterY = option.switch.left.Position.Y
        local knobPosition = Vector2.new(switchCenterX + (enabled and 9 or -9), switchCenterY)
        option.switch.knobRim.Position = knobPosition
        option.switch.knob.Position = knobPosition
        if option.marker then
            option.marker.Color = available and colors.accent or colors.border
        end
        option.value.Color = available and enabled and colors.accent or colors.secondary
        option.value.Text = not supported and "N/A"
            or (not available and enabled and "Standby" or "")
        option.value.Visible = current.menuVisible ~= false
            and (option.value.Text == "N/A" or option.value.Text == "Standby")
    end

    for _, id in ipairs(self.rates) do
        local control = controls.rates[id]
        local value = math.clamp(settings[id] or 0, 0, 100)
        local alpha = value / 100
        local thumbTravel = RATE_TRACK_WIDTH - RATE_THUMB_RADIUS * 2
        local thumbX = control.track.Position.X + RATE_THUMB_RADIUS + thumbTravel * alpha
        control.fill.Size = Vector2.new(math.max(0, thumbX - control.track.Position.X), 4)
        control.knob.Position = Vector2.new(thumbX, control.track.Position.Y + 2)
        control.value.Text = ("%d%%"):format(math.round(value))
    end

    if self.aimBuilt then
        local alpha = (settings.fov - settings.minimumFov) / (settings.maximumFov - settings.minimumFov)
        controls.sliderFill.Size = Vector2.new(FOV_TRACK_WIDTH * alpha, 4)
        controls.sliderKnob.Position = Vector2.new(
            self.sliderStartX + FOV_TRACK_WIDTH * alpha,
            controls.sliderTrack.Position.Y + 2
        )
        self.bridge.setControlColor(
            controls.fovModeButton,
            settings.fullScreenAim and colors.accentSurface or colors.elevated
        )
        controls.sliderFill.Color = settings.fullScreenAim and colors.border or colors.accent
        controls.sliderKnob.Color = settings.fullScreenAim and colors.secondary or colors.text
        controls.fovValue.Color = settings.fullScreenAim and colors.accent or colors.secondary
        controls.fovLabel.Text = "FOV"
        controls.fovAmount.Text = ("%d px"):format(math.round(settings.fov))
        controls.fovValue.Text = "Fullscreen"
        controls.fovCircle.Radius = settings.fov
        controls.fovCircle.Visible = self.aimControlsSupported
            and settings.fovCircle ~= false
            and not settings.fullScreenAim
    end
end

function StandardPanels:setMousePosition(position)
    if self.controls.fovCircle then
        self.controls.fovCircle.Position = position
    end
end

function StandardPanels:destroy() end

return StandardPanels
