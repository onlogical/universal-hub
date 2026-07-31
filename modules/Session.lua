local Session = {}
Session.__index = Session

function Session.stopPrevious(environment)
    assert(type(environment) == "table", "Hub session cleanup requires an environment")
    local previous = environment.UniversalHubSession
    if type(previous) ~= "table" or type(previous.stop) ~= "function" then
        return nil
    end

    local helpers = environment.oh
    local resources = type(helpers) == "table" and helpers.Resources or nil
    local legacyIndex = type(resources) == "table" and table.find(resources, previous) or nil

    previous:stop()
    if environment.UniversalHubSession == previous then
        environment.UniversalHubSession = nil
    end
    if legacyIndex and resources[legacyIndex] == previous then
        table.remove(resources, legacyIndex)
    end
    return previous
end

function Session.new(options)
    assert(options and options.environment, "Hub session requires an environment")
    assert(options.store, "Hub session requires a store")
    assert(options.overlay, "Hub session requires an overlay")
    assert(options.adapter, "Hub session requires an adapter")

    local self = setmetatable({
        adapter = options.adapter,
        environment = options.environment,
        inputCapture = options.inputCapture,
        overlay = options.overlay,
        resources = {},
        settingsChanged = options.settingsChanged,
        stopped = false,
        store = options.store,
    }, Session)

    self.environment.UniversalHubSession = self
    return self
end

function Session:Add(cleanup)
    assert(type(cleanup) == "function", "Hub cleanup must be a function")
    if self.stopped then
        cleanup()
        return cleanup
    end

    table.insert(self.resources, cleanup)
    return cleanup
end

function Session:patchSettings(patch, persist)
    self.store:Patch({ settings = patch })
    if persist ~= false and self.settingsChanged then
        self.settingsChanged(self.store:Get().settings)
    end
end

function Session:setOption(name, enabled)
    local state = self.store:Get()
    assert(state.settings[name] ~= nil, "Unknown hub option: " .. tostring(name))
    self:patchSettings({
        [name] = enabled == true,
    })
end

function Session:setFov(value, persist)
    local state = self.store:Get()
    local settings = state.settings
    self:patchSettings({
        fov = math.clamp(value, settings.minimumFov, settings.maximumFov),
    }, persist)
end

function Session:setRate(name, value, persist)
    assert(
        name == "aimSmoothness" or name == "headshotRate" or name == "missRate",
        "Unknown hub rate: " .. tostring(name)
    )
    self:patchSettings({
        [name] = math.clamp(math.round(value), 0, 100),
    }, persist)
end

function Session:setCosmeticsOpen(open)
    self.store:Patch({
        cosmeticsOpen = open == true,
    })
end

function Session:setCosmeticMode(mode)
    self.store:Patch({
        cosmeticMode = mode == "gloves" and "gloves" or "weapon",
    })
end

function Session:setMenuVisible(visible)
    self.store:Patch({
        menuVisible = visible == true,
    })
end

function Session:toggleMenu()
    self:setMenuVisible(not self.store:Get().menuVisible)
end

function Session:stop()
    if self.stopped then
        return
    end
    self.stopped = true

    for index = #self.resources, 1, -1 do
        pcall(self.resources[index])
    end
    table.clear(self.resources)

    if self.adapter and type(self.adapter.stop) == "function" then
        pcall(self.adapter.stop, self.adapter)
    end
    if self.overlay and type(self.overlay.destroy) == "function" then
        pcall(self.overlay.destroy, self.overlay)
    end
    if self.inputCapture and type(self.inputCapture.Destroy) == "function" then
        pcall(self.inputCapture.Destroy, self.inputCapture)
    end
    if self.store and type(self.store.Destroy) == "function" then
        self.store:Destroy()
    end

    if self.environment.UniversalHubSession == self then
        self.environment.UniversalHubSession = nil
    end
end

Session.Destroy = Session.stop

return Session
