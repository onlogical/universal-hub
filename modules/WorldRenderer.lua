local WorldRenderer = {}
WorldRenderer.__index = WorldRenderer

function WorldRenderer.new(context, limnRenderer, nativeRenderer)
    assert(type(context) == "table" and context.store, "WorldRenderer requires context.store")
    assert(type(limnRenderer) == "table" and type(limnRenderer.render) == "function")
    assert(type(nativeRenderer) == "table" and type(nativeRenderer.render) == "function")
    local support = {}
    for key, value in pairs(limnRenderer.optionSupport or {}) do
        support[key] = value
    end
    support.chams = true
    return setmetatable({
        context = context,
        limn = limnRenderer,
        native = nativeRenderer,
        optionSupport = support,
        destroyed = false,
    }, WorldRenderer)
end

function WorldRenderer:setPolicy(policy)
    if not self.destroyed then
        self.native:setPolicy(policy)
    end
end

function WorldRenderer:render(observations, mousePosition, utilityObservations)
    if self.destroyed then
        return
    end
    local settings = self.context.store:Get().settings or {}
    if self.context.nativeWorldSupported ~= false and settings.worldRenderer == "native" then
        local remainder = self.native:render(observations)
        self.limn:render(remainder or {}, mousePosition, utilityObservations)
    else
        self.native:render(nil)
        self.limn:render(observations, mousePosition, utilityObservations)
    end
end

function WorldRenderer:destroy()
    if self.destroyed then
        return
    end
    self.destroyed = true
    self.native:destroy()
    self.limn:destroy()
end

return WorldRenderer
