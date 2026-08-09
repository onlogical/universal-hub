local NativeMenu = {}
NativeMenu.__index = NativeMenu

function NativeMenu.new(context)
    assert(type(context) == "table", "NativeMenu requires context")
    assert(type(context.nativeMenu) == "table" and type(context.nativeMenu.mountUniversalHubMenu) == "function", "NativeMenu requires the compiled Prism artifact")
    assert(type(context.presentation) == "table" and type(context.presentation.mount) == "function", "NativeMenu requires a game presentation")
    assert(type(context.catalog) == "table" and type(context.catalog.new) == "function", "NativeMenu requires PresentationCatalog")
    assert(context.store, "NativeMenu requires Store")
    assert(typeof(context.uiParent) == "Instance", "NativeMenu requires a gethui() parent")

    local existing = context.uiParent:FindFirstChild("UniversalHubNative")
    if existing then
        existing:Destroy()
    end

    local createInstance = context.createInstance or Instance.new
    local screenGui = createInstance("ScreenGui")
    screenGui.Name = "UniversalHubNative"
    screenGui.DisplayOrder = 1000
    screenGui.IgnoreGuiInset = true
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
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
    local handle = context.nativeMenu.mountUniversalHubMenu(screenGui, model)
    local self = setmetatable({
        catalog = catalog,
        context = context,
        destroyed = false,
        gui = screenGui,
        handle = handle,
        model = model,
        previewObservation = function()
            return publishedPreview
        end,
    }, NativeMenu)
    self.unsubscribe = context.store:Subscribe(function(state)
        if self.destroyed then
            return
        end
        self.model = self.catalog:model(state)
        self.handle.update(self.model)
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

function NativeMenu:previewObservations()
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

function NativeMenu:isCaptured()
    return not self.destroyed and self.context.store:Get().menuVisible ~= false
end

function NativeMenu:destroy()
    if self.destroyed then
        return
    end
    self.destroyed = true
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
    if self.handle then
        self.handle.destroy()
        self.handle = nil
    end
    if self.gui then
        self.gui:Destroy()
        self.gui = nil
    end
end

return NativeMenu
