local PresentationHost = {}
PresentationHost.__index = PresentationHost

local PRIVATE = setmetatable({}, { __mode = "k" })
local ACTIVE_CONTROL_LAYER = 206
local CONTENT_WIDTH = 276
local FOV_TRACK_WIDTH = 252
local HITBOX_TRANSPARENCY = 0.01
local RATE_TRACK_WIDTH = 256
local RATE_THUMB_RADIUS = 6
local PLOT_OWNER_VALUE_LIMIT = 22
local PLOT_SAVE_VALUE_LIMIT = 24
local COSMETIC_WEAPON_CONTROLS = {
    weaponBackground = true,
    weaponName = true,
    weaponNext = true,
    weaponNextLabel = true,
    weaponPrevious = true,
    weaponPreviousLabel = true,
}

local function private(host)
    return assert(PRIVATE[host], "Presentation host is unavailable")
end

local function setVisible(nodes, visible)
    for _, node in pairs(nodes or {}) do
        if type(node) == "table" and node.Visible ~= nil then
            node.Visible = visible
        elseif type(node) == "table" then
            setVisible(node, visible)
        end
    end
end

local function compactText(value, limit)
    value = tostring(value or "")
    if #value <= limit then
        return value
    end
    return value:sub(1, math.max(1, limit - 3)) .. "..."
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
        state.refreshVisibility()
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
    local surface = state.surface
    return {
        hit = surface:create("Square", options.hit, { pointerEvents = true }),
        track = surface:create("Square", options.track, { pointerEvents = false }),
        fill = surface:create("Square", options.fill, { pointerEvents = false }),
        knob = surface:create("Circle", options.knob, { pointerEvents = false }),
    }
end

local function card(state, options)
    local surface = state.surface
    return {
        background = surface:create("Square", options.background, { pointerEvents = false }),
        border = surface:create("Square", options.border, { pointerEvents = false }),
    }
end

function PresentationHost.new(bridge)
    assert(type(bridge) == "table", "Presentation host requires an Overlay bridge")
    assert(type(bridge.text) == "function", "Presentation host requires text construction")
    assert(type(bridge.interactive) == "function", "Presentation host requires control construction")
    assert(type(bridge.setControlColor) == "function", "Presentation host requires control coloring")
    assert(type(bridge.layout) == "function", "Presentation host requires Overlay layout")
    assert(bridge.surface and bridge.controls and bridge.context and bridge.theme)

    local available = {}
    for key, value in pairs(bridge.capabilities or {}) do
        local name = type(key) == "number" and value or key
        if value ~= false then
            available[name] = true
        end
    end

    local host = setmetatable({}, PresentationHost)
    PRIVATE[host] = {
        activeSliderVisuals = bridge.activeSliderVisuals,
        aimControlsSupported = available.silentAim == true
            or available.shotAim == true
            or available.triggerBot == true
            or available.aimSmoothness == true
            or available.headshotRate == true
            or available.missRate == true,
        available = available,
        bridge = bridge,
        context = bridge.context,
        controls = bridge.controls,
        cosmeticsSupported = bridge.cosmeticsSupported,
        groups = {},
        groupById = {},
        nativeConnections = {},
        optionSupport = bridge.optionSupport or {},
        parents = {},
        plotDropdownItems = {},
        plotDropdownOpen = false,
        plotSaveName = "",
        rates = {},
        selectedPlotOwner = nil,
        surface = bridge.surface,
        theme = bridge.theme,
    }
    PRIVATE[host].refreshVisibility = function()
        host:setVisible(bridge.context.store:Get().menuVisible ~= false)
    end
    bridge.controls.rates = {}
    bridge.controls.sections = {}
    bridge.controls.options = {}
    return host
end

function PresentationHost.mount(bridge, presentation)
    assert(type(presentation) == "table" and type(presentation.mount) == "function")
    local host = PresentationHost.new(bridge)
    presentation.mount(host)
    return host
end

function PresentationHost:supports(name)
    return private(self).available[name] == true
end

function PresentationHost:read()
    return private(self).context.store:Get()
end

function PresentationHost:patch(patch)
    return private(self).context.store:Patch(patch)
end

function PresentationHost:action(name, ...)
    local callback = private(self).context[name]
    assert(type(callback) == "function", "Unknown presentation action: " .. tostring(name))
    return callback(...)
end

function PresentationHost:aim()
    local state = private(self)
    if state.aimBuilt then
        return
    end
    state.aimBuilt = true
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
    controls.fovModeButton = state.bridge.interactive(state.surface:create("Square", {
        Color = colors.elevated,
        Filled = true,
        Size = Vector2.new(60, 30),
        Visible = true,
        ZIndex = 201,
    }))
    controls.fovModeButton:on("click", function()
        local settings = state.context.store:Get().settings
        state.context.setOption("fullScreenAim", not settings.fullScreenAim)
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
    controls.fovCircle = state.surface:create("Circle", {
        Color = colors.accent,
        Filled = false,
        NumSides = 96,
        Radius = 180,
        Thickness = 1.5,
        Transparency = 0.8,
        Visible = true,
        ZIndex = 50,
    }, { pointerEvents = false })

    local function setFov(point, persist)
        local current = state.context.store:Get()
        if current.settings.fullScreenAim then
            return
        end
        local alpha = math.clamp((point.X - state.sliderStartX) / FOV_TRACK_WIDTH, 0, 1)
        local settings = current.settings
        state.context.setFov(
            settings.minimumFov + (settings.maximumFov - settings.minimumFov) * alpha,
            persist
        )
    end
    local function fovSliderEnabled()
        return state.context.store:Get().settings.fullScreenAim ~= true
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

function PresentationHost:rate(id, label)
    local state = private(self)
    if not state.available[id] or state.controls.rates[id] then
        return
    end
    local colors = state.theme
    local control = {
        background = state.surface:create("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(CONTENT_WIDTH, 54),
            Visible = true,
            ZIndex = 201,
        }, { pointerEvents = false }),
        border = state.surface:create("Square", {
            Color = colors.border,
            Filled = false,
            Size = Vector2.new(CONTENT_WIDTH, 54),
            Thickness = 1,
            Transparency = 0.72,
            Visible = true,
            ZIndex = 202,
        }, { pointerEvents = false }),
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
        valueSurface = state.surface:create("Square", {
            Color = colors.panel,
            Filled = true,
            Size = Vector2.new(42, 24),
            Visible = true,
            ZIndex = 202,
        }, { pointerEvents = false }),
        valueBorder = state.surface:create("Square", {
            Color = colors.border,
            Filled = false,
            Size = Vector2.new(42, 24),
            Thickness = 1,
            Transparency = 0.72,
            Visible = true,
            ZIndex = 203,
        }, { pointerEvents = false }),
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
        state.context.setRate(id, math.round(alpha * 100), persist)
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

function PresentationHost:section(id, label)
    local state = private(self)
    assert(not state.groupById[id], "Duplicate presentation section: " .. id)
    local group = {
        id = id,
        label = label,
        maxRow = 0,
        rows = {},
    }
    state.groupById[id] = group
    table.insert(state.groups, group)
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
        line = state.surface:create("Square", {
            Color = state.theme.border,
            Filled = true,
            Size = Vector2.new(218, 1),
            Visible = true,
            ZIndex = 202,
        }, { pointerEvents = false }),
    }
