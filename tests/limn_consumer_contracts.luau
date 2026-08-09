local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

Color3 = roblox.Color3
Vector2 = roblox.Vector2
Drawing = {
    Fonts = {
        Plex = 2,
    },
}

local limnPath = "vendor/Limn.lua"
local limnProvenance = fs.readFile("vendor/Limn.provenance")
assert(
    limnProvenance:find("commit=a560e5823bddda0ece824ddcdad87173ccf02496", 1, true)
        and limnProvenance:find(
            "sha256=6f929b41c2c1a7727a461989bb7d1cf55151289693805b1014a80060f1c3d126",
            1,
            true
        ),
    "Limn's vendored artifact must retain its immutable published provenance"
)
assert(
    not limnProvenance:find("d5d9369", 1, true),
    "Universal Hub must never pin the visually rejected overlapping-alpha Limn head"
)
local limnChunk, limnError = loadstring(fs.readFile(limnPath), limnPath)
local Limn = assert(limnChunk, limnError)()
assert(
    type(Limn.new) == "function",
    "Universal Hub must load Limn through its public runtime constructor"
)
local PresentationRuntime = require("../modules/presentation/Runtime")
local StandardPanels = require("../modules/presentation/StandardPanels")
local CosmeticsPanel = require("../modules/presentation/CosmeticsPanel")
local initSource = fs.readFile("init.lua")
local helpersLoadAt = assert(initSource:find("Helpers.load", 1, true))
local previousStopAt = assert(initSource:find("Session.stopPrevious", 1, true))
local runtimeCreateAt = assert(initSource:find("local drawingRuntime = Limn.new", 1, true))
local overlayCreateAt = assert(initSource:find("pcall(Overlay.new", 1, true))
assert(
    helpersLoadAt < previousStopAt
        and previousStopAt < runtimeCreateAt
        and runtimeCreateAt < overlayCreateAt,
    "Dependencies must validate before prior-session cleanup and all new Limn/UI resources"
)
assert(
    not initSource:find("environment.oh =", 1, true),
    "Universal Hub init must not install or replace environment.oh"
)
assert(
    initSource:find("MapPosition", 1, true)
        and initSource:find("return position + topLeftInset", 1, true),
    "Universal Hub must add the GUI inset to executor input before Limn hit-testing"
)
for _, path in ipairs({
    "games/Counterblox.lua",
    "games/rivals/Adapter.lua",
    "games/Town.lua",
}) do
    local gameSource = fs.readFile(path)
    assert(
        not gameSource:find("LimnPath", 1, true)
            and not gameSource:find("Drawing.new", 1, true)
            and not gameSource:find("DrawingImmediate", 1, true),
        path .. " must receive only scoped runtime/helper seams"
    )
end
local Store = require("../modules/Store")
local Overlay = require("../modules/Overlay")
local PresentationHost = require("../modules/PresentationHost")
local RivalsPresentation = require("../games/rivals/Presentation")

local function newSignal()
    local listeners = {}
    local signal = {}
    function signal:Connect(callback)
        table.insert(listeners, callback)
        local connection = {
            Connected = true,
        }
        function connection:Disconnect()
            if not self.Connected then
                return
            end
            self.Connected = false
            local index = table.find(listeners, callback)
            if index then
                table.remove(listeners, index)
            end
        end
        return connection
    end
    function signal:Fire(...)
        for _, callback in ipairs(table.clone(listeners)) do
            callback(...)
        end
    end
    function signal:count()
        return #listeners
    end
    return signal
end

