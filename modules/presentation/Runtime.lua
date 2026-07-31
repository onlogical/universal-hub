local Runtime = {}
Runtime.__index = Runtime

local PRIVATE = setmetatable({}, { __mode = "k" })

local function private(runtime)
    return assert(PRIVATE[runtime], "Presentation runtime is unavailable")
end

local function buildAvailability(capabilities)
    local available = {}
    for key, value in pairs(capabilities or {}) do
        local name = type(key) == "number" and value or key
        if value ~= false then
            available[name] = true
        end
    end
    return available
end

function Runtime.new(bridge, parts)
    assert(type(bridge) == "table", "Presentation runtime requires an Overlay facade")
    assert(type(bridge.node) == "function", "Presentation runtime requires node construction")
    assert(type(bridge.text) == "function", "Presentation runtime requires text construction")
    assert(type(bridge.setControlColor) == "function", "Presentation runtime requires control coloring")
    assert(type(bridge.requestLayout) == "function", "Presentation runtime requires layout invalidation")
    assert(bridge.controls and bridge.context and bridge.theme)
    assert(type(parts) == "table", "Presentation runtime requires control parts")
    assert(type(parts.standard) == "table" and type(parts.standard.new) == "function")
    assert(type(parts.cosmetics) == "table" and type(parts.cosmetics.new) == "function")

    local controls = bridge.controls
    controls.rates = {}
    controls.sections = {}
    controls.options = {}
    controls.cosmetics = {}

    local runtime = setmetatable({}, Runtime)
    PRIVATE[runtime] = {
        activeSliderVisuals = bridge.activeSliderVisuals,
        available = buildAvailability(bridge.capabilities),
        bridge = bridge,
        cosmeticsSupported = bridge.cosmeticsSupported == true,
        parts = parts,
        panels = {},
        standard = nil,
        cosmetics = nil,
    }
    return runtime
end

function Runtime:_standard()
    local state = private(self)
    if not state.standard then
        state.standard = state.parts.standard.new(state.bridge, state.available)
        self:register(state.standard)
    end
    return state.standard
end

function Runtime:register(panel)
    assert(type(panel) == "table", "Registered presentation panel must be a table")
    assert(type(panel.layout) == "function", "Registered presentation panel requires layout")
    assert(type(panel.render) == "function", "Registered presentation panel requires render")
    assert(type(panel.setVisible) == "function", "Registered presentation panel requires visibility")
    assert(type(panel.destroy) == "function", "Registered presentation panel requires cleanup")
    table.insert(private(self).panels, panel)
    return panel
end

function Runtime:supports(name)
    return private(self).available[name] == true
end

function Runtime:read()
    return private(self).bridge.context.store:Get()
end

function Runtime:patch(patch)
    return private(self).bridge.context.store:Patch(patch)
end

function Runtime:action(name, ...)
    local callback = private(self).bridge.context[name]
    assert(type(callback) == "function", "Unknown presentation action: " .. tostring(name))
    return callback(...)
end

function Runtime:node(kind, properties, pointerEvents)
    return private(self).bridge.node(kind, properties, pointerEvents == true)
end

function Runtime:interactive(node)
    return private(self).bridge.interactive(node)
end

function Runtime:text(properties, pointerEvents)
    return private(self).bridge.text(properties, pointerEvents)
end

function Runtime:setControlColor(node, color)
    return private(self).bridge.setControlColor(node, color)
end

function Runtime:requestLayout()
    return private(self).bridge.requestLayout()
end

function Runtime:controls()
    return private(self).bridge.controls
end

function Runtime:theme()
    return private(self).bridge.theme
end

function Runtime:uiParent()
    return private(self).bridge.context.uiParent
end

function Runtime:createInstance(className)
    local context = private(self).bridge.context
    return (context.createInstance or Instance.new)(className)
end

function Runtime:aim()
    return self:_standard():aim()
end

function Runtime:rate(id, label)
    return self:_standard():rate(id, label)
end

function Runtime:section(id, label, lineOffset, includesRates)
    return self:_standard():section(id, label, lineOffset, includesRates)
end

function Runtime:option(sectionId, rowIndex, id, label, parent)
    return self:_standard():option(sectionId, rowIndex, id, label, parent)
end

function Runtime:cosmetics()
    local state = private(self)
    if not state.cosmeticsSupported then
        return
    end
    if not state.cosmetics then
        state.cosmetics = state.parts.cosmetics.new(state.bridge)
        self:register(state.cosmetics)
    end
end

function Runtime:layout(x, y)
    local state = private(self)
    local cursor = y + 60
    for _, panel in ipairs(state.panels) do
        cursor = panel:layout(x, y, cursor) or cursor
    end
    state.contentHeight = cursor - y + 12
    return state.contentHeight
end

function Runtime:render(current)
    local state = private(self)
    local panelHeight = state.contentHeight or 596
    for _, panel in ipairs(state.panels) do
        panel:render(current)
    end
    for _, panel in ipairs(state.panels) do
        if type(panel.panelHeight) == "function" then
            panelHeight = panel:panelHeight(panelHeight, current) or panelHeight
        end
    end
    local size = Vector2.new(300, panelHeight)
    state.bridge.controls.panel.Size = size
    state.bridge.controls.panelShadow.Size = size
    state.bridge.controls.panelBorder.Size = size
end

function Runtime:setVisible(visible)
    local state = private(self)
    for _, panel in ipairs(state.panels) do
        panel:setVisible(visible)
    end
    for node in pairs(state.activeSliderVisuals) do
        node.Visible = false
    end
end

function Runtime:setMousePosition(position)
    for _, panel in ipairs(private(self).panels) do
        if type(panel.setMousePosition) == "function" then
            panel:setMousePosition(position)
        end
    end
end

function Runtime:destroy()
    local state = PRIVATE[self]
    if not state then
        return
    end
    for index = #state.panels, 1, -1 do
        state.panels[index]:destroy()
    end
    table.clear(state.panels)
    PRIVATE[self] = nil
end

return Runtime