end

function PresentationHost:option(sectionId, rowIndex, id, label, parent)
    local state = private(self)
    if not state.available[id] then
        return
    end
    local group = assert(state.groupById[sectionId], "Unknown presentation section: " .. sectionId)
    buildSection(state, group)
    group.rows[rowIndex] = group.rows[rowIndex] or {}
    table.insert(group.rows[rowIndex], id)
    group.maxRow = math.max(group.maxRow, rowIndex)
    state.parents[id] = parent

    local colors = state.theme
    local row = state.bridge.interactive(state.surface:create("Square", {
        Color = colors.elevated,
        Filled = true,
        Size = Vector2.new(134, 30),
        Visible = true,
        ZIndex = 202,
    }))
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
    local outline = state.surface:create("Square", {
        Color = colors.border,
        Filled = false,
        Size = Vector2.new(134, 30),
        Thickness = 1,
        Transparency = 0.72,
        Visible = true,
        ZIndex = 203,
    }, { pointerEvents = false })
    local switchShadowTrack = state.surface:create("Square", {
        Color = colors.panelShadow, Filled = true, Size = Vector2.new(18, 22), Visible = true, ZIndex = 203,
    }, { pointerEvents = false })
    local switchShadowLeft = state.surface:create("Circle", {
        Color = colors.panelShadow, Filled = true, NumSides = 24, Radius = 11, Visible = true, ZIndex = 203,
    }, { pointerEvents = false })
    local switchShadowRight = state.surface:create("Circle", {
        Color = colors.panelShadow, Filled = true, NumSides = 24, Radius = 11, Visible = true, ZIndex = 203,
    }, { pointerEvents = false })
    local switchTrack = state.surface:create("Square", {
        Color = colors.border, Filled = true, Size = Vector2.new(18, 22), Visible = true, ZIndex = 204,
    }, { pointerEvents = false })
    local switchLeft = state.surface:create("Circle", {
        Color = colors.border, Filled = true, NumSides = 24, Radius = 11, Visible = true, ZIndex = 204,
    }, { pointerEvents = false })
    local switchRight = state.surface:create("Circle", {
        Color = colors.border, Filled = true, NumSides = 24, Radius = 11, Visible = true, ZIndex = 204,
    }, { pointerEvents = false })
    local switchFillTrack = state.surface:create("Square", {
        Color = colors.elevated, Filled = true, Size = Vector2.new(18, 18), Visible = true, ZIndex = 205,
    }, { pointerEvents = false })
    local switchFillLeft = state.surface:create("Circle", {
        Color = colors.elevated, Filled = true, NumSides = 24, Radius = 9, Visible = true, ZIndex = 205,
    }, { pointerEvents = false })
    local switchFillRight = state.surface:create("Circle", {
        Color = colors.elevated, Filled = true, NumSides = 24, Radius = 9, Visible = true, ZIndex = 205,
    }, { pointerEvents = false })
    local switchKnobRim = state.surface:create("Circle", {
        Color = colors.border, Filled = true, NumSides = 24, Radius = 9.5, Visible = true, ZIndex = 206,
    }, { pointerEvents = false })
    local switchKnob = state.surface:create("Circle", {
        Color = colors.text, Filled = true, NumSides = 24, Radius = 8.5, Visible = true, ZIndex = 207,
    }, { pointerEvents = false })
    local marker
    if parent then
        marker = state.surface:create("Square", {
            Color = colors.border,
            Filled = true,
            Size = Vector2.new(2, 14),
            Visible = true,
            ZIndex = 203,
        }, { pointerEvents = false })
    end
    row:on("click", function()
        if state.optionSupport[id] == false then
            return
        end
        local current = state.context.store:Get()
        state.context.setOption(id, not current.settings[id])
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

local function setPlotSaveName(state, saveName)
    state.plotSaveName = tostring(saveName or "")
    local controls = state.controls.plotCopy
    if controls then
        controls.saveValue.Text = state.plotSaveName == ""
                and "Enter save name"
            or compactText(state.plotSaveName, PLOT_SAVE_VALUE_LIMIT)
        controls.saveValue.Color =
            state.plotSaveName == "" and state.theme.secondary or state.theme.text
    end
end

local function clearPlotDropdown(state)
    for _, item in ipairs(state.plotDropdownItems) do
        item.row:destroy()
        item.label:destroy()
    end
    table.clear(state.plotDropdownItems)
end

local function selectPlotOwner(state, ownerName)
    local previousDefault = state.selectedPlotOwner
            and ("copy_" .. state.selectedPlotOwner)
        or ""
    state.selectedPlotOwner = ownerName
    local controls = state.controls.plotCopy
    controls.ownerValue.Text = compactText(ownerName, PLOT_OWNER_VALUE_LIMIT)
    controls.ownerValue.Color = state.theme.text
    if state.plotSaveName == "" or state.plotSaveName == previousDefault then
        setPlotSaveName(state, "copy_" .. ownerName)
        if controls.saveInput then
            controls.saveInput.Text = state.plotSaveName
        end
    end
end

local function setPlotDropdownOpen(state, open)
    local controls = state.controls.plotCopy
    if not controls then
        return
    end

    clearPlotDropdown(state)
    state.plotDropdownOpen = open == true
    controls.ownerIndicator.Text = state.plotDropdownOpen and "^" or "v"
    if not state.plotDropdownOpen then
        return
    end

    local succeeded, owners = pcall(state.plotActions.listOwners)
    if not succeeded or type(owners) ~= "table" or #owners == 0 then
        state.plotDropdownOpen = false
        controls.ownerIndicator.Text = "v"
        controls.ownerValue.Text = "No player plots"
        controls.ownerValue.Color = state.theme.danger
        state.plotActions.reportError("No other player plots are available")
        return
    end

    if not table.find(owners, state.selectedPlotOwner) then
        selectPlotOwner(state, owners[1])
    end
    for _, ownerName in ipairs(owners) do
        local row = state.bridge.interactive(state.surface:create("Square", {
            Color = ownerName == state.selectedPlotOwner
                    and state.theme.accentSurface
                or state.theme.elevated,
            Filled = true,
            Size = Vector2.new(CONTENT_WIDTH, 26),
            Visible = true,
            ZIndex = 212,
        }))
        local label = state.bridge.text({
            Color = ownerName == state.selectedPlotOwner and state.theme.accent or state.theme.text,
            Size = 12,
            Text = compactText(ownerName, PLOT_OWNER_VALUE_LIMIT),
            ZIndex = 213,
        })
        row:on("click", function()
            selectPlotOwner(state, ownerName)
            setPlotDropdownOpen(state, false)
        end)
        table.insert(state.plotDropdownItems, {
            label = label,
            row = row,
        })
    end
    state.bridge.layout()
end

function PresentationHost:plotCopy(actions)
    local state = private(self)
    if not state.available.plotCopy or state.controls.plotCopy then
        return
    end
    assert(type(actions) == "table", "Plot copy presentation requires game-owned actions")
    assert(type(actions.listOwners) == "function", "Plot copy presentation requires owner discovery")
    assert(type(actions.primary) == "function", "Plot copy presentation requires a primary action")
    assert(type(actions.reportError) == "function", "Plot copy presentation requires error reporting")
    assert(type(actions.secondary) == "function", "Plot copy presentation requires a secondary action")
    state.plotActions = actions
    local colors = state.theme
    state.controls.sections.plotCopy = {
        label = state.bridge.text({
            Color = colors.accent,
            Size = 11,
            Text = "PLOT COPY",
            ZIndex = 203,
        }),
        line = state.surface:create("Square", {
            Color = colors.border,
            Filled = true,
            Size = Vector2.new(206, 1),
            Visible = true,
            ZIndex = 202,
        }, { pointerEvents = false }),
    }
    local plotCopy = {
        ownerButton = state.bridge.interactive(state.surface:create("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(CONTENT_WIDTH, 30),
            Visible = true,
            ZIndex = 202,
        })),
        ownerIndicator = state.bridge.text({
            Center = true, Color = colors.secondary, Size = 12, Text = "v", ZIndex = 204,
        }),
        ownerLabel = state.bridge.text({
            Color = colors.secondary, Size = 11, Text = "PLAYER", ZIndex = 203,
        }),
        ownerOutline = state.surface:create("Square", {
            Color = colors.border,
            Filled = false,
            Size = Vector2.new(CONTENT_WIDTH, 30),
            Thickness = 1,
            Transparency = 0.72,
            Visible = true,
            ZIndex = 203,
        }, { pointerEvents = false }),
        ownerValue = state.bridge.text({
            Color = colors.secondary, Size = 12, Text = "Select a plot", ZIndex = 203,
        }),
        saveButton = state.bridge.interactive(state.surface:create("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(CONTENT_WIDTH, 30),
            Visible = true,
            ZIndex = 202,
        })),
        saveLabel = state.bridge.text({
            Color = colors.secondary, Size = 11, Text = "SAVE", ZIndex = 203,
        }),
        saveOutline = state.surface:create("Square", {
            Color = colors.border,
            Filled = false,
            Size = Vector2.new(CONTENT_WIDTH, 30),
            Thickness = 1,
            Transparency = 0.72,
            Visible = true,
            ZIndex = 203,
        }, { pointerEvents = false }),
        saveValue = state.bridge.text({
            Color = colors.secondary, Size = 12, Text = "Enter save name", ZIndex = 203,
        }),
        actionButton = state.bridge.interactive(state.surface:create("Square", {
            Color = colors.accentSurface,
            Filled = true,
            Size = Vector2.new(CONTENT_WIDTH, 30),
            Visible = true,
            ZIndex = 202,
        })),
        actionLabel = state.bridge.text({
            Center = true, Color = colors.accent, Size = 13, Text = "Copy & Save", ZIndex = 203,
        }),
        secondaryButton = state.bridge.interactive(state.surface:create("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(CONTENT_WIDTH, 26),
            Visible = false,
            ZIndex = 202,
        })),
        secondaryLabel = state.bridge.text({
            Center = true, Color = colors.secondary, Size = 12, Text = "", Visible = false, ZIndex = 203,
        }),
        progressPhase = state.bridge.text({
            Color = colors.secondary, Size = 11, Text = "Ready", ZIndex = 203,
        }),
        progressContext = state.bridge.text({
            Color = colors.secondary, Size = 10, Text = "", ZIndex = 203,
        }),
        progressValue = state.bridge.text({
            Center = true, Color = colors.secondary, Size = 11, Text = "0%", ZIndex = 203,
        }),
        progressTrack = state.surface:create("Square", {
            Color = colors.border,
            Filled = true,
            Size = Vector2.new(CONTENT_WIDTH, 4),
            Visible = true,
            ZIndex = 202,
        }, { pointerEvents = false }),
        progressFill = state.surface:create("Square", {
            Color = colors.accent,
            Filled = true,
            Size = Vector2.new(0, 4),
            Visible = true,
            ZIndex = 203,
        }, { pointerEvents = false }),
    }
    plotCopy.dropdownItems = state.plotDropdownItems
    state.controls.plotCopy = plotCopy
    local nativeSaveInput

    plotCopy.ownerButton:on("click", function()
        setPlotDropdownOpen(state, not state.plotDropdownOpen)
    end)
    plotCopy.saveButton:on("click", function()
        setPlotDropdownOpen(state, false)
        if nativeSaveInput then
            nativeSaveInput:CaptureFocus()
        end
    end)
    local function runPrimaryAction()
        state.plotActions.primary(state.selectedPlotOwner, state.plotSaveName, function()
            setPlotDropdownOpen(state, false)
        end)
    end
    plotCopy.actionButton:on("click", runPrimaryAction)
    plotCopy.secondaryButton:on("click", function()
        state.plotActions.secondary()
    end)

    if state.context.uiParent then
        local createInstance = state.context.createInstance or Instance.new
        local inputLayer = createInstance("ScreenGui")
        inputLayer.Name = "UniversalHubPlotCopyInput"
        inputLayer.DisplayOrder = 10000
        inputLayer.IgnoreGuiInset = true
        inputLayer.ResetOnSpawn = false
        inputLayer.Parent = state.context.uiParent

        local saveInput = createInstance("TextBox")
        saveInput.Name = "SaveName"
        saveInput.BackgroundTransparency = 1
        saveInput.ClearTextOnFocus = false
        saveInput.Position = UDim2.fromOffset(-20, -20)
        saveInput.Size = UDim2.fromOffset(1, 1)
        saveInput.Text = ""
        saveInput.TextTransparency = 1
        saveInput.Parent = inputLayer
        nativeSaveInput = saveInput
        plotCopy.inputLayer = inputLayer
        plotCopy.saveInput = saveInput
        table.insert(state.nativeConnections, saveInput:GetPropertyChangedSignal("Text"):Connect(function()
            setPlotSaveName(state, saveInput.Text)
        end))
        table.insert(state.nativeConnections, saveInput.Focused:Connect(function()
            plotCopy.saveOutline.Color = colors.accent
        end))
        table.insert(state.nativeConnections, saveInput.FocusLost:Connect(function(enterPressed)
            plotCopy.saveOutline.Color = colors.border
            if enterPressed then
                runPrimaryAction()
            end
        end))
    end