local objects = {}
local drawing = {
    new = function(kind)
        local object = {
            Kind = kind,
            Removed = false,
            TextBounds = Vector2.new(80, 14),
        }
        function object:Remove()
            self.Removed = true
        end
        table.insert(objects, object)
        return object
    end,
}
local input = {
    InputBegan = newSignal(),
    InputChanged = newSignal(),
    InputEnded = newSignal(),
}
local paintSignals = {}
local immediateDraws = {}
local drawingImmediate = {
    FilledCircle = function(position, radius)
        table.insert(immediateDraws, {
            kind = "circle",
            position = position,
            radius = radius,
        })
    end,
    FilledRectangle = function(position, size)
        table.insert(immediateDraws, {
            kind = "rectangle",
            position = position,
            size = size,
        })
    end,
    GetPaint = function(zIndex)
        paintSignals[zIndex] = paintSignals[zIndex] or newSignal()
        return paintSignals[zIndex]
    end,
}
local guiInset = Vector2.new(0, 58)
local runtime = Limn.new({
    Drawing = drawing,
    DrawingImmediate = drawingImmediate,
    Vector2 = Vector2,
    Input = {
        MapPosition = function(position)
            return position + guiInset
        end,
        Processed = "allow",
    },
})
assert(
    type(runtime.createSegmentedControl) == "function"
        and type(runtime.createKeybindControl) == "function",
    "Universal Hub page controls must consume Limn's published segmented and keybind interfaces"
)
local contractCanvas = runtime:createCanvas()
local labelColor = Color3.fromRGB(170, 178, 184)
local selectedLabelColor = Color3.fromRGB(160, 225, 194)
local segmented = runtime:createSegmentedControl(contractCanvas, {
    CornerRadius = 4,
    Options = {
        { Label = "Combat", Value = "combat" },
        { Label = "Visuals", Value = "visuals" },
    },
    Position = Vector2.new(12, 12),
    Size = Vector2.new(160, 24),
    Style = {
        Label = { Color = labelColor },
        SelectedLabel = { Color = selectedLabelColor },
    },
    Value = "combat",
})
local function liveText(label)
    local matches = {}
    for _, object in ipairs(objects) do
        if object.Kind == "Text" and object.Text == label and object.Removed ~= true then
            table.insert(matches, object)
        end
    end
    return matches
end
local function visibleText(label)
    local matches = {}
    for _, object in ipairs(liveText(label)) do
        if object.Visible ~= false then
            table.insert(matches, object)
        end
    end
    return matches
end
assert(
    #liveText("Combat") == 1 and #liveText("Visuals") == 1,
    "Limn segmented controls must own exactly one Text primitive per labeled option"
)
local roundedTriangles = 0
for _, object in ipairs(objects) do
    if object.Kind == "Triangle" and object.Removed ~= true then
        roundedTriangles = roundedTriangles + 1
    end
end
assert(roundedTriangles > 0, "Positive CornerRadius must use Limn-owned retained rounded geometry")
assert(
    liveText("Combat")[1].Color == selectedLabelColor
        and liveText("Visuals")[1].Color == labelColor,
    "Limn SelectedLabel must style only the selected option's owned label"
)
local segmentedChanges = 0
segmented.Changed:Connect(function()
    segmentedChanges = segmentedChanges + 1
end)
segmented:setLayout({
    Position = Vector2.new(24, 24),
    Size = Vector2.new(180, 24),
})
assert(
    segmented:getValue() == "combat" and segmentedChanges == 0,
    "Limn segmented layout must preserve the selected state without emitting Changed"
)
segmented:setVisible(false)
assert(segmented:getValue() == "combat", "Hiding a segmented control must preserve its value")
segmented:setVisible(true)

