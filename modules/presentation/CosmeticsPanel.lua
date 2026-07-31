local CosmeticsPanel = {}
CosmeticsPanel.__index = CosmeticsPanel

local ACTIVE_CONTROL_LAYER = 206
local HITBOX_TRANSPARENCY = 0.01
local WEAPON_CONTROLS = {
    weaponBackground = true,
    weaponName = true,
    weaponNext = true,
    weaponNextLabel = true,
    weaponPrevious = true,
    weaponPreviousLabel = true,
}

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

local function paintActiveSlider(painter, track, width, knobX, radius, fillColor, knobColor)
    painter.FilledRectangle(track.Position, Vector2.new(math.max(0, width), 4), fillColor, 1, 0)
    painter.FilledCircle(
        Vector2.new(knobX, track.Position.Y + track.Size.Y * 0.5),
        radius,
        knobColor,
        1,
        32
    )
end

function CosmeticsPanel.new(bridge)
    local self = setmetatable({
        activeSliderVisuals = bridge.activeSliderVisuals,
        bridge = bridge,
        controls = bridge.controls,
        theme = bridge.theme,
    }, CosmeticsPanel)
    self:_build()
    return self
end

function CosmeticsPanel:_build()
    local state = self
    local controls = state.controls
    local colors = state.theme
    local function node(kind, properties, pointerEvents)
        return state.bridge.node(kind, properties, pointerEvents == true)
    end
    local function interactive(kind, properties)
        return state.bridge.interactive(node(kind, properties, true))
    end
    local function text(properties)
        return state.bridge.text(properties)
    end

    controls.cosmetics = {
        header = interactive("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(276, 30),
            Visible = true,
            ZIndex = 202,
        }),
        headerLabel = text({
            Color = colors.accent,
            Size = 11,
            Text = "COSMETICS",
            ZIndex = 203,
        }),
        indicator = text({
            Center = true,
            Color = colors.secondary,
            Size = 14,
            Text = "+",
            ZIndex = 203,
        }),
        weaponMode = interactive("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(134, 24),
            Visible = false,
            ZIndex = 202,
        }),
        weaponModeLabel = text({
            Center = true,
            Color = colors.text,
            Size = 12,
            Text = "Weapons",
            Visible = false,
            ZIndex = 203,
        }),
        gloveMode = interactive("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(134, 24),
            Visible = false,
            ZIndex = 202,
        }),
        gloveModeLabel = text({
            Center = true,
            Color = colors.text,
            Size = 12,
            Text = "Gloves",
            Visible = false,
            ZIndex = 203,
        }),
        weaponBackground = node("Square", {
            Color = colors.panel,
            Filled = true,
            Size = Vector2.new(208, 30),
            Visible = false,
            ZIndex = 202,
        }),
        weaponName = text({
            Center = true,
            Color = colors.text,
            Size = 13,
            Text = "Weapon",
            Visible = false,
            ZIndex = 203,
        }),
        weaponNext = interactive("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(30, 30),
            Visible = false,
            ZIndex = 202,
        }),
        weaponNextLabel = text({
            Center = true,
            Color = colors.text,
            Size = 15,
            Text = ">",
            Visible = false,
            ZIndex = 203,
        }),
        weaponPrevious = interactive("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(30, 30),
            Visible = false,
            ZIndex = 202,
        }),
        weaponPreviousLabel = text({
            Center = true,
            Color = colors.text,
            Size = 15,
            Text = "<",
            Visible = false,
            ZIndex = 203,
        }),
        next = interactive("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(30, 30),
            Visible = false,
            ZIndex = 202,
        }),
        nextLabel = text({
            Center = true,
            Color = colors.text,
            Size = 15,
            Text = ">",
            Visible = false,
            ZIndex = 203,
        }),
        previous = interactive("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(30, 30),
            Visible = false,
            ZIndex = 202,
        }),
        previousLabel = text({
            Center = true,
            Color = colors.text,
            Size = 15,
            Text = "<",
            Visible = false,
            ZIndex = 203,
        }),
        reset = interactive("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(134, 30),
            Visible = false,
            ZIndex = 202,
        }),
        resetLabel = text({
            Color = colors.text,
            Size = 13,
            Text = "Reset Stock",
            Visible = false,
            ZIndex = 203,
        }),
        skinBackground = node("Square", {
            Color = colors.panel,
            Filled = true,
            Size = Vector2.new(208, 30),
            Visible = false,
            ZIndex = 202,
        }),
        skinName = text({
            Center = true,
            Color = colors.text,
            Size = 13,
            Text = "Stock",
            Visible = false,
            ZIndex = 203,
        }),
        statTrak = interactive("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(134, 30),
            Visible = false,
            ZIndex = 202,
        }),
        statTrakLabel = text({
            Color = colors.text,
            Size = 13,
            Text = "StatTrak",
            Visible = false,
            ZIndex = 203,
        }),
        statTrakValue = text({
            Center = true,
            Color = colors.secondary,
            Size = 12,
            Text = "N/A",
            Visible = false,
            ZIndex = 203,
        }),
        wearFill = node("Square", {
            Color = colors.accent,
            Filled = true,
            Visible = false,
            ZIndex = 204,
        }),
        wearHit = interactive("Square", {
            Color = colors.panel,
            Filled = true,
            Size = Vector2.new(276, 22),
            Transparency = HITBOX_TRANSPARENCY,
            Visible = false,
            ZIndex = 202,
        }),
        wearKnob = node("Circle", {
            Color = colors.text,
            Filled = true,
            NumSides = 32,
            Radius = 6,
            Visible = false,
            ZIndex = 205,
        }),
        wearLabel = text({
            Color = colors.secondary,
            Size = 12,
            Text = "Wear",
            Visible = false,
            ZIndex = 203,
        }),
        wearTrack = node("Square", {
            Color = colors.border,
            Filled = true,
            Size = Vector2.new(276, 4),
            Visible = false,
            ZIndex = 203,
        }),
        wearValue = text({
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
            fill = node("Square", {
                Color = channel.color,
                Filled = true,
                Visible = false,
                ZIndex = 204,
            }),
            hit = interactive("Square", {
                Color = colors.panel,
                Filled = true,
                Size = Vector2.new(236, 20),
                Transparency = HITBOX_TRANSPARENCY,
                Visible = false,
                ZIndex = 202,
            }),
            knob = node("Circle", {
                Color = colors.text,
                Filled = true,
                NumSides = 32,
                Radius = 5,
                Visible = false,
                ZIndex = 205,
            }),
            label = text({
                Color = channel.color,
                Size = 12,
                Text = channel.label,
                Visible = false,
                ZIndex = 203,
            }),
            track = node("Square", {
                Color = colors.border,
                Filled = true,
                Size = Vector2.new(236, 4),
                Visible = false,
                ZIndex = 203,
            }),
            value = text({
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
        state.bridge.context.setCosmeticsOpen(not state.bridge.context.store:Get().cosmeticsOpen)
    end)
    controls.cosmetics.weaponMode:on("click", function()
        state.bridge.context.setCosmeticMode("weapon")
    end)
    controls.cosmetics.gloveMode:on("click", function()
        state.bridge.context.setCosmeticMode("gloves")
    end)
    controls.cosmetics.weaponPrevious:on("click", function()
        state.bridge.context.cycleCosmeticWeapon(-1)
    end)
    controls.cosmetics.weaponNext:on("click", function()
        state.bridge.context.cycleCosmeticWeapon(1)
    end)
    controls.cosmetics.previous:on("click", function()
        if state.bridge.context.store:Get().cosmeticMode == "gloves" then
            state.bridge.context.cycleGlove(-1)
        else
            state.bridge.context.cycleSkin(-1)
        end
    end)
    controls.cosmetics.next:on("click", function()
        if state.bridge.context.store:Get().cosmeticMode == "gloves" then
            state.bridge.context.cycleGlove(1)
        else
            state.bridge.context.cycleSkin(1)
        end
    end)
    controls.cosmetics.statTrak:on("click", function()
        local currentState = state.bridge.context.store:Get()
        if currentState.cosmeticMode == "gloves" then
            local current = currentState.settings.gloveColorOverride
            if type(current) == "table" then
                state.bridge.context.setGloveColor(false)
            else
                state.bridge.context.setGloveColor({ b = 0.68, g = 0.84, r = 0.38 })
            end
        else
            state.bridge.context.toggleStatTrak()
        end
    end)
    controls.cosmetics.reset:on("click", function()
        if state.bridge.context.store:Get().cosmeticMode == "gloves" then
            state.bridge.context.resetGlove()
        else
            state.bridge.context.resetSkin()
        end
    end)

    local function setWear(point)
        local alpha = math.clamp((point.X - state.wearStartX) / 276, 0, 1)
        if state.bridge.context.store:Get().cosmeticMode == "gloves" then
            state.bridge.context.setGloveWear(alpha)
        else
            state.bridge.context.setWear(alpha)
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
    for _, eventName in ipairs({ "pointerdown", "drag", "pointerup" }) do
        controls.cosmetics.wearHit:on(eventName, function(_node, point)
            setWear(point)
            if wearActivePaint then
                setRetainedSliderVisible(
                    state,
                    controls.cosmetics.wearFill,
                    controls.cosmetics.wearKnob,
                    eventName == "pointerup"
                )
            end
        end)
    end
    for channelName, channel in pairs(controls.cosmetics.colorChannels) do
        local function setColor(point)
            local current = state.bridge.context.store:Get().settings.gloveColorOverride
            if type(current) ~= "table" then
                return
            end
            local color = { b = current.b, g = current.g, r = current.r }
            color[channelName] = math.clamp((point.X - state.colorStartX) / 236, 0, 1)
            state.bridge.context.setGloveColor(color)
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
        for _, eventName in ipairs({ "pointerdown", "drag", "pointerup" }) do
            channel.hit:on(eventName, function(_node, point)
                setColor(point)
                if activePaint then
                    setRetainedSliderVisible(
                        state,
                        channel.fill,
                        channel.knob,
                        eventName == "pointerup"
                    )
                end
            end)
        end
    end
end

function CosmeticsPanel:layout(x, _y, cursor)
    local cosmetics = self.controls.cosmetics
    cosmetics.header.Position = Vector2.new(x + 12, cursor)
    cosmetics.headerLabel.Position = Vector2.new(x + 22, cursor + 9)
    cosmetics.indicator.Position = Vector2.new(x + 270, cursor + 7)
    cosmetics.weaponMode.Position = Vector2.new(x + 12, cursor + 30)
    cosmetics.weaponModeLabel.Position = Vector2.new(x + 79, cursor + 37)
    cosmetics.gloveMode.Position = Vector2.new(x + 154, cursor + 30)
    cosmetics.gloveModeLabel.Position = Vector2.new(x + 221, cursor + 37)
    cosmetics.weaponPrevious.Position = Vector2.new(x + 12, cursor + 58)
    cosmetics.weaponPreviousLabel.Position = Vector2.new(x + 27, cursor + 65)
    cosmetics.weaponBackground.Position = Vector2.new(x + 46, cursor + 58)
    cosmetics.weaponName.Position = Vector2.new(x + 150, cursor + 66)
    cosmetics.weaponNext.Position = Vector2.new(x + 258, cursor + 58)
    cosmetics.weaponNextLabel.Position = Vector2.new(x + 273, cursor + 65)
    local weaponOffset = self.cosmeticMode == "weapon" and 34 or 0
    cosmetics.previous.Position = Vector2.new(x + 12, cursor + 58 + weaponOffset)
    cosmetics.previousLabel.Position = Vector2.new(x + 27, cursor + 65 + weaponOffset)
    cosmetics.skinBackground.Position = Vector2.new(x + 46, cursor + 58 + weaponOffset)
    cosmetics.skinName.Position = Vector2.new(x + 150, cursor + 66 + weaponOffset)
    cosmetics.next.Position = Vector2.new(x + 258, cursor + 58 + weaponOffset)
    cosmetics.nextLabel.Position = Vector2.new(x + 273, cursor + 65 + weaponOffset)
    cosmetics.wearLabel.Position = Vector2.new(x + 12, cursor + 94 + weaponOffset)
    cosmetics.wearValue.Position = Vector2.new(x + 264, cursor + 94 + weaponOffset)
    self.wearStartX = x + 12
    cosmetics.wearHit.Position = Vector2.new(x + 12, cursor + 106 + weaponOffset)
    cosmetics.wearTrack.Position = Vector2.new(x + 12, cursor + 115 + weaponOffset)
    cosmetics.wearFill.Position = cosmetics.wearTrack.Position
    cosmetics.statTrak.Position = Vector2.new(x + 12, cursor + 132 + weaponOffset)
    cosmetics.statTrakLabel.Position = Vector2.new(x + 21, cursor + 140 + weaponOffset)
    cosmetics.statTrakValue.Position = Vector2.new(x + 124, cursor + 140 + weaponOffset)
    cosmetics.reset.Position = Vector2.new(x + 154, cursor + 132 + weaponOffset)
    cosmetics.resetLabel.Position = Vector2.new(x + 163, cursor + 140 + weaponOffset)
    self.colorStartX = x + 32
    for index, channelName in ipairs({ "r", "g", "b" }) do
        local channel = cosmetics.colorChannels[channelName]
        local channelY = cursor + 166 + weaponOffset + (index - 1) * 24
        channel.label.Position = Vector2.new(x + 12, channelY + 4)
        channel.hit.Position = Vector2.new(x + 32, channelY)
        channel.track.Position = Vector2.new(x + 32, channelY + 8)
        channel.fill.Position = channel.track.Position
        channel.value.Position = Vector2.new(x + 280, channelY + 3)
    end
    return cursor
end

function CosmeticsPanel:panelHeight(baseHeight)
    local collapsedHeight = baseHeight + 36
    if not self.cosmeticsOpen then
        return collapsedHeight
    end
    if self.cosmeticMode == "weapon" then
        return collapsedHeight + 162
    end
    return collapsedHeight + (self.gloveColorVisible and 202 or 128)
end

function CosmeticsPanel:setVisible(visible)
    local cosmetics = self.controls.cosmetics
    cosmetics.header.Visible = visible
    cosmetics.headerLabel.Visible = visible
    cosmetics.indicator.Visible = visible
    for name, node in pairs(cosmetics) do
        if name ~= "header" and name ~= "headerLabel" and name ~= "indicator" then
            if name == "colorChannels" then
                for _, channel in pairs(node) do
                    setVisible(channel, visible and self.cosmeticsOpen and self.gloveColorVisible)
                end
            elseif WEAPON_CONTROLS[name] then
                node.Visible = visible and self.cosmeticsOpen and self.cosmeticMode == "weapon"
            else
                node.Visible = visible and self.cosmeticsOpen
            end
        end
    end
end

function CosmeticsPanel:render(current)
    local colors = self.theme
    local settings = current.settings
    self.cosmeticMode = current.cosmeticMode == "gloves" and "gloves" or "weapon"
    self.cosmeticsOpen = current.cosmeticsOpen == true
    local cosmeticMode = self.cosmeticMode
    local gloveColor = settings.gloveColorOverride
    self.gloveColorVisible = cosmeticMode == "gloves" and type(gloveColor) == "table"
    local cosmetics = cosmeticMode == "gloves" and (current.gloves or {}) or (current.cosmetics or {})
    local controls = self.controls.cosmetics
    local minimumWear = cosmetics.minimumWear or 0
    local maximumWear = cosmetics.maximumWear or 1
    local wearRange = maximumWear - minimumWear
    local wearAlpha = wearRange > 0 and ((cosmetics.wear or minimumWear) - minimumWear) / wearRange or 0
    controls.indicator.Text = self.cosmeticsOpen and "-" or "+"
    self.bridge.setControlColor(
        controls.weaponMode,
        cosmeticMode == "weapon" and colors.accentSurface or colors.elevated
    )
    self.bridge.setControlColor(
        controls.gloveMode,
        cosmeticMode == "gloves" and colors.accentSurface or colors.elevated
    )
    controls.weaponModeLabel.Color = cosmeticMode == "weapon" and colors.accent or colors.text
    controls.gloveModeLabel.Color = cosmeticMode == "gloves" and colors.accent or colors.text
    controls.weaponModeLabel.Text =
        cosmeticMode == "weapon" and (cosmetics.weapon or "Weapon") or "Weapons"
    controls.gloveModeLabel.Text =
        cosmeticMode == "gloves" and (cosmetics.weapon or "Gloves") or "Gloves"
    controls.weaponName.Text = current.cosmeticWeapon or current.activeWeapon or "Select weapon"
    controls.skinName.Text = cosmetics.skinLabel or cosmetics.skin or "Stock"
    controls.wearValue.Text = ("%.2f"):format(cosmetics.wear or 0)
    controls.wearFill.Size = Vector2.new(276 * wearAlpha, 4)
    controls.wearKnob.Position =
        Vector2.new(self.wearStartX + 276 * wearAlpha, controls.wearTrack.Position.Y + 2)
    local supportsStatTrak = cosmeticMode ~= "gloves" and cosmetics.supportsStatTrak == true
    local solidColor = cosmeticMode == "gloves" and type(gloveColor) == "table"
    self.bridge.setControlColor(
        controls.statTrak,
        solidColor and colors.accentSurface
            or (supportsStatTrak
                and (cosmetics.statTrak and colors.accentSurface or colors.elevated)
                or colors.elevated)
    )
    controls.statTrakLabel.Color =
        (supportsStatTrak or cosmeticMode == "gloves") and colors.text or colors.secondary
    controls.statTrakValue.Color =
        (solidColor or (supportsStatTrak and cosmetics.statTrak)) and colors.accent or colors.secondary
    controls.statTrakLabel.Text = cosmeticMode == "gloves" and "Solid Color" or "StatTrak"
    controls.statTrakValue.Text = cosmeticMode == "gloves"
            and (solidColor and "On" or "Off")
        or (not supportsStatTrak and "N/A" or (cosmetics.statTrak and "On" or "Off"))
    if solidColor then
        for _, channelName in ipairs({ "r", "g", "b" }) do
            local channel = controls.colorChannels[channelName]
            local value = math.clamp(gloveColor[channelName] or 0, 0, 1)
            channel.fill.Size = Vector2.new(236 * value, 4)
            channel.knob.Position =
                Vector2.new(self.colorStartX + 236 * value, channel.track.Position.Y + 2)
            channel.value.Text = tostring(math.round(value * 255))
        end
    end
    controls.resetLabel.Text = cosmeticMode == "gloves" and "Reset Game" or "Reset Stock"
end

function CosmeticsPanel:destroy() end

return CosmeticsPanel