end

function PresentationHost:cosmetics()
    local state = private(self)
    if state.cosmeticsBuilt then
        return
    end
    state.cosmeticsBuilt = true
    local controls = state.controls
    local colors = state.theme
    local surface = state.surface

    controls.cosmetics = {
        header = state.bridge.interactive(surface:create("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(276, 30),
            Visible = true,
            ZIndex = 202,
        })),
        headerLabel = state.bridge.text({
            Color = colors.accent,
            Size = 11,
            Text = "COSMETICS",
            ZIndex = 203,
        }),
        indicator = state.bridge.text({
            Center = true,
            Color = colors.secondary,
            Size = 14,
            Text = "+",
            ZIndex = 203,
        }),
        weaponMode = state.bridge.interactive(surface:create("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(134, 24),
            Visible = false,
            ZIndex = 202,
        })),
        weaponModeLabel = state.bridge.text({
            Center = true,
            Color = colors.text,
            Size = 12,
            Text = "Weapons",
            Visible = false,
            ZIndex = 203,
        }),
        gloveMode = state.bridge.interactive(surface:create("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(134, 24),
            Visible = false,
            ZIndex = 202,
        })),
        gloveModeLabel = state.bridge.text({
            Center = true,
            Color = colors.text,
            Size = 12,
            Text = "Gloves",
            Visible = false,
            ZIndex = 203,
        }),
        weaponBackground = surface:create("Square", {
            Color = colors.panel,
            Filled = true,
            Size = Vector2.new(208, 30),
            Visible = false,
            ZIndex = 202,
        }, { pointerEvents = false }),
        weaponName = state.bridge.text({
            Center = true,
            Color = colors.text,
            Size = 13,
            Text = "Weapon",
            Visible = false,
            ZIndex = 203,
        }),
        weaponNext = state.bridge.interactive(surface:create("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(30, 30),
            Visible = false,
            ZIndex = 202,
        })),
        weaponNextLabel = state.bridge.text({
            Center = true,
            Color = colors.text,
            Size = 15,
            Text = ">",
            Visible = false,
            ZIndex = 203,
        }),
        weaponPrevious = state.bridge.interactive(surface:create("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(30, 30),
            Visible = false,
            ZIndex = 202,
        })),
        weaponPreviousLabel = state.bridge.text({
            Center = true,
            Color = colors.text,
            Size = 15,
            Text = "<",
            Visible = false,
            ZIndex = 203,
        }),
        next = state.bridge.interactive(surface:create("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(30, 30),
            Visible = false,
            ZIndex = 202,
        })),
        nextLabel = state.bridge.text({
            Center = true,
            Color = colors.text,
            Size = 15,
            Text = ">",
            Visible = false,
            ZIndex = 203,
        }),
        previous = state.bridge.interactive(surface:create("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(30, 30),
            Visible = false,
            ZIndex = 202,
        })),
        previousLabel = state.bridge.text({
            Center = true,
            Color = colors.text,
            Size = 15,
            Text = "<",
            Visible = false,
            ZIndex = 203,
        }),
        reset = state.bridge.interactive(surface:create("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(134, 30),
            Visible = false,
            ZIndex = 202,
        })),
        resetLabel = state.bridge.text({
            Color = colors.text,
            Size = 13,
            Text = "Reset Stock",
            Visible = false,
            ZIndex = 203,
        }),
        skinBackground = surface:create("Square", {
            Color = colors.panel,
            Filled = true,
            Size = Vector2.new(208, 30),
            Visible = false,
            ZIndex = 202,
        }, { pointerEvents = false }),
        skinName = state.bridge.text({
            Center = true,
            Color = colors.text,
            Size = 13,
            Text = "Stock",
            Visible = false,
            ZIndex = 203,
        }),
        statTrak = state.bridge.interactive(surface:create("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(134, 30),
            Visible = false,
            ZIndex = 202,
        })),
        statTrakLabel = state.bridge.text({
            Color = colors.text,
            Size = 13,
            Text = "StatTrak",
            Visible = false,
            ZIndex = 203,
        }),
        statTrakValue = state.bridge.text({
            Center = true,
            Color = colors.secondary,
            Size = 12,
            Text = "N/A",
            Visible = false,
            ZIndex = 203,
        }),
        wearFill = surface:create("Square", {
            Color = colors.accent,
            Filled = true,
            Visible = false,
            ZIndex = 204,
        }, { pointerEvents = false }),
        wearHit = state.bridge.interactive(surface:create("Square", {
            Color = colors.panel,
            Filled = true,
            Size = Vector2.new(276, 22),
            Transparency = HITBOX_TRANSPARENCY,
            Visible = false,
            ZIndex = 202,
        })),
        wearKnob = surface:create("Circle", {
            Color = colors.text,
            Filled = true,
            NumSides = 32,
            Radius = 6,
            Visible = false,
            ZIndex = 205,
        }, { pointerEvents = false }),
        wearLabel = state.bridge.text({
            Color = colors.secondary,
            Size = 12,
            Text = "Wear",
            Visible = false,
            ZIndex = 203,
        }),
        wearTrack = surface:create("Square", {
            Color = colors.border,
            Filled = true,
            Size = Vector2.new(276, 4),
            Visible = false,
            ZIndex = 203,
        }, { pointerEvents = false }),
        wearValue = state.bridge.text({
            Center = true,
            Color = colors.secondary,
            Size = 12,
            Text = "0.00",
            Visible = false,
            ZIndex = 203,
        }),
    }
    controls.cosmetics.colorChannels = {}
    for _, channel in ipairs({
        { id = "r", label = "R", color = Color3.fromRGB(230, 107, 110) },
        { id = "g", label = "G", color = colors.accent },
        { id = "b", label = "B", color = Color3.fromRGB(91, 155, 213) },
    }) do
        controls.cosmetics.colorChannels[channel.id] = {
            fill = surface:create("Square", {
                Color = channel.color,
                Filled = true,
                Visible = false,
                ZIndex = 204,
            }, { pointerEvents = false }),
            hit = state.bridge.interactive(surface:create("Square", {
                Color = colors.panel,
                Filled = true,
                Size = Vector2.new(236, 20),
                Transparency = HITBOX_TRANSPARENCY,
                Visible = false,
                ZIndex = 202,
            })),
            knob = surface:create("Circle", {
                Color = colors.text,
                Filled = true,
                NumSides = 32,
                Radius = 5,
                Visible = false,
                ZIndex = 205,
            }, { pointerEvents = false }),
            label = state.bridge.text({
                Color = channel.color,
                Size = 12,
                Text = channel.label,
                Visible = false,
                ZIndex = 203,
            }),
            track = surface:create("Square", {
                Color = colors.border,
                Filled = true,
                Size = Vector2.new(236, 4),
                Visible = false,
                ZIndex = 203,
            }, { pointerEvents = false }),
            value = state.bridge.text({
                Center = true,
                Color = colors.secondary,
                Size = 11,
                Text = "0",
                Visible = false,
                ZIndex = 203,
            }),
        }
    end

    controls.cosmetics.header:on("click", function()
        state.context.setCosmeticsOpen(not state.context.store:Get().cosmeticsOpen)
    end)
    controls.cosmetics.weaponMode:on("click", function()
        state.context.setCosmeticMode("weapon")
    end)
    controls.cosmetics.gloveMode:on("click", function()
        state.context.setCosmeticMode("gloves")
    end)
    controls.cosmetics.weaponPrevious:on("click", function()
        state.context.cycleCosmeticWeapon(-1)
    end)
    controls.cosmetics.weaponNext:on("click", function()
        state.context.cycleCosmeticWeapon(1)
    end)
    controls.cosmetics.previous:on("click", function()
        if state.context.store:Get().cosmeticMode == "gloves" then
            state.context.cycleGlove(-1)
        else
            state.context.cycleSkin(-1)
        end
    end)
    controls.cosmetics.next:on("click", function()
        if state.context.store:Get().cosmeticMode == "gloves" then
            state.context.cycleGlove(1)
        else
            state.context.cycleSkin(1)
        end
    end)
    controls.cosmetics.statTrak:on("click", function()
        local currentState = state.context.store:Get()
        if currentState.cosmeticMode == "gloves" then
            local current = currentState.settings.gloveColorOverride
            if type(current) == "table" then
                state.context.setGloveColor(false)
            else
                state.context.setGloveColor({
                    b = 0.68,
                    g = 0.84,
                    r = 0.38,
                })
            end
        else
            state.context.toggleStatTrak()
        end
    end)
    controls.cosmetics.reset:on("click", function()
        if state.context.store:Get().cosmeticMode == "gloves" then
            state.context.resetGlove()
        else
            state.context.resetSkin()
        end
    end)

    local function setWear(point)
        local alpha = math.clamp((point.X - state.wearStartX) / 276, 0, 1)
        if state.context.store:Get().cosmeticMode == "gloves" then
            state.context.setGloveWear(alpha)
        else
            state.context.setWear(alpha)
        end
    end
    local wearActivePaint = registerActiveSliderPaint(controls.cosmetics.wearHit, function(painter, point)
        local alpha = math.clamp((point.X - state.wearStartX) / 276, 0, 1)
        paintActiveSlider(
            painter,
            controls.cosmetics.wearTrack,
            276 * alpha,
            state.wearStartX + 276 * alpha,
            6,
            colors.accent,
            colors.text
        )
    end)
    controls.cosmetics.wearHit:on("pointerdown", function(_node, point)
        setWear(point)
        if wearActivePaint then
            setRetainedSliderVisible(
                state,
                controls.cosmetics.wearFill,
                controls.cosmetics.wearKnob,
                false
            )
        end
    end)
    controls.cosmetics.wearHit:on("drag", function(_node, point)
        setWear(point)
        if wearActivePaint then
            setRetainedSliderVisible(
                state,
                controls.cosmetics.wearFill,
                controls.cosmetics.wearKnob,
                false
            )
        end
    end)
    controls.cosmetics.wearHit:on("pointerup", function(_node, point)
        setWear(point)
        if wearActivePaint then
            setRetainedSliderVisible(
                state,
                controls.cosmetics.wearFill,
                controls.cosmetics.wearKnob,
                true
            )
        end
    end)
    for channelName, channel in pairs(controls.cosmetics.colorChannels) do
        local function setColor(point)
            local currentState = state.context.store:Get()
            local current = currentState.settings.gloveColorOverride
            if type(current) ~= "table" then
                return
            end
            local color = {
                b = current.b,
                g = current.g,
                r = current.r,
            }
            color[channelName] = math.clamp((point.X - state.colorStartX) / 236, 0, 1)
            state.context.setGloveColor(color)
        end
        local activePaint = registerActiveSliderPaint(channel.hit, function(painter, point)
            local alpha = math.clamp((point.X - state.colorStartX) / 236, 0, 1)
            paintActiveSlider(
                painter,
                channel.track,
                236 * alpha,
                state.colorStartX + 236 * alpha,
                5,
                channel.label.Color,
                colors.text
            )
        end)
        channel.hit:on("pointerdown", function(_node, point)
            setColor(point)
            if activePaint then
                setRetainedSliderVisible(state, channel.fill, channel.knob, false)
            end
        end)
        channel.hit:on("drag", function(_node, point)
            setColor(point)
            if activePaint then
                setRetainedSliderVisible(state, channel.fill, channel.knob, false)
            end
        end)
        channel.hit:on("pointerup", function(_node, point)
            setColor(point)
            if activePaint then
                setRetainedSliderVisible(state, channel.fill, channel.knob, true)
            end
        end)
    end