local keybind = runtime:createKeybindControl(contractCanvas, {
    Label = "Menu key",
    Position = Vector2.new(12, 48),
    Size = Vector2.new(180, 24),
    Value = "RightShift",
})
local keybindChanges = 0
keybind.Changed:Connect(function()
    keybindChanges = keybindChanges + 1
end)
assert(keybind:begin() and keybind:getState() == "listening")
keybind:setVisible(false)
assert(
    keybind:getValue() == "RightShift"
        and keybind:getState() == "idle"
        and not keybind:begin()
        and keybindChanges == 0,
    "Hiding a keybind must cancel capture, reject new capture, and preserve its binding"
)
keybind:setVisible(true)
keybind:setLayout({
    Position = Vector2.new(24, 60),
    Size = Vector2.new(180, 24),
})
assert(
    keybind:getValue() == "RightShift" and keybindChanges == 0,
    "Limn keybind layout must preserve its binding without emitting Changed"
)
segmented:destroy()
segmented:destroy()
keybind:destroy()
keybind:destroy()
contractCanvas:destroy()
local store = Store.new({
    activeWeapon = "Test Rifle",
    cosmeticsOpen = false,
    menuVisible = true,
    observations = {},
    settings = {
        aimSmoothness = 0,
        chams = false,
        fov = 180,
        fovCircle = true,
        fullScreenAim = false,
        headshotRate = 0,
        maximumFov = 500,
        minimumFov = 40,
        missRate = 0,
        silentAim = false,
        triggerBot = false,
    },
    status = "Ready",
    utilityObservations = {},
})
local menuChanges = {}
local captures = {}
local optionChanges = {}
local overlay = Overlay.new({
    capabilities = {
        "aimSmoothness",
        "silentAim",
        "triggerBot",
    },
    cosmetics = false,
    gameLabel = "Limn Contract",
    presentation = RivalsPresentation,
    presentationHost = PresentationHost,
    presentationParts = {
        cosmetics = CosmeticsPanel,
        standard = StandardPanels,
    },
    presentationRuntime = PresentationRuntime,
    getCamera = function()
        return {
            ViewportSize = Vector2.new(1280, 720),
        }
    end,
    inputService = input,
    limn = runtime,
    setFov = function() end,
    setInputCaptured = function(captured)
        table.insert(captures, captured)
    end,
    setMenuVisible = function(visible)
        table.insert(menuChanges, visible)
    end,
    setOption = function(name, value)
        table.insert(optionChanges, {
            name = name,
            value = value,
        })
    end,
    setRate = function(name, value)
        store:Patch({
            settings = {
                [name] = value,
            },
        })
    end,
    store = store,
})

