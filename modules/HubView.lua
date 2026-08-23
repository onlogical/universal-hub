local HubView = {}
HubView.__index = HubView

function HubView.new(world, menu)
    assert(type(world) == "table" and type(world.render) == "function")
    assert(type(menu) == "table" and type(menu.destroy) == "function")
    return setmetatable({ world = world, menu = menu, destroyed = false }, HubView)
end

local function appended(values, additions)
    if not additions or #additions == 0 then
        return values
    end
    local result = {}
    for _, value in ipairs(values or {}) do
        table.insert(result, value)
    end
    for _, value in ipairs(additions) do
        table.insert(result, value)
    end
    return result
end

function HubView:render(observations, mousePosition, utilityObservations)
    if self.destroyed then
        return
    end
    local previewPlayers, previewUtilities = self.menu:previewObservations()
    self.world:render(
        appended(observations, previewPlayers),
        mousePosition,
        appended(utilityObservations, previewUtilities)
    )
end

function HubView:isCaptured()
    return not self.destroyed and self.menu:isCaptured()
end

function HubView:setMenu(menu)
    assert(type(menu) == "table" and type(menu.destroy) == "function")
    if self.destroyed then
        menu:destroy()
        return
    end
    if self.menu and self.menu ~= menu then
        self.menu:destroy()
    end
    self.menu = menu
end

function HubView:destroy()
    if self.destroyed then
        return
    end
    self.destroyed = true
    pcall(self.menu.destroy, self.menu)
    self.world:destroy()
end

return HubView