end

function PresentationHost:layout(x, y)
    local state = private(self)
    local controls = state.controls
    if state.aimBuilt then
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

        state.sliderStartX = x + 24
        controls.sliderHit.Position = Vector2.new(state.sliderStartX, y + 114)
        controls.sliderTrack.Position = Vector2.new(state.sliderStartX, y + 127)
        controls.sliderFill.Position = controls.sliderTrack.Position
    end

    local sectionY = y + (state.aimControlsSupported and 184 or 60)
    for _, group in ipairs(state.groups) do
        local section = controls.sections[group.id]
        if section then
            section.label.Position = Vector2.new(x + 12, sectionY)
            section.line.Position = Vector2.new(
                x + (group.id == "rage" and 64 or (group.id == "plotCopy" and 82 or 70)),
                sectionY + 7
            )
            sectionY = sectionY + 22
        end

        if group.id == "rage" then
            for _, id in ipairs(state.rates) do
                local control = controls.rates[id]
                control.background.Position = Vector2.new(x + 12, sectionY)
                control.border.Position = control.background.Position
                control.label.Position = Vector2.new(x + 22, sectionY + 8)
                control.valueSurface.Visible = false
                control.valueBorder.Visible = false
                control.value.Position = Vector2.new(x + 258, sectionY + 8)
                control.hit.Position = Vector2.new(x + 22, sectionY + 22)
                control.track.Position = Vector2.new(x + 22, sectionY + 35)
                control.fill.Position = control.track.Position
                sectionY = sectionY + 58
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
                    option.row.Position = Vector2.new(rowX, sectionY)
                    option.row.Size = Vector2.new(rowWidth, 32)
                    option.outline.Position = option.row.Position
                    option.outline.Size = option.row.Size
                    if option.marker then
                        option.marker.Position = Vector2.new(rowX + 10, sectionY + 9)
                    end
                    option.label.Position =
                        Vector2.new(rowX + (option.marker and 24 or 12), sectionY + 10)
                    option.value.Position = Vector2.new(rowX + rowWidth - 60, sectionY + 10)
                    local switchX = rowX + rowWidth - 30
                    local switchY = sectionY + 16
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
                sectionY = sectionY + 36
            end
        end
        if section then
            sectionY = sectionY + 6
        end
    end

    local plotCopy = controls.plotCopy
    if plotCopy then
        local section = controls.sections.plotCopy
        section.label.Position = Vector2.new(x + 12, sectionY)
        section.line.Position = Vector2.new(x + 82, sectionY + 7)
        sectionY = sectionY + 22

        plotCopy.ownerButton.Position = Vector2.new(x + 12, sectionY)
        plotCopy.ownerOutline.Position = plotCopy.ownerButton.Position
        plotCopy.ownerLabel.Position = Vector2.new(x + 22, sectionY + 9)
        plotCopy.ownerValue.Position = Vector2.new(x + 106, sectionY + 9)
        plotCopy.ownerIndicator.Position = Vector2.new(x + 275, sectionY + 8)

        plotCopy.saveButton.Position = Vector2.new(x + 12, sectionY + 36)
        plotCopy.saveOutline.Position = plotCopy.saveButton.Position
        plotCopy.saveLabel.Position = Vector2.new(x + 22, sectionY + 45)
        plotCopy.saveValue.Position = Vector2.new(x + 82, sectionY + 45)

        plotCopy.actionButton.Position = Vector2.new(x + 12, sectionY + 72)
        plotCopy.actionLabel.Position = Vector2.new(x + 150, sectionY + 80)
        plotCopy.secondaryButton.Position = Vector2.new(x + 12, sectionY + 108)
        plotCopy.secondaryLabel.Position = Vector2.new(x + 150, sectionY + 114)
        plotCopy.progressPhase.Position = Vector2.new(x + 14, sectionY + 143)
        plotCopy.progressValue.Position = Vector2.new(x + 274, sectionY + 143)
        plotCopy.progressContext.Position = Vector2.new(x + 14, sectionY + 161)
        plotCopy.progressTrack.Position = Vector2.new(x + 12, sectionY + 180)
        plotCopy.progressFill.Position = plotCopy.progressTrack.Position

        for index, item in ipairs(state.plotDropdownItems) do
            item.row.Position = Vector2.new(x + 12, sectionY + 30 + (index - 1) * 26)
            item.label.Position = Vector2.new(x + 22, sectionY + 37 + (index - 1) * 26)
        end
        sectionY = sectionY + 192
    end

    state.optionsPanelHeight = sectionY - y + 12
    local cosmetics = controls.cosmetics
    cosmetics.header.Position = Vector2.new(x + 12, sectionY)
    cosmetics.headerLabel.Position = Vector2.new(x + 22, sectionY + 9)
    cosmetics.indicator.Position = Vector2.new(x + 270, sectionY + 7)
    cosmetics.weaponMode.Position = Vector2.new(x + 12, sectionY + 30)
    cosmetics.weaponModeLabel.Position = Vector2.new(x + 79, sectionY + 37)
    cosmetics.gloveMode.Position = Vector2.new(x + 154, sectionY + 30)
    cosmetics.gloveModeLabel.Position = Vector2.new(x + 221, sectionY + 37)
    cosmetics.weaponPrevious.Position = Vector2.new(x + 12, sectionY + 58)
    cosmetics.weaponPreviousLabel.Position = Vector2.new(x + 27, sectionY + 65)
    cosmetics.weaponBackground.Position = Vector2.new(x + 46, sectionY + 58)
    cosmetics.weaponName.Position = Vector2.new(x + 150, sectionY + 66)
    cosmetics.weaponNext.Position = Vector2.new(x + 258, sectionY + 58)
    cosmetics.weaponNextLabel.Position = Vector2.new(x + 273, sectionY + 65)
    local weaponOffset = state.cosmeticMode == "weapon" and 34 or 0
    cosmetics.previous.Position = Vector2.new(x + 12, sectionY + 58 + weaponOffset)
    cosmetics.previousLabel.Position = Vector2.new(x + 27, sectionY + 65 + weaponOffset)
    cosmetics.skinBackground.Position = Vector2.new(x + 46, sectionY + 58 + weaponOffset)
    cosmetics.skinName.Position = Vector2.new(x + 150, sectionY + 66 + weaponOffset)
    cosmetics.next.Position = Vector2.new(x + 258, sectionY + 58 + weaponOffset)
    cosmetics.nextLabel.Position = Vector2.new(x + 273, sectionY + 65 + weaponOffset)
    cosmetics.wearLabel.Position = Vector2.new(x + 12, sectionY + 94 + weaponOffset)
    cosmetics.wearValue.Position = Vector2.new(x + 264, sectionY + 94 + weaponOffset)
    state.wearStartX = x + 12
    cosmetics.wearHit.Position = Vector2.new(x + 12, sectionY + 106 + weaponOffset)
    cosmetics.wearTrack.Position = Vector2.new(x + 12, sectionY + 115 + weaponOffset)
    cosmetics.wearFill.Position = cosmetics.wearTrack.Position
    cosmetics.statTrak.Position = Vector2.new(x + 12, sectionY + 132 + weaponOffset)
    cosmetics.statTrakLabel.Position = Vector2.new(x + 21, sectionY + 140 + weaponOffset)
    cosmetics.statTrakValue.Position = Vector2.new(x + 124, sectionY + 140 + weaponOffset)
    cosmetics.reset.Position = Vector2.new(x + 154, sectionY + 132 + weaponOffset)
    cosmetics.resetLabel.Position = Vector2.new(x + 163, sectionY + 140 + weaponOffset)
    state.colorStartX = x + 32
    for index, channelName in ipairs({ "r", "g", "b" }) do
        local channel = cosmetics.colorChannels[channelName]
        local channelY = sectionY + 166 + weaponOffset + (index - 1) * 24
        channel.label.Position = Vector2.new(x + 12, channelY + 4)
        channel.hit.Position = Vector2.new(x + 32, channelY)
        channel.track.Position = Vector2.new(x + 32, channelY + 8)
        channel.fill.Position = channel.track.Position
        channel.value.Position = Vector2.new(x + 280, channelY + 3)
    end
    return state.optionsPanelHeight