assert(overlay.available == true)
assert(captures[1] == true)
assert(
    #liveText("Combat") == 1 and #liveText("Radius") == 1,
    "Universal Hub must not overlay duplicate active tab or segmented labels"
)
assert(
    #visibleText("Radius") == 1
        and #visibleText("Fullscreen") == 1
        and visibleText("Radius")[1].Font == Drawing.Fonts.Plex
        and visibleText("Radius")[1].Size == 13
        and visibleText("Radius")[1].Color == Color3.fromRGB(160, 225, 194)
        and visibleText("Fullscreen")[1].Font == Drawing.Fonts.Plex
        and visibleText("Fullscreen")[1].Size == 13
        and visibleText("Fullscreen")[1].Color == Color3.fromRGB(243, 243, 244),
    "The real Limn-owned Target Mode labels must receive Universal Hub's Plex text hierarchy"
)
local triggerRow = overlay.controls.options.triggerBot.row
local triggerScreenPosition = triggerRow.Position + triggerRow.Size / 2
local triggerInputPosition = triggerScreenPosition - guiInset
local panelPosition = overlay.controls.panel.Position
local triggerMouse = {
    Position = triggerInputPosition,
    UserInputType = "MouseButton1",
}
input.InputBegan:Fire(triggerMouse, true)
input.InputChanged:Fire({
    Position = triggerInputPosition + Vector2.new(8, 0),
    UserInputType = "MouseMovement",
}, true)
input.InputEnded:Fire(triggerMouse, true)
assert(
    optionChanges[1] and optionChanges[1].name == "triggerBot",
    "Clicking the rendered Trigger Bot row must not select the control one GUI inset above it"
)
assert(
    overlay.controls.panel.Position == panelPosition,
    "Dragging a rendered option must not capture or move the full panel"
)
local smoothness = overlay.controls.rates.aimSmoothness
local smoothnessStart = smoothness.hit.Position + Vector2.new(24, smoothness.hit.Size.Y / 2)
local smoothnessEnd = smoothness.hit.Position + Vector2.new(132, smoothness.hit.Size.Y / 2)
local smoothnessMouse = {
    Position = smoothnessStart - guiInset,
    UserInputType = "MouseButton1",
}
input.InputBegan:Fire(smoothnessMouse, true)
input.InputChanged:Fire({
    Position = smoothnessEnd - guiInset,
    UserInputType = "MouseMovement",
}, true)
assert(
    smoothness.fill.Visible == false and smoothness.knob.Visible == false,
    "Captured slider must hide only its retained fill/thumb while immediate paint is active"
)
store:Patch({ status = "Live telemetry update" })
assert(
    smoothness.fill.Visible == false and smoothness.knob.Visible == false,
    "Frame-driven store patches must not reveal stale retained visuals during captured paint"
)
paintSignals[206]:Fire()
assert(
    immediateDraws[#immediateDraws - 1].kind == "rectangle"
        and immediateDraws[#immediateDraws].kind == "circle"
        and immediateDraws[#immediateDraws].position.X > smoothness.track.Position.X + 120,
    "Bundled Limn must paint the active slider from the latest mapped pointer event"
)
local activeDrawCount = #immediateDraws
input.InputEnded:Fire({
    Position = smoothnessEnd - guiInset,
    UserInputType = "MouseButton1",
}, true)
paintSignals[206]:Fire()
assert(
    #immediateDraws == activeDrawCount
        and smoothness.fill.Visible == true
        and smoothness.knob.Visible == true,
    "Slider release must stop immediate paint and restore the current retained fill/thumb"
)
local panel = overlay.controls.panel
local clickPosition = panel.Position + Vector2.new(4, 4) - guiInset
local mouse = {
    Position = clickPosition,
    UserInputType = "MouseButton1",
}
input.InputBegan:Fire(mouse, true)
input.InputEnded:Fire(mouse, true)
assert(
    overlay.panelDragOffset == Vector2.new(4, 4),
    "Processed menu input must reach the Limn-owned panel after Universal Hub sinks it"
)
assert(
    panel.Position == Vector2.new(846, 20),
    "Universal Hub must retain physical-screen Drawing coordinates while mapping input"
)

overlay:destroy()
assert(captures[#captures] == false)
assert(input.InputBegan:count() == 0 and input.InputChanged:count() == 0 and input.InputEnded:count() == 0)
for _, object in ipairs(objects) do
    assert(object.Removed == true, "Destroying the overlay must remove every Limn-owned drawing")
end

local unavailableRuntime = Limn.new({
    Drawing = {
        new = function(kind)
            if kind == "Circle" then
                error("unsupported Circle")
            end
            local object = {}
            function object:Remove() end
            return object
        end,
    },
    Vector2 = Vector2,
})
local unavailableOverlay = Overlay.new({
    capabilities = {},
    cosmetics = false,
    gameLabel = "Unavailable",
    getCamera = function()
        return {
            ViewportSize = Vector2.new(1280, 720),
        }
    end,
    limn = unavailableRuntime,
    store = store,
})
assert(unavailableOverlay.available == false)
assert(table.find(unavailableOverlay.missingPrimitives, "Circle") ~= nil)

local triangleUnavailableRuntime = Limn.new({
    Drawing = {
        new = function(kind)
            if kind == "Triangle" then
                error("unsupported Triangle")
            end
            local object = {}
            function object:Remove() end
            return object
        end,
    },
    Vector2 = Vector2,
})
local triangleUnavailableOverlay = Overlay.new({
    capabilities = {},
    cosmetics = false,
    gameLabel = "Unavailable rounded controls",
    getCamera = function()
        return { ViewportSize = Vector2.new(1280, 720) }
    end,
    limn = triangleUnavailableRuntime,
    store = store,
})
assert(
    triangleUnavailableOverlay.available == false
        and table.find(triangleUnavailableOverlay.missingPrimitives, "Triangle") ~= nil,
    "The rounded segmented design must fail at the UH capability gate when retained Triangle is unavailable"
)
unavailableOverlay:render({}, Vector2.new(0, 0), {})
unavailableOverlay:destroy()

store:Destroy()
print("limn-consumer-contracts-ok")
