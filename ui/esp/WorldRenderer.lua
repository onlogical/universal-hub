-- Two explicit ESP backends share this switch:
--   drawing   = Limn / Drawing API (ui/esp/DrawingRenderer)
--   highlights = Highlight + BillboardGui (ui/esp/HighlightRenderer)
-- The persisted setting remains worldRenderer = "limn" | "native".
local WorldRenderer = {}
WorldRenderer.__index = WorldRenderer

function WorldRenderer.new(context, drawingRenderer, highlightRenderer)
    assert(type(context) == "table" and context.store, "WorldRenderer requires context.store")
    assert(type(drawingRenderer) == "table" and type(drawingRenderer.render) == "function")
    assert(type(highlightRenderer) == "table" and type(highlightRenderer.render) == "function")
    local support = {}
    for key, value in pairs(drawingRenderer.optionSupport or {}) do
        support[key] = value
    end
    support.chams = true
    return setmetatable({
        context = context,
        drawing = drawingRenderer,
        highlights = highlightRenderer,
        optionSupport = support,
        destroyed = false,
    }, WorldRenderer)
end

function WorldRenderer:setPolicy(policy)
    if not self.destroyed then
        self.highlights:setPolicy(policy)
    end
end

function WorldRenderer:render(observations, mousePosition, utilityObservations)
    if self.destroyed then
        return
    end
    local settings = self.context.store:Get().settings or {}
    if self.context.highlightsSupported ~= false and settings.worldRenderer == "native" then
        local remainder = self.highlights:render(observations)
        self.drawing:render(remainder or {}, mousePosition, utilityObservations)
    else
        self.highlights:render(nil)
        self.drawing:render(observations, mousePosition, utilityObservations)
    end
end

function WorldRenderer:destroy()
    if self.destroyed then
        return
    end
    self.destroyed = true
    self.highlights:destroy()
    self.drawing:destroy()
end

return WorldRenderer