end

function PresentationHost:setVisible(visible)
    local state = private(self)
    local controls = state.controls
    local aimVisible = visible and state.aimControlsSupported
    if state.aimBuilt then
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
            controls[name].Visible = aimVisible
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
    for _, section in pairs(controls.sections) do
        setVisible(section, visible)
    end

    local plotCopy = controls.plotCopy
    if plotCopy then
        for name, node in pairs(plotCopy) do
            if name ~= "inputLayer"
                and name ~= "saveInput"
                and name ~= "dropdownItems"
                and name ~= "secondaryButton"
                and name ~= "secondaryLabel"
                and name ~= "secondaryVisible"
            then
                node.Visible = visible
            end
        end
        plotCopy.secondaryButton.Visible = visible and plotCopy.secondaryVisible == true
        plotCopy.secondaryLabel.Visible = visible and plotCopy.secondaryVisible == true
        for _, item in ipairs(state.plotDropdownItems) do
            setVisible(item, visible and state.plotDropdownOpen)
        end
        if plotCopy.inputLayer then
            plotCopy.inputLayer.Enabled = visible
        end
        if not visible then
            setPlotDropdownOpen(state, false)
        end
    end

    local cosmeticsVisible = visible and state.cosmeticsSupported
    controls.cosmetics.header.Visible = cosmeticsVisible
    controls.cosmetics.headerLabel.Visible = cosmeticsVisible
    controls.cosmetics.indicator.Visible = cosmeticsVisible
    for name, node in pairs(controls.cosmetics) do
        if name ~= "header" and name ~= "headerLabel" and name ~= "indicator" then
            if name == "colorChannels" then
                for _, channel in pairs(node) do
                    setVisible(
                        channel,
                        cosmeticsVisible and state.cosmeticsOpen == true and state.gloveColorVisible == true
                    )
                end
            elseif COSMETIC_WEAPON_CONTROLS[name] then
                node.Visible = cosmeticsVisible
                    and state.cosmeticsOpen == true
                    and state.cosmeticMode == "weapon"
            else
                node.Visible = cosmeticsVisible and state.cosmeticsOpen == true
            end
        end
    end
    for node in pairs(state.activeSliderVisuals) do
        node.Visible = false
    end
end

function PresentationHost:render(current)
    local state = private(self)
    local settings = current.settings
    local controls = state.controls
    local colors = state.theme
    state.cosmeticMode = current.cosmeticMode == "gloves" and "gloves" or "weapon"
    state.cosmeticsOpen = current.cosmeticsOpen == true
    if state.aimBuilt then
        controls.weaponValue.Text = current.activeWeapon or "Spectating"
        controls.weaponValue.Color = current.activeWeapon and colors.accent or colors.secondary
    end

    local plotCopy = controls.plotCopy
    if plotCopy then
        local plotCopyState = current.plotCopy or {}
        local progress = math.clamp(
            plotCopyState.confirmedProgress or plotCopyState.progress or 0,
            0,
            1
        )
        local active = plotCopyState.active == true
        local copyState = plotCopyState.state or (active and "copying" or "idle")
        local hasError = copyState == "error" or copyState == "rollback_incomplete"
        local primaryLabels = {
            awaiting_confirmation = "Start copy",
            cancel_requested = "Cancelling...",
            cleanup_pending = "Cleanup pending",
            completed = "Copy another",
            copying = "Cancel",
            copy_authorized = "Starting...",
            discarding = "Discarding...",
            error = "Retry",
            idle = "Copy & Save",
            paused = "Resume",
            preflight = "Cancel",
            reconciling = "Cancel",
            resuming = "Cancel",
            rollback = "Cleaning...",
            rollback_incomplete = "Retry cleanup",
            saving = "Saving...",
        }
        local primaryEnabled = copyState == "idle"
            or copyState == "completed"
            or copyState == "error"
            or copyState == "awaiting_confirmation"
            or copyState == "copying"
            or copyState == "preflight"
            or copyState == "reconciling"
            or copyState == "resuming"
            or copyState == "paused"
            or copyState == "rollback_incomplete"
            or copyState == "rollback"
            or copyState == "cleanup_pending"
        local secondaryLabel
        if copyState == "awaiting_confirmation" then
            secondaryLabel = "Cancel"
        elseif copyState == "paused" then
            secondaryLabel = "Discard"
        end
        plotCopy.progressPhase.Text = compactText(plotCopyState.phase or "Ready", 34)
        plotCopy.progressPhase.Color = hasError and colors.danger
            or (active and colors.text or colors.secondary)
        plotCopy.progressContext.Text = plotCopyState.context or ""
        plotCopy.progressContext.Color = hasError and colors.danger or colors.secondary
        plotCopy.progressValue.Text = ("%d%%"):format(math.round(progress * 100))
        plotCopy.progressValue.Color = active and colors.accent or colors.secondary
        plotCopy.progressFill.Size = Vector2.new(CONTENT_WIDTH * progress, 4)
        plotCopy.progressFill.Color = hasError and colors.danger or colors.accent
        state.bridge.setControlColor(
            plotCopy.actionButton,
            primaryEnabled and colors.accentSurface or colors.panel
        )
        plotCopy.actionLabel.Text = plotCopyState.localCleanupAvailable
                and "Clear local recovery"
            or (plotCopyState.retryCleanupAvailable and "Retry cleanup")
            or (
                plotCopyState.resumeAvailable
                    and copyState ~= "awaiting_confirmation"
                    and "Resume"
            )
            or (primaryLabels[copyState] or "Working...")
        plotCopy.actionLabel.Color = primaryEnabled and colors.accent or colors.secondary
        local showSecondary = secondaryLabel ~= nil and current.menuVisible ~= false
        plotCopy.secondaryVisible = secondaryLabel ~= nil
        plotCopy.secondaryButton.Visible = showSecondary
        plotCopy.secondaryLabel.Visible = showSecondary
        plotCopy.secondaryLabel.Text = secondaryLabel or ""
    end

    for optionName, option in pairs(controls.options) do
        local enabled = settings[optionName] == true
        local parent = state.parents[optionName]
        local supported = state.optionSupport[optionName] ~= false
        local available = supported and (not parent or settings[parent] == true)
        state.bridge.setControlColor(option.row, available and colors.elevated or colors.panel)
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

    for _, id in ipairs(state.rates) do
        local control = controls.rates[id]
        local value = math.clamp(settings[id] or 0, 0, 100)
        local alpha = value / 100
        local thumbTravel = RATE_TRACK_WIDTH - RATE_THUMB_RADIUS * 2
        local thumbX = control.track.Position.X
            + RATE_THUMB_RADIUS
            + thumbTravel * alpha
        control.fill.Size = Vector2.new(math.max(0, thumbX - control.track.Position.X), 4)
        control.knob.Position = Vector2.new(thumbX, control.track.Position.Y + 2)
        control.value.Text = ("%d%%"):format(math.round(value))
    end

    if state.aimBuilt then
        local alpha = (settings.fov - settings.minimumFov) / (settings.maximumFov - settings.minimumFov)
        controls.sliderFill.Size = Vector2.new(FOV_TRACK_WIDTH * alpha, 4)
        controls.sliderKnob.Position = Vector2.new(
            state.sliderStartX + FOV_TRACK_WIDTH * alpha,
            controls.sliderTrack.Position.Y + 2
        )
        state.bridge.setControlColor(
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
        controls.fovCircle.Visible = state.aimControlsSupported
            and settings.fovCircle ~= false
            and not settings.fullScreenAim
    end

    local cosmeticMode = state.cosmeticMode
    local gloveColor = settings.gloveColorOverride
    state.gloveColorVisible = cosmeticMode == "gloves" and type(gloveColor) == "table"
    local collapsedHeight = (state.optionsPanelHeight or 560) + 36
    controls.panel.Size = Vector2.new(300, if state.cosmeticsSupported
        then (state.cosmeticsOpen
            and (collapsedHeight
                + (cosmeticMode == "weapon" and 162 or (state.gloveColorVisible and 202 or 128)))
            or collapsedHeight)
        else (state.optionsPanelHeight or 596))
    controls.panelShadow.Size = controls.panel.Size
    controls.panelBorder.Size = controls.panel.Size
    local cosmetics = cosmeticMode == "gloves" and (current.gloves or {}) or (current.cosmetics or {})
    local cosmeticControls = controls.cosmetics
    local minimumWear = cosmetics.minimumWear or 0
    local maximumWear = cosmetics.maximumWear or 1
    local wearRange = maximumWear - minimumWear
    local wearAlpha = wearRange > 0 and ((cosmetics.wear or minimumWear) - minimumWear) / wearRange or 0
    cosmeticControls.indicator.Text = state.cosmeticsOpen and "-" or "+"
    state.bridge.setControlColor(
        cosmeticControls.weaponMode,
        cosmeticMode == "weapon" and colors.accentSurface or colors.elevated
    )
    state.bridge.setControlColor(
        cosmeticControls.gloveMode,
        cosmeticMode == "gloves" and colors.accentSurface or colors.elevated
    )
    cosmeticControls.weaponModeLabel.Color = cosmeticMode == "weapon" and colors.accent or colors.text
    cosmeticControls.gloveModeLabel.Color = cosmeticMode == "gloves" and colors.accent or colors.text
    cosmeticControls.weaponModeLabel.Text =
        cosmeticMode == "weapon" and (cosmetics.weapon or "Weapon") or "Weapons"
    cosmeticControls.gloveModeLabel.Text =
        cosmeticMode == "gloves" and (cosmetics.weapon or "Gloves") or "Gloves"
    cosmeticControls.weaponName.Text = current.cosmeticWeapon or current.activeWeapon or "Select weapon"
    cosmeticControls.skinName.Text = cosmetics.skinLabel or cosmetics.skin or "Stock"
    cosmeticControls.wearValue.Text = ("%.2f"):format(cosmetics.wear or 0)
    cosmeticControls.wearFill.Size = Vector2.new(276 * wearAlpha, 4)
    cosmeticControls.wearKnob.Position =
        Vector2.new(state.wearStartX + 276 * wearAlpha, cosmeticControls.wearTrack.Position.Y + 2)
    local supportsStatTrak = cosmeticMode ~= "gloves" and cosmetics.supportsStatTrak == true
    local solidColor = cosmeticMode == "gloves" and type(gloveColor) == "table"
    state.bridge.setControlColor(cosmeticControls.statTrak,
        solidColor and colors.accentSurface
        or (supportsStatTrak and (cosmetics.statTrak and colors.accentSurface or colors.elevated)
            or colors.elevated))
    cosmeticControls.statTrakLabel.Color =
        (supportsStatTrak or cosmeticMode == "gloves") and colors.text or colors.secondary
    cosmeticControls.statTrakValue.Color =
        (solidColor or (supportsStatTrak and cosmetics.statTrak)) and colors.accent or colors.secondary
    cosmeticControls.statTrakLabel.Text = cosmeticMode == "gloves" and "Solid Color" or "StatTrak"
    cosmeticControls.statTrakValue.Text = cosmeticMode == "gloves"
            and (solidColor and "On" or "Off")
        or (not supportsStatTrak and "N/A" or (cosmetics.statTrak and "On" or "Off"))
    if solidColor then
        for _, channelName in ipairs({ "r", "g", "b" }) do
            local channel = cosmeticControls.colorChannels[channelName]
            local value = math.clamp(gloveColor[channelName] or 0, 0, 1)
            channel.fill.Size = Vector2.new(236 * value, 4)
            channel.knob.Position =
                Vector2.new(state.colorStartX + 236 * value, channel.track.Position.Y + 2)
            channel.value.Text = tostring(math.round(value * 255))
        end
    end
    cosmeticControls.resetLabel.Text = cosmeticMode == "gloves" and "Reset Game" or "Reset Stock"
end

function PresentationHost:setMousePosition(position)
    local controls = private(self).controls
    if controls.fovCircle then
        controls.fovCircle.Position = position
    end
end

function PresentationHost:destroy()
    local state = PRIVATE[self]
    if not state then
        return
    end
    clearPlotDropdown(state)
    for _, connection in ipairs(state.nativeConnections) do
        connection:Disconnect()
    end
    table.clear(state.nativeConnections)
    local plotCopy = state.controls.plotCopy
    if plotCopy and plotCopy.inputLayer then
        plotCopy.inputLayer:Destroy()
        plotCopy.inputLayer = nil
        plotCopy.saveInput = nil
    end
    PRIVATE[self] = nil
end

return PresentationHost
